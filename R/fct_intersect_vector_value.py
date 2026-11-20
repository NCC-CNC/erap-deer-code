# Vector-vector intersection helpers, shared with conservation-profiles.
#
# intersect_vector_values() replaces the old intersect_vector_value(): same
# classic arcpy.analysis.Intersect + Dissolve approach, but dissolves BY
# landscape_id instead of to one global total, so it returns
# {landscape_id: value} for every landscape in `boundary` -- correct and
# equally fast whether `boundary` has 1 landscape (conservation-profiles'
# custom-landscape case) or 149 (this repo's ecoregions run). See the plan
# addendum "resolved -- one bulk-pass function replaces the loop-vs-bulk
# choice" for the full reasoning.
#
# intersect_with_fallback() uses PairwiseIntersect, guarded, not plain
# classic Intersect -- classic Intersect alone was too slow against inputs
# the size of habitat_peatlands (17M+ features). Three real Pairwise bugs
# turned up earlier in this project: PairwiseIntersect silently returning 0
# rows at small scale (issue #24), memory/-workspace non-determinism in
# PairwiseIntersect/PairwiseDissolve (conservation-profiles commit d5a4c94),
# and PairwiseIntersect raising ERROR 160385 ("workspace is read only")
# against a freshly-rebuilt input geodatabase. The memory/-workspace bug is
# moot here (everything below writes to arcpy.env.scratchGDB, never
# memory/, and classic Intersect/Dissolve hit that same bug in memory/ --
# it was never Pairwise-specific). The other two are guarded explicitly in
# intersect_with_fallback(): a 0-row result retries with classic Intersect
# to confirm it's real, and ERROR 160385 falls back to classic Intersect
# outright.
#
# Dissolve stays classic (arcpy.management.Dissolve, via
# dissolve_with_repair() below), not PairwiseDissolve, as the FIRST thing
# tried -- Dissolve isn't the slow step, and classic Intersect/Dissolve
# raising a loud ERROR 160196 on self-intersecting geometry is exactly how
# the habitat_wetland and habitat_peatlands invalid-topology bugs got caught
# in the first place. PairwiseIntersect is known to tolerate invalid
# topology silently rather than erroring (see "13 repair_wetland_geometry.py"'s
# header) -- useful for speed, but it means a future bad-geometry input
# could produce a wrong answer with no error at all, rather than a loud
# failure to investigate. That's an accepted tradeoff for the Intersect step
# now that it's guarded for the two known Pairwise bugs, not a reason to
# avoid Pairwise here entirely -- just a reason classic Dissolve still runs
# first every time, with PairwiseDissolve only as dissolve_with_repair()'s
# last-resort tier (see that function's docstring) once every classic-tool
# option has already failed and raised its own loud error.
#
# Even on clean inputs, Intersect's own output can occasionally come out
# with self-intersecting geometry that then fails Dissolve with ERROR 160196
# ("Invalid Topology") -- seen with habitat_peatlands (17M+ features) and
# habitat_lakes (14.6M+ features), both against the Priority Landscapes
# boundary, with every input independently confirmed clean via
# CheckGeometry. dissolve_with_repair() below catches that specific error
# and retries after a RepairGeometry pass, rather than repairing
# unconditionally (too slow on inputs this size) -- ESRI validation first,
# then the stricter OGC validation if ESRI's repair still isn't enough
# (needed for the habitat_lakes case specifically).
#
# habitat_lakes went a step further: PairwiseIntersect's output there passed
# CheckGeometry cleanly (0 problems) both before and after ESRI/OGC repair,
# yet still failed Dissolve every time -- repair can't fix a problem
# CheckGeometry doesn't flag. Classic Intersect on the identical two inputs
# produced different output that CheckGeometry DID flag (13 self-
# intersections), and dissolved on the first try anyway. So
# dissolve_with_repair()'s third tier, when both repair tiers fail, is to
# redo the intersect step itself with classic Intersect and dissolve that
# instead -- not another repair pass on the Pairwise output.
#
# habitat_peatlands went further still: one specific landscape ("LP Boreal",
# 2.4M features, isolated by splitting the dissolve per landscape to find
# it) failed ALL of the above, plus MultipartToSinglepart and Integrate
# (0.001m tolerance) tried directly against it -- the other 28 landscapes in
# the same run all dissolved fine with plain classic Dissolve, so this
# wasn't a scale problem, just that one landscape's geometry. PairwiseDissolve
# succeeds on it, with a summed area matching the raw undissolved features
# exactly (0.0000% difference) -- confirmed deliberately, since silently
# trusting Pairwise's output here would repeat the exact risk this file
# otherwise avoids by keeping Dissolve classic. It's dissolve_with_repair()'s
# fourth and final tier: every classic-tool option still runs and still
# raises its own loud error first, on every call -- this only engages once
# all of them are already exhausted.
#
# Porting this file back into conservation-profiles replaces the old
# per-landscape intersect_vector_value(); call sites there change from
# `x <- intersect_vector_value(...)` to
# `x <- intersect_vector_values(...)[[landscape_id]]` -- see
# CONSERVATION_PROFILES_CHANGES.md (gitignored, repo root) for the tracked
# list of exactly what needs to change there. Note that conservation-profiles
# independently fixed a "memory/" workspace non-determinism bug on the OLD
# intersect_vector_value() (commit d5a4c94) since this file was first built
# here -- that fix (scratch-gdb intermediates, uuid-tagged names, try/finally
# cleanup) is already folded into intersect_vector_values() below, so porting
# this file replaces d5a4c94's fix with an equivalent one, not a regression.

