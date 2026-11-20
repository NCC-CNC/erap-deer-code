# Build a true vector CPCAD + NCC protected-areas layer for 2025 -- the
# real 2025 counterpart to protected_areas_2024/combine_cpcad_ncc.py's
# cpcad_ncc_dslv_july2024, not a redo of it.
#
# Also persists two NCC-only layers alongside the merged cpcad_ncc_dslv_2025
# output -- ncc_fs_ca_2025_dslv (fee simple + conservation agreement) and
# ncc_fs_2025_dslv (fee simple only) -- setup.toml's ncc_fs_ca_path/ncc_fs_path,
# read by R/08_actions.R for the STEW1/PARTNER1 action-recommendation triggers.
#
# This script mirrors combine_cpcad_ncc.py's logic, pointed
# at the real 2025 sources:
#   - CPCAD\ProtectedConservedArea_2025\ProtectedConservedArea_2025.gdb\
#     ProtectedConservedArea_2025 (22,438 features, BIOME T=21,509/M=929 --
#     same schema as 2024's raw CPCAD, filtered to BIOME='T' same as 2024).
#   - protected_areas_2025\Includes.gdb\NCCFSCA_20260428 (7,691 features)
#     -- "FSCA" = Fee Simple / Conservation Agreement, and it's already
#     pre-filtered to exactly the four PCL_PARCEL_INTEREST_TYPE_EN values
#     combine_cpcad_ncc.py selects on the raw NCC accomplishments table
#     (Fee Simple, Fee Simple (Joint Ownership), Conservation Agreement,
#     Conservation Agreement (Joint Ownership)) -- that interest-type
#     filter is applied explicitly below too, so a future run against an
#     unfiltered source still comes out correct. Also filtered to
#     PCL_NCC_ACCOMPLISHMENT_EN = 'Yes' (7,651/7,691 rows), the closest
#     available match to 2024's PCLMNA_NCC_ACCOMPLISHMENT_IND = 1 filter.
#
# Both source geodatabases are marked read-only at the ESRI workspace
# level (not an NTFS/ACL thing -- icacls shows full control; SearchCursor
# reads them fine too), which makes SelectLayerByAttribute + a
# select-based Dissolve fail with "ERROR 160385: Workspace or data source
# is read only" even though nothing was being written back to the source.
# Project (a straight read, like CopyFeatures) works against them without
# issue, so every source gets reprojected into our own writable gdb first,
# and all selecting/dissolving happens on that local copy -- CPCAD's raw
# source ships in a different CRS (Canada_Albers_Equal_Area_Conic, NAD83)
# from this project's standard (a custom WGS84-based Albers), confirmed by
# direct WKT comparison, so Project (not CopyFeatures) is required here,
# not just a convenience.

import arcpy
import os
import time

arcpy.env.overwriteOutput = True
start_time = time.time()

cpcad_source = r"C:\Users\marc.edwards\Documents\gisdata\CPCAD\ProtectedConservedArea_2025\ProtectedConservedArea_2025.gdb\ProtectedConservedArea_2025"
ncc_source   = r"C:\Users\marc.edwards\Documents\gisdata\protected_areas_2025\Includes.gdb\NCCFSCA_20260428"

# This project's standard CRS, taken from a reference layer rather than a
# hardcoded EPSG/WKID so it always matches exactly.
reference_layer = r"C:\Users\marc.edwards\Documents\gisdata\priority_landscapes\NCC_priority_landscapes_10162026\NCC_priority_landscapes_10162026.gdb\NCC_priority_landscapes_10162026_terrestrial"
target_sr = arcpy.Describe(reference_layer).spatialReference

# All data_prep script output lives in this project folder, not in the
# repo -- shared across every data_prep script that reads or writes GIS
# data (not just this one).
output_dir = r"C:\Users\marc.edwards\Documents\PROJECTS\ERAPs_v2\data_prep"
gdb = os.path.join(output_dir, "protected_areas.gdb")
if not arcpy.Exists(gdb):
    arcpy.management.CreateFileGDB(output_dir, "protected_areas.gdb")

