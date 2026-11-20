# Indigenous territories x ecoregions, and x Priority Landscapes -- straight
# Intersect, two separate CSVs (#28). No sliver filtering: territories are
# large, independently-sourced polygons, not the kind of thin digitising
# mismatch the Priority Landscapes/ecoregions sliver rule exists for.
#
# territories' own Name/description fields are renamed to NATION_NAME/
# NATION_URL on a scratch copy before intersecting, since Priority
# Landscapes already has a field called NAME and the two would otherwise
# collide.
#
# Uses classic (non-Pairwise) Intersect (#24).
#
# Intersect outputs one row per disjoint output piece, not one row per
# input feature pair -- some ecoregions are multipart (confirmed: Lower
# Mainland/196 has 464 parts, BC's coastal islands), so a single large
# territory can produce dozens of fragment rows against one ecoregion.
# Fragments sharing the same area ID + NATION_NAME are grouped into one row
# (overlap_km2 summed) before writing the CSV, since report cards need one
# line per Nation per area, not one per island.

import arcpy
import csv
import os
import time

arcpy.env.overwriteOutput = True
start_time = time.time()

output_dir = r"C:\Users\marc.edwards\Documents\PROJECTS\ERAPs_v2\data_prep"

territories = os.path.join(output_dir, "indigenous_territories.gdb", "territories")
# ALL-ecozone layer (not the non-Arctic-filtered ecoregions_ctef_v2_2_terrestrial
# the main ERAP pipeline uses) -- a territory touching an Arctic ecoregion
# still needs a real overlap row here, see "1 prep_ecoregions.py".
ecoregions = os.path.join(output_dir, "ecoregions.gdb", "ecoregions_ctef_v2_2_all_terrestrial")
priority_landscapes = r"C:\Users\marc.edwards\Documents\gisdata\priority_landscapes\NCC_priority_landscapes_10162026\NCC_priority_landscapes_10162026.gdb\NCC_priority_landscapes_10162026_terrestrial"

scratch_dir = os.path.join(output_dir, "scratch")
if not os.path.exists(scratch_dir):
    os.makedirs(scratch_dir)

scratch_gdb = os.path.join(scratch_dir, "indigenous_territories_intersect.gdb")
if not arcpy.Exists(scratch_gdb):
    arcpy.management.CreateFileGDB(scratch_dir, "indigenous_territories_intersect.gdb")

print("Territories:", arcpy.management.GetCount(territories)[0], "features")
print("Ecoregions:", arcpy.management.GetCount(ecoregions)[0], "features")
print("Priority Landscapes (terrestrial):", arcpy.management.GetCount(priority_landscapes)[0], "features")

territories_renamed = os.path.join(scratch_gdb, "territories_renamed")
arcpy.management.CopyFeatures(territories, territories_renamed)
arcpy.management.AlterField(territories_renamed, "Name", "NATION_NAME", "NATION_NAME")
arcpy.management.AlterField(territories_renamed, "description", "NATION_URL", "NATION_URL")

# native-land.ca's source geometry has self-intersections and bad ring
# ordering (confirmed via CheckGeometry: 22 problem features) -- community-
# sourced, not topology-checked like this project's other inputs. Intersect
# raises ERROR 160196 ("Invalid Topology") without this.
arcpy.management.RepairGeometry(territories_renamed)


def intersect_to_csv(area_fc, area_fields, out_name):
    print(f"\nrunning Intersect against {os.path.basename(area_fc)}...")
    intersect_fc = os.path.join(scratch_gdb, out_name)
    arcpy.analysis.Intersect([territories_renamed, area_fc], intersect_fc, join_attributes="ALL")
    print("intersect fragments:", arcpy.management.GetCount(intersect_fc)[0])

    arcpy.management.AddField(intersect_fc, "overlap_km2", "DOUBLE")
    arcpy.management.CalculateField(intersect_fc, "overlap_km2", "!shape.area@squarekilometers!")

    fields = area_fields + ["NATION_NAME", "NATION_URL", "overlap_km2"]
    grouped = {}
    with arcpy.da.SearchCursor(intersect_fc, fields) as cursor:
        for row in cursor:
            key, overlap = row[:-1], row[-1]
            grouped[key] = grouped.get(key, 0) + overlap
    print(f"collapsed to {len(grouped)} area x Nation rows")

    out_csv = os.path.join(output_dir, f"{out_name}.csv")
    with open(out_csv, "w", newline="", encoding="utf-8-sig") as f:
        writer = csv.writer(f)
        writer.writerow(fields)
        for key, overlap in grouped.items():
            writer.writerow(list(key) + [overlap])

    print(f"wrote {out_csv}")
    return out_csv


intersect_to_csv(
    ecoregions,
    ["ECOREGION_ID", "ECOREGION_NAME_EN", "ECOREGION_NAME_FR"],
    "indigenous_territories_x_ecoregions",
)
intersect_to_csv(
    priority_landscapes,
    ["LIS_LANDSC", "NAME"],
    "indigenous_territories_x_priority_landscapes",
)

print("\ntotal elapsed:", round(time.time() - start_time, 1), "sec")