import arcpy
import os
import sys
import uuid

arcpy.env.overwriteOutput = True


def set_output_projection(reference_path):
    """Sets arcpy's output coordinate system to match a reference dataset,
    so vector intersect outputs land in the same projection as the rest of
    the pipeline."""
    arcpy.env.outputCoordinateSystem = arcpy.Describe(reference_path).spatialReference


def intersect_with_fallback(inputs, out_fc):
    """PairwiseIntersect (faster than classic Intersect, especially against
    large inputs like habitat_peatlands' 17M+ features), with two guards
    against its known failure modes -- see the module-level comment above
    for the history behind both:

    1. ERROR 160385 ("workspace is read only"): caught directly, falls back
       to classic Intersect outright.
    2. Silent 0-row result (#24): PairwiseIntersect can return 0 rows even
       where a real overlap exists, with no error at all. A 0-row result
       here is re-run with classic Intersect to confirm it's genuinely
       empty rather than trusting it -- costs nothing extra in the normal
       (nonzero) case.

    Kept as its own function (rather than inlining the call at each call
    site) so both intersect_vector_values() and intersect_vector_geoms()
    share one place to change tools again if needed.
    """
    try:
        arcpy.analysis.PairwiseIntersect(inputs, out_fc)
    except arcpy.ExecuteError as e:
        if "160385" not in str(e):
            raise
        arcpy.analysis.Intersect(inputs, out_fc)
        return out_fc

    if int(arcpy.management.GetCount(out_fc)[0]) == 0:
        arcpy.analysis.Intersect(inputs, out_fc)

    return out_fc