cpcad_local = os.path.join(gdb, "cpcad_2025_raw")
ncc_local   = os.path.join(gdb, "ncc_fsca_2025_raw")
cpcad_dslv  = os.path.join(gdb, "cpcad_2025_terrestrial_dslv")
ncc_dslv    = os.path.join(gdb, "ncc_fs_ca_2025_dslv")
ncc_fs_only_dslv = os.path.join(gdb, "ncc_fs_2025_dslv")
out_fc      = os.path.join(gdb, "cpcad_ncc_dslv_2025")

print("reprojecting CPCAD 2025 source locally (source features:", arcpy.management.GetCount(cpcad_source)[0], ")...")
arcpy.management.Project(cpcad_source, cpcad_local, target_sr)

print("reprojecting NCC FSCA 2025 source locally (source features:", arcpy.management.GetCount(ncc_source)[0], ")...")
arcpy.management.Project(ncc_source, ncc_local, target_sr)

print("dissolving CPCAD (BIOME = 'T')...")
cpcad_t = arcpy.management.SelectLayerByAttribute(cpcad_local, "NEW_SELECTION", "BIOME = 'T'")
arcpy.management.Dissolve(cpcad_t, cpcad_dslv, multi_part="SINGLE_PART")
print("  ->", arcpy.management.GetCount(cpcad_dslv)[0], "features")

print("dissolving NCC accomplishments (accomplished fee simple / conservation agreement)...")
ncc_filtered = arcpy.management.SelectLayerByAttribute(
    ncc_local, "NEW_SELECTION",
    "PCL_NCC_ACCOMPLISHMENT_EN = 'Yes' And PCL_PARCEL_INTEREST_TYPE_EN IN "
    "('Fee Simple', 'Fee Simple (Joint Ownership)', 'Conservation Agreement', 'Conservation Agreement (Joint Ownership)')"
)
arcpy.management.Dissolve(ncc_filtered, ncc_dslv, multi_part="SINGLE_PART")
print("  ->", arcpy.management.GetCount(ncc_dslv)[0], "features")

# Fee-simple-only subset (no Conservation Agreement) -- kept as its own
# persisted layer for action_recommendations' PARTNER1 trigger
# ("Area of NCC fee-simple land"), distinct from STEW1's fee-simple-or-CA
# trigger above. Both ncc_dslv and this one survive past this script now
# (not deleted in cleanup below) since the action-recommendations step
# needs them as real pipeline inputs, not throwaway merge intermediates.
print("dissolving NCC accomplishments (accomplished fee simple only)...")
ncc_fs_only_filtered = arcpy.management.SelectLayerByAttribute(
    ncc_local, "NEW_SELECTION",
    "PCL_NCC_ACCOMPLISHMENT_EN = 'Yes' And PCL_PARCEL_INTEREST_TYPE_EN IN "
    "('Fee Simple', 'Fee Simple (Joint Ownership)')"
)
arcpy.management.Dissolve(ncc_fs_only_filtered, ncc_fs_only_dslv, multi_part="SINGLE_PART")
print("  ->", arcpy.management.GetCount(ncc_fs_only_dslv)[0], "features")

print("merging + dissolving...")
merged = os.path.join(gdb, "merged_tmp")
arcpy.management.Merge([ncc_dslv, cpcad_dslv], merged)
arcpy.management.Dissolve(merged, out_fc, multi_part="SINGLE_PART")
print("wrote", out_fc, "| count:", arcpy.management.GetCount(out_fc)[0])

# The raw CPCAD source contains a small number of true circular-arc
# features (confirmed: 20 of 22,438), which GEOS-based tools downstream
# (exactextractr::exact_extract(), used in "7 recalc_species_protected_km2.R")
# can't read -- fails with "Unsupported geometry type". Densify once here so
# every consumer of cpcad_ncc_dslv_2025 gets straight-line geometry.
print("densifying (removing curves)...")
arcpy.edit.Densify(out_fc, "OFFSET", max_deviation="1 Meters")

print("cleanup...")
arcpy.management.Delete([cpcad_local, ncc_local, cpcad_dslv, merged])

print("total elapsed:", round(time.time() - start_time, 1), "sec")
