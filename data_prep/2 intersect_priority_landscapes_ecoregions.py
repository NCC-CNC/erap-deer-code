# Priority Landscapes x ecoregions overlap -- true Intersect + sliver flag.
#
# Populates ECOREGION_ID/ECOREGION_NAME_EN/ECOREGION_NAME_FR/ECOZONE_ID/
# ECOZONE_NAME_EN/ECOZONE_NAME_FR for the Priority Landscapes run by
# spatially intersecting each Priority Landscape against the ecoregions
# layer, "/"-joining values where a landscape spans more than one
# ecoregion or ecozone.
# Uses classic (non-Pairwise) Intersect (#24)
# Removes slivers that are not genuine overlaps.
#
# All 194 ecoregions are included for overlap
#
# Inputs:
#   Priority Landscapes: terrestrial + marine versions. Intersect only run
#   for terrestrial, then copid into marine.
#   Ecoregions: data_prep/ecoregions.gdb's clipped, ALL-ecozone CTEF v2.2
#     layer (ecoregions_ctef_v2_2_all_terrestrial, see "1 prep_ecoregions.py")
#     -- deliberately NOT the non-Arctic-filtered ecoregions_ctef_v2_2_terrestrial
#     the main ERAP pipeline uses, so a Priority Landscape that touches an
#     Arctic ecoregion still gets a real ECOREGION_ID/ECOZONE_ID attribution
#     here instead of silently losing that overlap.
#
# Sliver rule: perim_per_area_km (a fragment's own perimeter in km,
# divided by its own area in km2) separates real overlaps from slivers --
# validated against 338 manually-labeled fragments, every real fragment
# was <= 2.46 km/km2, every sliver was >= 4.24 km/km2. SLIVER_THRESHOLD
# below (3.0) sits in the middle of that gap. Plain overlap area/pct alone
# is not a reliable filter -- real fragments and slivers overlap in that
# range.
#
# Re-validate this threshold whenever the Priority Landscapes or
# ecoregions source data changes -- it's fit to one manually-labeled
# dataset, not derived from a universal geometric law. Re-running this
# script recreates its output feature classes from scratch
# (overwriteOutput), so save a copy first to keep an old validation pass
# for comparison.
#
# Output 1 (scratch/, inspection only): every PL/ecoregion overlap
# fragment as its own feature, carrying both inputs' attributes plus
# overlap_km2, pct_of_pl_area (overlap area as a % of that Priority
# Landscape's own total area), perim_per_area_km, and sliver_flag (1 =
# likely sliver, 0 = likely real) -- sort/filter on sliver_flag or
# perim_per_area_km in ArcGIS Pro to inspect.
#
# Output 2 (data_prep/, the deliverable -- one feature class per landscape
# version): real (sliver_flag = 0) fragments collapsed to one row per
# Priority Landscape, joined onto a copy of each landscape version as
# <original name>_ecoregion_attributes --
#     - ECOREGION_ID/ECOREGION_NAME_EN/ECOREGION_NAME_FR "/"-joined per
#       overlapping ecoregion (position-aligned, sorted by ECOREGION_ID)
#     - ECOZONE_ID/ECOZONE_NAME_EN/ECOZONE_NAME_FR "/"-joined per
#       *distinct* ecozone among those
# This lets the Priority Landscapes output carry the same pre-computed
# values as the ecoregions run, so both can pass these columns straight
# through with no runtime difference between the two landscape sets.

import arcpy
import os
import time

arcpy.env.overwriteOutput = True

start_time = time.time()

# All data_prep script output lives in this project folder, not in the
# repo -- shared across every data_prep script that reads or writes GIS
# data (not just this one).
output_dir = r"C:\Users\marc.edwards\Documents\PROJECTS\ERAPs_v2\data_prep"

priority_landscapes        = r"C:\Users\marc.edwards\Documents\gisdata\priority_landscapes\NCC_priority_landscapes_10162026\NCC_priority_landscapes_10162026.gdb\NCC_priority_landscapes_10162026_terrestrial"
priority_landscapes_marine = r"C:\Users\marc.edwards\Documents\gisdata\priority_landscapes\NCC_priority_landscapes_10162026\NCC_priority_landscapes_10162026.gdb\NCC_priority_landscapes_10162026_marine"
ecoregions                  = os.path.join(output_dir, "ecoregions.gdb", "ecoregions_ctef_v2_2_all_terrestrial")

pl_id_field = "LIS_LANDSC"

# See the header comment -- empirically validated on 338 manually-labeled
# fragments (gap between 2.46 and 4.24 km/km2), re-check if source data changes.
SLIVER_THRESHOLD_KM_PER_KM2 = 3.0

# Output 1: scratch/inspection gdb, in ERAPs_v2/data_prep/scratch/ ---------