def dissolve_with_repair(fc, out_fc, dissolve_field, reintersect_inputs=None):
    """Classic arcpy.management.Dissolve, with a repair-and-retry fallback.
    Intersect's own output can come out with self-intersecting geometry even
    when both its inputs pass CheckGeometry cleanly -- seen with
    habitat_peatlands (17M+ features) against the Priority Landscapes
    boundary, and again with habitat_lakes (14.6M+ features) against the
    same boundary, both ERROR 160196 on Dissolve. RepairGeometry only runs
    when Dissolve actually fails this way, not on every call, since
    unconditionally repairing a layer that size would be slow and usually
    unnecessary.

    Tries RepairGeometry's default "ESRI" validation first, then falls back
    to the stricter "OGC" validation if ESRI's repair still leaves Dissolve
    failing. For habitat_lakes, neither was enough: PairwiseIntersect's
    output there passed CheckGeometry cleanly before AND after both repair
    passes, yet Dissolve kept failing anyway -- whatever is wrong with that
    geometry isn't something CheckGeometry/RepairGeometry can see, so no
    amount of repairing it will help.

    Pass reintersect_inputs (the two feature classes that were intersected
    to produce fc) to enable the next fix: redo the intersect with classic
    arcpy.analysis.Intersect instead of Pairwise, and dissolve that. Classic
    Intersect on habitat_lakes' identical inputs produced different output
    -- CheckGeometry flagged 13 self-intersections in it, more than
    Pairwise's "clean" output -- but it dissolved on the first try
    regardless. Without reintersect_inputs, that tier is skipped and the
    OGC-repair failure just propagates.

    habitat_peatlands' "LP Boreal" landscape (2.4M features) went past even
    that: still ERROR 160196 after the classic reintersect, and after
    MultipartToSinglepart and Integrate (0.001m tolerance) on top of that --
    whatever's wrong with it is invisible to CheckGeometry/RepairGeometry
    and untouched by precision fixes. PairwiseDissolve succeeds on it, with
    a summed area that matches the raw undissolved features exactly (0.0000%
    difference), so it's the true last resort here: classic Dissolve, both
    repair tiers, and the reintersect all still run first and all still
    raise their own loud errors on an ordinary bad-geometry input -- this
    only engages once every classic-tool option is already exhausted.
    """
    try:
        arcpy.management.Dissolve(fc, out_fc, dissolve_field)
        return
    except arcpy.ExecuteError as e:
        if "160196" not in str(e):
            raise

    try:
        arcpy.management.RepairGeometry(fc, "DELETE_NULL", "ESRI")
        arcpy.management.Dissolve(fc, out_fc, dissolve_field)
        return
    except arcpy.ExecuteError as e:
        if "160196" not in str(e):
            raise

    try:
        arcpy.management.RepairGeometry(fc, "DELETE_NULL", "OGC")
        arcpy.management.Dissolve(fc, out_fc, dissolve_field)
        return
    except arcpy.ExecuteError as e:
        if "160196" not in str(e) or reintersect_inputs is None:
            raise

    try:
        arcpy.analysis.Intersect(reintersect_inputs, fc)
        arcpy.management.Dissolve(fc, out_fc, dissolve_field)
        return
    except arcpy.ExecuteError as e:
        if "160196" not in str(e):
            raise

    arcpy.analysis.PairwiseDissolve(fc, out_fc, dissolve_field)


