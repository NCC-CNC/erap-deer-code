# Build the "WTW opportunity, protected areas erased" layer for
# erap-deer-code#18 (https://github.com/NCC-CNC/erap-deer-code/issues/18):
# redefines wtw_percent as % of the whole landscape (not % of the
# unprotected remainder), which only works cleanly if the WTW solution
# polygon itself is free of any real protected area the original 1km-grid
# prioritizr run missed -- otherwise that ground double-counts toward
# both protected_pcnt and the new wtw_percent. See the plan addendum
# "erap-deer-code#18" for the full reasoning.
#
# INPUTS, Canada_wtw_2026.tif, built by this
# repo's own "4_prioritizr.R" (data_prep/8 prioritizr/). That same script
# now also builds the no-Includes raster directly (Canada_wtw_2026.tif
# minus CPCAD_2025_NCCFSCA_20260428.tif, the matching current-generation
# Includes layer -- vetted, marks every 1km grid cell with >=50% overlap
# against the real vector CPCAD layer as included). That ~50%-threshold
# grid approximation is accepted for the WTW map's own Includes-masking
# (not for species-level protected-area figures, which use the true-vector
# intersection elsewhere in this repo -- see "7
# recalc_species_protected_km2.R" and the plan's "root cause of the
# grid-based Protected_Km2 error" addendum, which is about a different,
# unrelated raster this one shouldn't be confused with despite the similar
# name/lineage).
#
# Not expected to reproduce the old Canada_wtw_2024_noIncludes.tif-based
# counts recorded elsewhere in this repo's history (e.g. the plan's
# erap-deer-code#18 addendum) -- those numbers are specific to the
# superseded 2024 WTW map + a different-vintage Includes raster
# (Existing_Conservation.tif), not a target this real run needs to match.
#
# Steps:
#   1. Vectorize the pre-built no-Includes raster to polygon
#      (RasterToPolygon, NO_SIMPLIFY -- exact cell boundaries, not
#      smoothed, matching this project's general preference for precise
#      area/length figures over visual simplicity), keep only gridcode = 1
#      (the actual WTW opportunity cells; gridcode = 0 is discarded).
#
#   2. Dissolve into contiguous blobs (classic Dissolve, no group field --
#      just merges touching cells into fewer, larger polygons). Necessary
#      for practical performance: hundreds of thousands of individual
#      1km-cell squares would make the Erase in step 3 enormous and slow;
#      dissolving first is much cheaper than erasing per-cell.
#
#   3. Erase cpcad_ncc_dslv_2025 (this repo's true-vector CPCAD+NCC layer,
#      built by "3 prep_cpcad_ncc_2025.py") from the dissolved WTW
#      polygon -- classic arcpy.analysis.Erase, not PairwiseErase (your
#      decision -- this session has twice found real correctness bugs in
#      the "Pairwise" tool family specifically -- PairwiseIntersect's
#      silent 0-row failure at small scale, and conservation-profiles'
#      memory/-workspace non-determinism in PairwiseIntersect/
#      PairwiseDissolve -- so sticking with the slower-but-trusted classic
#      tool here rather than risk a third).
#
# Output feeds the not-yet-built 06_wtw.R: per your decision, wtw_area_km2
# switches from 1e_prioritizr_ecoregion_intersects.R's raster-based
# exact_extract() (against prioritization_wtw, the un-erased WTW raster)
# to a vector intersection of THIS output against each landscape, via the
# shared intersect_vector_values() (R/fct_intersect_vector_value.py) --
# then wtw_percent = wtw_area_km2 / landscape_km2 * 100 (the new formula
# from the erap-deer-code#18 addendum). Not a replacement for
# wtw_vector_path (that's 04_habitat.R's per-habitat WTW-overlap input, a
# separate pipeline step/concern) -- this output is specific to 06_wtw.R's
# own landscape-level figure. All intermediates write to this script's own
# working gdb, never "memory/" (see the "never use memory/" plan
# addendum) -- the vector intermediates are cleaned up at the end; the
# no-Includes raster itself lives in "4_prioritizr.R"'s own output now,
# not here, so there's nothing to keep or clean up on that front in this
# script anymore.

import arcpy
import os
import time

arcpy.env.overwriteOutput = True
start_time = time.time()

wtw_noincludes_source = r"C:\Users\marc.edwards\Documents\PROJECTS\ERAPs_v2\data_prep\prioritizr\ecozones\Canada_wtw_2026_noIncludes.tif"

# All data_prep script output lives in this project folder, not in the
# repo -- shared across every data_prep script that reads or writes GIS
# data (not just this one).
output_dir = r"C:\Users\marc.edwards\Documents\PROJECTS\ERAPs_v2\data_prep"
protected_gdb = os.path.join(output_dir, "protected_areas.gdb")
cpcad_ncc = os.path.join(protected_gdb, "cpcad_ncc_dslv_2025")

gdb = os.path.join(output_dir, "wtw.gdb")
if not arcpy.Exists(gdb):
    arcpy.management.CreateFileGDB(output_dir, "wtw.gdb")

polygon_raw   = os.path.join(gdb, "wtw_polygon_raw")
polygon_ones  = os.path.join(gdb, "wtw_polygon_ones")
dissolved     = os.path.join(gdb, "wtw_dissolved")
out_fc        = os.path.join(gdb, "wtw_erased_protected")

# wtw_noincludes_source carries an unnamed CRS (confirmed via arcpy.Describe:
# PROJCS["unknown",...]) despite its actual parameters matching this
# project's standard Albers exactly -- a gdalwarp/GDAL-written raster, not
# ArcGIS-native. DefineProjection just labels it correctly (no resampling,
# no coordinate shift) so RasterToPolygon's output carries a real, named
# CRS instead of propagating "unknown" into the final vector deliverable.
target_sr = arcpy.Describe(cpcad_ncc).spatialReference
arcpy.management.DefineProjection(wtw_noincludes_source, target_sr)

print("vectorizing (RasterToPolygon, no simplify)...")
arcpy.conversion.RasterToPolygon(wtw_noincludes_source, polygon_raw, "NO_SIMPLIFY", "Value")
print("  ->", arcpy.management.GetCount(polygon_raw)[0], "raw polygons (all gridcodes)")

print("keeping only gridcode = 1 (WTW opportunity cells)...")
ones = arcpy.management.SelectLayerByAttribute(polygon_raw, "NEW_SELECTION", "gridcode = 1")
arcpy.management.CopyFeatures(ones, polygon_ones)
print("  ->", arcpy.management.GetCount(polygon_ones)[0], "polygons")

print("dissolving into contiguous blobs...")
arcpy.management.Dissolve(polygon_ones, dissolved, multi_part="SINGLE_PART")
print("  ->", arcpy.management.GetCount(dissolved)[0], "features")

print("erasing cpcad_ncc_dslv_2025 (protected areas) from the WTW polygon...")
print("  cpcad features:", arcpy.management.GetCount(cpcad_ncc)[0])
arcpy.analysis.Erase(dissolved, cpcad_ncc, out_fc)
print("wrote", out_fc, "| count:", arcpy.management.GetCount(out_fc)[0])

print("cleanup...")
arcpy.management.Delete([polygon_raw, polygon_ones, dissolved])

print("total elapsed:", round(time.time() - start_time, 1), "sec")