scratch_dir = os.path.join(output_dir, "scratch")
if not os.path.exists(scratch_dir):
    os.makedirs(scratch_dir)

scratch_gdb = os.path.join(scratch_dir, "priority_landscapes_ecoregion_overlap.gdb")
if not arcpy.Exists(scratch_gdb):
    arcpy.management.CreateFileGDB(scratch_dir, "priority_landscapes_ecoregion_overlap.gdb")

# Output 2: the deliverable, directly in ERAPs_v2/data_prep/ ---------------

data_prep_gdb = os.path.join(output_dir, "priority_landscapes.gdb")
if not arcpy.Exists(data_prep_gdb):
    arcpy.management.CreateFileGDB(output_dir, "priority_landscapes.gdb")

print("Priority Landscapes (terrestrial):", arcpy.management.GetCount(priority_landscapes)[0], "features")
print("Priority Landscapes (marine):", arcpy.management.GetCount(priority_landscapes_marine)[0], "features")
print("Ecoregions:", arcpy.management.GetCount(ecoregions)[0], "features")

# Each Priority Landscape's own total area, for pct_of_pl_area later -------

pl_area_km2 = {}
with arcpy.da.SearchCursor(priority_landscapes, [pl_id_field, "SHAPE@AREA"]) as cursor:
    for pl_id, area_m2 in cursor:
        pl_area_km2[pl_id] = area_m2 / 1_000_000

# True (classic, non-Pairwise) Intersect, all attributes from both inputs --

print("running Intersect...")
intersect_fc = os.path.join(scratch_gdb, "priority_landscapes_x_ecoregions")
arcpy.analysis.Intersect([priority_landscapes, ecoregions], intersect_fc, join_attributes="ALL")
print("intersect fragments:", arcpy.management.GetCount(intersect_fc)[0])

# Overlap area, % of the Priority Landscape's own area, perimeter/area
# ratio, and the derived sliver flag -- per fragment -----------------------

arcpy.management.AddField(intersect_fc, "overlap_km2", "DOUBLE")
arcpy.management.CalculateField(intersect_fc, "overlap_km2", "!shape.area@squarekilometers!")

arcpy.management.AddField(intersect_fc, "perim_km", "DOUBLE")
arcpy.management.CalculateField(intersect_fc, "perim_km", "!shape.length@kilometers!")

arcpy.management.AddField(intersect_fc, "pct_of_pl_area", "DOUBLE")
arcpy.management.AddField(intersect_fc, "perim_per_area_km", "DOUBLE")
arcpy.management.AddField(intersect_fc, "sliver_flag", "SHORT")

with arcpy.da.UpdateCursor(
    intersect_fc,
    [pl_id_field, "overlap_km2", "perim_km", "pct_of_pl_area", "perim_per_area_km", "sliver_flag"],
) as cursor:
    for row in cursor:
        pl_id, overlap_km2, perim_km, _, _, _ = row
        total = pl_area_km2.get(pl_id)
        row[3] = round(overlap_km2 / total * 100, 3) if total else None
        ratio = perim_km / overlap_km2 if overlap_km2 else None
        row[4] = round(ratio, 4) if ratio is not None else None
        row[5] = int(ratio is not None and ratio >= SLIVER_THRESHOLD_KM_PER_KM2)
        cursor.updateRow(row)

# Quick console summary, so slivers are visible before even opening Pro ----

distinct_pl = set()
distinct_eco = set()
sliver_fragments = []
with arcpy.da.SearchCursor(
    intersect_fc,
    [pl_id_field, "NAME", "ECOREGION_ID", "ECOREGION_NAME_EN", "overlap_km2", "pct_of_pl_area", "perim_per_area_km", "sliver_flag"],
) as cursor:
    for pl_id, name, eco, eco_name_en, overlap_km2, pct, ratio, sliver in cursor:
        distinct_pl.add(pl_id)
        distinct_eco.add(eco)
        if sliver:
            sliver_fragments.append((name, eco_name_en, eco, overlap_km2, pct, ratio))

print(f"\n{len(distinct_pl)} distinct Priority Landscapes involved, {len(distinct_eco)} distinct ecoregions")
print(f"sliver_flag threshold: perim_per_area_km >= {SLIVER_THRESHOLD_KM_PER_KM2}")
print(f"{len(sliver_fragments)} fragments flagged as likely slivers:")
for name, eco_name_en, eco, overlap_km2, pct, ratio in sorted(sliver_fragments, key=lambda r: -r[5]):
    print(f"  {name!r} x ECOREGION_ID {eco} ({eco_name_en}): {overlap_km2:.4f} km2, {pct}% of PL area, {ratio} km/km2")

print("\nwrote", intersect_fc)

