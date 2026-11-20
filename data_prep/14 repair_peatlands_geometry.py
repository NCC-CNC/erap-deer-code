# Repairs invalid topology in the local habitat.gdb/habitat_peatlands feature
# class (self-intersections/bad ring ordering -- same symptom class as
# "13 repair_wetland_geometry.py"'s wetland fix), found when the main R
# pipeline's classic arcpy.management.Dissolve (R/fct_intersect_vector_value.py)
# raised ERROR 160196 ("Invalid Topology") while intersecting habitat_peatlands
# during a priority-landscape run. Classic Intersect/Dissolve enforce valid
# topology; the PairwiseIntersect/PairwiseDissolve this pipeline used before
# tolerated it silently.
#
# Runs CheckGeometry before AND after the repair, printed to console --
# if the "before" count comes back 0, habitat_peatlands was not actually the
# problem (don't trust this script fixed anything just because it ran; read
# the printed counts).
#
# habitat_peatlands keeps its original name/path (R/fct_intersect_vector_value.py's
# callers, and setup_ecoregions.toml's/setup_priority_landscapes.toml's
# cfg$habitat_vector$habitat_peatlands, both point at it unchanged). The
# pre-repair version is saved alongside it as habitat_peatlands_broken for
# reference, not deleted.
#
# Local fix only -- does not touch "10 gather_habitat_data.py"'s source
# data on the S: drive server, so a future re-run of that gather script
# will reintroduce the same invalid geometry here unless it's fixed
# upstream too (or this script is re-run after).

import arcpy
import os
import time

arcpy.env.overwriteOutput = True
start_time = time.time()

gdb = r"C:\Users\marc.edwards\Documents\PROJECTS\ERAPs_v2\data_prep\habitat\habitat.gdb"
peatlands = os.path.join(gdb, "habitat_peatlands")
peatlands_broken = os.path.join(gdb, "habitat_peatlands_broken")


def check(fc, label):
    # scratchGDB, not memory/ -- this project's bulk intersect helper
    # (R/fct_intersect_vector_value.py) found memory/ non-deterministic for
    # geoprocessing output; same caution applies here even for a small table.
    check_table = os.path.join(arcpy.env.scratchGDB, "check_geom_result")
    arcpy.management.CheckGeometry(fc, check_table)
    count = int(arcpy.management.GetCount(check_table)[0])
    print(f"{label}: {count} problem feature(s)")
    if count > 0:
        with arcpy.da.SearchCursor(check_table, ["CLASS", "PROBLEM"]) as cursor:
            for cls, problem in cursor:
                print(f"    {cls}: {problem}")
    arcpy.management.Delete(check_table)
    return count


print("habitat_peatlands:", arcpy.management.GetCount(peatlands)[0], "features")
before_count = check(peatlands, "before repair")

print("\nsaving unrepaired copy as habitat_peatlands_broken...")
arcpy.management.CopyFeatures(peatlands, peatlands_broken)

print("repairing geometry in place...")
arcpy.management.RepairGeometry(peatlands, "DELETE_NULL")

after_count = check(peatlands, "after repair")
print("\nhabitat_peatlands:", arcpy.management.GetCount(peatlands)[0], "features (post-repair)")

if before_count == 0:
    print("\nNOTE: 0 problems found before repair -- habitat_peatlands likely wasn't the "
          "actual source of the ERROR 160196. Check the landscape (priority landscapes) "
          "layer instead.")
elif after_count > 0:
    print(f"\nWARNING: {after_count} problem(s) remain after RepairGeometry -- "
          "needs manual inspection, not safe to assume fixed.")
else:
    print("\nall problems resolved.")

print("\ntotal elapsed:", round(time.time() - start_time, 1), "sec")