def intersect_vector_values(input_fc, boundary, landscape_id_field):
    """Computes the area (polygons, ha) or length (polylines, km) of
    input_fc within boundary, per distinct landscape_id_field value in
    boundary -- i.e. "how much of input_fc falls in each landscape". Pass a
    list for boundary (e.g. [landscape_fc, protected_fc]) to chain through
    more than one boundary at once (habitat ∩ landscape ∩ protected);
    Intersect only accepts two inputs per call, so multiple boundaries are
    applied as a chain of pairwise intersects, same as the original
    intersect_vector_value().

    Returns {landscape_id: value}, always a dict -- even for a single
    landscape (e.g. conservation-profiles' custom-landscape case), which
    dissolving by landscape_id_field naturally collapses to one group. That
    field must exist on the *last* boundary in the chain (the landscape/AOI
    itself, not any intermediate protected/wtw boundary).

    Intermediates are written to arcpy's scratch file geodatabase
    (arcpy.env.scratchGDB), not the "memory/" workspace -- conservation-profiles
    found intersects/dissolves into memory/ non-deterministic (identical
    calls returned different areas, dropping up to ~6% of habitat in chained
    landscape x protected/WTW intersects), with both PairwiseIntersect and
    classic Intersect, parallel processing on or off (see that repo's commit
    d5a4c94, "Avoid use of memory for intermediate files..."). Writing to a
    file gdb gave identical results on every repeat there. Names carry a
    per-call uuid tag since the scratch gdb, unlike memory/, is shared
    across concurrently running processes.

    Dissolve here is classic arcpy.management.Dissolve, not PairwiseDissolve
    -- see the module-level comment at the top of this file for why. Goes
    through dissolve_with_repair() rather than calling Dissolve directly,
    since Intersect's own output can occasionally need a RepairGeometry
    pass before it will dissolve -- see that function's docstring.
    """
    shape_type = arcpy.Describe(input_fc).shapeType
    if shape_type == "Polygon":
        query = "!shape.area@hectares!"
    elif shape_type == "Polyline":
        query = "!shape.length@kilometers!"
    else:
        sys.exit(f"Unknown shape type\ndataset path: {input_fc}\nshape type: {shape_type}")

    boundaries = boundary if isinstance(boundary, list) else [boundary]

    scratch = arcpy.env.scratchGDB
    tag = uuid.uuid4().hex[:8]
    dissolved = os.path.join(scratch, f"d_{tag}")

    current = input_fc
    intermediates = []
    last_inputs = None
    try:
        for i, b in enumerate(boundaries):
            out = os.path.join(scratch, f"i{i}_{tag}")
            intermediates.append(out)
            last_inputs = [current, b]
            current = intersect_with_fallback(last_inputs, out)

        intermediates.append(dissolved)
        dissolve_with_repair(current, dissolved, landscape_id_field, reintersect_inputs=last_inputs)
        arcpy.management.AddField(dissolved, "calculated_value", "DOUBLE")
        arcpy.management.CalculateField(dissolved, "calculated_value", query)

        values = {}
        with arcpy.da.SearchCursor(dissolved, [landscape_id_field, "calculated_value"]) as cursor:
            for lid, val in cursor:
                values[lid] = round(val, 4)
    finally:
        for out in intermediates:
            if arcpy.Exists(out):
                arcpy.management.Delete(out)

    return values


def intersect_vector_geoms(landscape_fc, clip_fc, landscape_id_field):
    """Like intersect_vector_values(), but for callers that need the actual
    clipped geometry afterward (e.g. to exact_extract a raster against it),
    not just a summed area -- 03_protected_intactness.R/04_habitat.R use
    this to build "protected area within each landscape"/"WTW opportunity
    within each landscape" once, then read the result into R and bulk
    exact_extract pressure/forest rasters against it per landscape_id, one
    call for every landscape at once instead of looping.

    Writes landscape_fc ∩ clip_fc, dissolved by landscape_id_field, to a
    new feature class in arcpy's scratch gdb and returns its path -- unlike
    intersect_vector_values()'s intermediates, this one is NOT deleted
    before returning, since the caller still needs to read it. Call
    delete_fc() on the returned path once done with it. A landscape with
    no overlap simply has no row in the result; callers should treat a
    missing landscape_id as 0, not an error.
    """
    scratch = arcpy.env.scratchGDB
    tag = uuid.uuid4().hex[:8]
    intersected = os.path.join(scratch, f"x_{tag}")
    out_fc = os.path.join(scratch, f"g_{tag}")
    try:
        intersect_with_fallback([landscape_fc, clip_fc], intersected)
        dissolve_with_repair(intersected, out_fc, landscape_id_field, reintersect_inputs=[landscape_fc, clip_fc])
    finally:
        if arcpy.Exists(intersected):
            arcpy.management.Delete(intersected)
    # forward slashes -- R's read_feature() splits on the literal substring
    # ".gdb/", which a raw Windows backslash path (arcpy.env.scratchGDB's
    # native form) would never match
    return out_fc.replace("\\", "/")


def delete_fc(path):
    """Deletes an arcpy dataset -- used by R callers to clean up a
    persistent output from intersect_vector_geoms() once they're done
    reading it (e.g. after exact_extract()'ing a raster against it)."""
    if arcpy.Exists(path):
        arcpy.management.Delete(path)