# Collapse real (non-sliver) fragments to one row per Priority Landscape --
# ECOREGION_ID/ECOREGION_NAME_EN/ECOREGION_NAME_FR: one value per
# overlapping ecoregion, "/"-joined in the same order (sorted by
# ECOREGION_ID) so the three columns stay position-aligned.
# ECOZONE_ID/ECOZONE_NAME_EN/ECOZONE_NAME_FR: the *distinct* ecozones among
# those same ecoregions, separately sorted and joined -- several
# overlapping ecoregions can share one ecozone.

print("\ncollapsing real overlaps to one row per Priority Landscape...")

pl_ecoregions = {}  # pl_id -> set of (ECOREGION_ID, ECOREGION_NAME_EN, ECOREGION_NAME_FR, ECOZONE_ID, ECOZONE_NAME_EN, ECOZONE_NAME_FR)
with arcpy.da.SearchCursor(
    intersect_fc,
    [pl_id_field, "ECOREGION_ID", "ECOREGION_NAME_EN", "ECOREGION_NAME_FR", "ECOZONE_ID", "ECOZONE_NAME_EN", "ECOZONE_NAME_FR", "sliver_flag"],
) as cursor:
    for pl_id, eco_id, eco_en, eco_fr, zone_id, zone_en, zone_fr, sliver in cursor:
        if sliver:
            continue
        pl_ecoregions.setdefault(pl_id, set()).add((eco_id, eco_en, eco_fr, zone_id, zone_en, zone_fr))

merged = {}
multi_eco_count = 0
multi_zone_count = 0
for pl_id, rows in pl_ecoregions.items():
    eco_rows = sorted(rows, key=lambda r: r[0])
    ecoregion_id_str = "/".join(str(r[0]) for r in eco_rows)
    ecoregion_en_str = "/".join(r[1] for r in eco_rows)
    ecoregion_fr_str = "/".join(r[2] for r in eco_rows)

    distinct_zones = sorted({(r[3], r[4], r[5]) for r in eco_rows}, key=lambda z: z[0])
    ecozone_id_str = "/".join(str(z[0]) for z in distinct_zones)
    ecozone_en_str = "/".join(z[1] for z in distinct_zones)
    ecozone_fr_str = "/".join(z[2] for z in distinct_zones)

    merged[pl_id] = {
        "ECOREGION_ID": ecoregion_id_str,
        "ECOREGION_NAME_EN": ecoregion_en_str,
        "ECOREGION_NAME_FR": ecoregion_fr_str,
        "ECOZONE_ID": ecozone_id_str,
        "ECOZONE_NAME_EN": ecozone_en_str,
        "ECOZONE_NAME_FR": ecozone_fr_str,
    }
    if len(eco_rows) > 1:
        multi_eco_count += 1
    if len(distinct_zones) > 1:
        multi_zone_count += 1

print(f"{len(merged)} Priority Landscapes with at least one real overlap")
print(f"  {multi_eco_count} span more than one ecoregion, {multi_zone_count} span more than one ecozone")
missing = set(pl_area_km2) - set(merged)
if missing:
    print(f"WARNING: {len(missing)} Priority Landscape(s) have NO real (non-sliver) overlap at all: {sorted(missing)}")

# Join back onto a copy of the Priority Landscapes layer, saved in
# data_prep/ (this is the deliverable) -- same attribute values written onto
# both the terrestrial and marine versions, since the ecoregion/ecozone
# overlap a landscape belongs to is the same fact either way. Marine is
# copied and joined here too, not re-intersected -- it shares the
# terrestrial version's already-computed, already-sliver-filtered `merged`
# dict rather than running its own Intersect/sliver pass. --------------------

merged_fields = ["ECOREGION_ID", "ECOREGION_NAME_EN", "ECOREGION_NAME_FR", "ECOZONE_ID", "ECOZONE_NAME_EN", "ECOZONE_NAME_FR"]

def write_attrs(source_fc, label):
    attrs_fc = os.path.join(data_prep_gdb, os.path.basename(source_fc) + "_ecoregion_attributes")
    arcpy.management.CopyFeatures(source_fc, attrs_fc)

    for f in merged_fields:
        arcpy.management.AddField(attrs_fc, f, "TEXT", field_length=1000)

    with arcpy.da.UpdateCursor(attrs_fc, [pl_id_field] + merged_fields) as cursor:
        for row in cursor:
            pl_id = row[0]
            values = merged.get(pl_id)
            if values is None:
                cursor.updateRow(row)  # leave the 6 new fields null, already warned above
                continue
            for i, f in enumerate(merged_fields, start=1):
                row[i] = values[f]
            cursor.updateRow(row)

    print(f"wrote {attrs_fc} ({label})")
    return attrs_fc

write_attrs(priority_landscapes, "terrestrial")
write_attrs(priority_landscapes_marine, "marine -- attributes copied from terrestrial, not re-intersected")

print("total elapsed:", round(time.time() - start_time, 1), "sec")
