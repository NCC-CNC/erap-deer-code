# Prep the ecoregions reference layer from the Canadian Terrestrial
# Ecological Framework (CTEF) v2.2 -- current version as of Sep 2026, per
# https://www.natureserve.org/canada/featured-projects/national-ecological-framework-canada
# (downloaded from open.canada.ca; see gisdata/CTEF/readMe.txt for
# provenance). Source gdbs ship compressed -- if arcpy reports the feature
# class "does not exist or is not supported", run
# arcpy.management.UncompressFileGeodatabaseData() on the gdb first.
#
# Replaces the previous ecoregions source
# (ecoregions_albers_dslv.shp / ecoregions_dslv_clipped_to_geo_political_region_20250815.shp),
# whose REGION_NOM (French ecoregion names) turned out to be corrupted at
# the raw-byte level and unrecoverable.
#
# New column names replace the old ECOREGION/REGION_NAM/REGION_NOM/ECOZONE/
# ZONE_NAME/ZONE_NOM going forward, repo-wide: ECOREGION_ID/
# ECOREGION_NAME_EN/ECOREGION_NAME_FR/ECOZONE_ID/ECOZONE_NAME_EN/
# ECOZONE_NAME_FR.
#
# Steps:
#   1. Dissolve ecoregion polygons by ECOREGION_ID (source has 218 rows for
#      194 distinct ecoregions -- some are split across multiple rows/parts).
#      All ecozones included at this stage, Arctic ones too.
#   2. Join ECOZONE_NAME_EN/ECOZONE_NAME_FR onto each ecoregion by
#      ECOZONE_ID, looked up from the ecozone layer directly.
#   3. Project to Canada Albers -- source ships in Web Mercator.
#   4. Clip to the geo-political/terrestrial land base boundary -- same clip
#      source used for the old ecoregions_dslv_clipped file. Both the
#      unclipped and clipped all-ecozone layers are saved
#      (ecoregions_ctef_v2_2_all / ecoregions_ctef_v2_2_all_terrestrial) --
#      consumers that need every ecoregion regardless of ecozone (Priority
#      Landscapes/Indigenous Territories overlap attribution, which must
#      still correctly attribute a landscape that touches an Arctic
#      ecoregion) read these, not the non-Arctic ones below.
#   5. Select non-Arctic ecozones only (ECOZONE_ID 4-15, dropping Arctic
#      Cordillera/Northern Arctic/Southern Arctic 1-3 -- same ecozone_list
#      the legacy pipeline's prioritizr/habitat/threats/species prep scripts
#      filtered to, confirmed CTEF v2.2's ECOZONE_ID numbering still matches
#      that same standard Canadian ecozone numbering) out of the two layers
#      from step 4, saved as ecoregions_ctef_v2_2 / ecoregions_ctef_v2_2_terrestrial
#      -- these are what setup_ecoregions.toml actually points the main
#      pipeline at.
#   6. Project and clip the raw ecozone layer the same way (same target CRS,
#      same terrestrial land base clip boundary) -- the prioritizr scripts
#      (data_prep/09 prioritizr) need these as AOIs. Left unfiltered here --
#      "8 prioritizr/1_initiate_project_ecozones.R" already scopes itself to
#      the same ecozone_list when it pulls per-ecozone AOIs from this output.

import arcpy
import os
import time

arcpy.env.overwriteOutput = True
start_time = time.time()

ecoregion_src = r"C:\Users\marc.edwards\Documents\gisdata\CTEF\nef_ca_ter_ecoregion_v2_2.gdb\nef_ca_ter_ecoregion_v2_2"
ecozone_src   = r"C:\Users\marc.edwards\Documents\gisdata\CTEF\nef_ca_ter_ecozone_v2_2.gdb\nef_ca_ter_ecozone_v2_2"
clip_layer    = r"C:\Users\marc.edwards\Documents\gisdata\Terrestrial_land_base\Terrestrial_Base_Data.gdb\geo_political_region_2_Dissolve_Erase_GL_Merge_ON_Islands_FInal_20250815"

# Canada Albers reference CRS, taken from an already-standard layer in this
# project rather than hardcoded, so it always matches exactly.
reference_layer = r"C:\Users\marc.edwards\Documents\gisdata\priority_landscapes\NCC_priority_landscapes_10162026\NCC_priority_landscapes_10162026.gdb\NCC_priority_landscapes_10162026_terrestrial"
target_sr = arcpy.Describe(reference_layer).spatialReference

# Non-Arctic ecozones only -- same ecozone_list used throughout the legacy
# pipeline (habitat/threats/species prep, prioritizr) to scope the project
# to the ecozones ERAPs actually covers. Excludes ECOZONE_ID 1-3 (Arctic
# Cordillera, Northern Arctic, Southern Arctic). Applied below as a
# selection out of the all-ecozone layers, not as an upstream read filter --
# see step 4/5 in the header comment for why both versions get saved.
NON_ARCTIC_ECOZONES = [4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
ecozone_where = "ECOZONE_ID IN ({})".format(",".join(str(z) for z in NON_ARCTIC_ECOZONES))

# All data_prep script output lives in this project folder, not in the
# repo -- shared across every data_prep script that reads or writes GIS
# data (not just this one).
output_dir = r"C:\Users\marc.edwards\Documents\PROJECTS\ERAPs_v2\data_prep"
gdb = os.path.join(output_dir, "ecoregions.gdb")
if not arcpy.Exists(gdb):
    arcpy.management.CreateFileGDB(output_dir, "ecoregions.gdb")

print("ecoregion source rows:", arcpy.management.GetCount(ecoregion_src)[0])
print("target CRS:", target_sr.name)

# Ecozone name lookup by ECOZONE_ID (source has multi-part rows per zone,
# dedupe here; trim stray whitespace/newlines seen in a couple of names) --

ecozone_names = {}
with arcpy.da.SearchCursor(ecozone_src, ["ECOZONE_ID", "ECOZONE_NAME_EN", "ECOZONE_NAME_FR"]) as cursor:
    for zid, en, fr in cursor:
        ecozone_names[zid] = ((en or "").strip(), (fr or "").strip())
print(f"{len(ecozone_names)} distinct ecozones")

# Ecoregion attribute lookup by ECOREGION_ID, from the source table directly
# (not from Dissolve's own multi-field grouping -- one ECOREGION_ID had two
# rows differing only by capitalization in the French name ("...du Centre"
# vs "...du centre"), a harmless source inconsistency that would otherwise
# split that ecoregion into 2 dissolve groups instead of 1). Picks whichever
# row is encountered first per ID.

eco_attrs = {}
with arcpy.da.SearchCursor(
    ecoregion_src,
    ["ECOREGION_ID", "ECOZONE_ID", "ECOPROVINCE_ID", "ECOREGION_NAME_EN", "ECOREGION_NAME_FR"],
) as cursor:
    for eid, zid, pid, en, fr in cursor:
        eco_attrs.setdefault(eid, (zid, pid, (en or "").strip(), (fr or "").strip()))
print(f"{len(eco_attrs)} distinct ECOREGION_ID")

# Dissolve ecoregion polygons by ECOREGION_ID alone -- one row per ecoregion,
# all ecozones included (Arctic ones get selected back out further down,
# once the Project/Clip work below is done) -------------------------------

print("dissolving ecoregions by ECOREGION_ID...")
dissolved = os.path.join(gdb, "ecoregions_dissolved_tmp")
arcpy.management.Dissolve(ecoregion_src, dissolved, ["ECOREGION_ID"])
n_dissolved = int(arcpy.management.GetCount(dissolved)[0])
print("dissolved rows:", n_dissolved)
if n_dissolved != len(eco_attrs):
    print(f"WARNING: dissolved row count ({n_dissolved}) doesn't match distinct ECOREGION_ID count ({len(eco_attrs)})")

# Add back ECOZONE_ID/ECOPROVINCE_ID/ECOREGION_NAME_EN/ECOREGION_NAME_FR
# (dropped by the single-field dissolve) plus the joined ECOZONE_NAME_EN/FR -

arcpy.management.AddField(dissolved, "ECOZONE_ID", "SHORT")
arcpy.management.AddField(dissolved, "ECOPROVINCE_ID", "FLOAT")
arcpy.management.AddField(dissolved, "ECOREGION_NAME_EN", "TEXT", field_length=100)
arcpy.management.AddField(dissolved, "ECOREGION_NAME_FR", "TEXT", field_length=100)
arcpy.management.AddField(dissolved, "ECOZONE_NAME_EN", "TEXT", field_length=100)
arcpy.management.AddField(dissolved, "ECOZONE_NAME_FR", "TEXT", field_length=100)

fields = ["ECOREGION_ID", "ECOZONE_ID", "ECOPROVINCE_ID", "ECOREGION_NAME_EN", "ECOREGION_NAME_FR", "ECOZONE_NAME_EN", "ECOZONE_NAME_FR"]
with arcpy.da.UpdateCursor(dissolved, fields) as cursor:
    for row in cursor:
        eid = row[0]
        zid, pid, name_en, name_fr = eco_attrs[eid]
        row[1] = zid
        row[2] = pid
        row[3] = name_en
        row[4] = name_fr
        row[5], row[6] = ecozone_names.get(zid, ("UNKNOWN", "UNKNOWN"))
        cursor.updateRow(row)

# Project to Canada Albers (all ecozones, Arctic included) -----------------

print(f"projecting to {target_sr.name}...")
ecoregions_all_full = os.path.join(gdb, "ecoregions_ctef_v2_2_all")
arcpy.management.Project(dissolved, ecoregions_all_full, target_sr)
arcpy.management.Delete(dissolved)
print("wrote", ecoregions_all_full, "(all ecozones)")

# Clip to the geo-political / terrestrial land base boundary (still all
# ecozones) ------------------------------------------------------------------

print("clipping to terrestrial land base boundary...")
ecoregions_all_terrestrial = os.path.join(gdb, "ecoregions_ctef_v2_2_all_terrestrial")
arcpy.analysis.Clip(ecoregions_all_full, clip_layer, ecoregions_all_terrestrial)
print("wrote", ecoregions_all_terrestrial, "(all ecozones) | count:", arcpy.management.GetCount(ecoregions_all_terrestrial)[0])

# Select non-Arctic ecozones out of both all-ecozone layers above -- these
# two (same names the pipeline has always used) are what setup_ecoregions.toml
# actually points at. Selected out rather than re-run through Dissolve/
# Project/Clip a second time -- that work only needs to happen once.

print("selecting non-Arctic ecozones...")
ecoregions_full = os.path.join(gdb, "ecoregions_ctef_v2_2")
all_full_lyr = arcpy.management.MakeFeatureLayer(ecoregions_all_full, "all_full_lyr", ecozone_where)
arcpy.management.CopyFeatures(all_full_lyr, ecoregions_full)
print("wrote", ecoregions_full, "(non-Arctic) | count:", arcpy.management.GetCount(ecoregions_full)[0])

ecoregions_clipped = os.path.join(gdb, "ecoregions_ctef_v2_2_terrestrial")
all_terrestrial_lyr = arcpy.management.MakeFeatureLayer(ecoregions_all_terrestrial, "all_terrestrial_lyr", ecozone_where)
arcpy.management.CopyFeatures(all_terrestrial_lyr, ecoregions_clipped)
print("wrote", ecoregions_clipped, "(non-Arctic) | count:", arcpy.management.GetCount(ecoregions_clipped)[0])

# Project and clip the raw ecozone layer too, same CRS and clip boundary as
# ecoregions above -- gives the prioritizr scripts a single terrestrial-
# clipped ecozone source to read instead of clipping it themselves ----------

print(f"projecting ecozones to {target_sr.name}...")
ecozones_full = os.path.join(gdb, "ecozones_ctef_v2_2")
arcpy.management.Project(ecozone_src, ecozones_full, target_sr)
print("wrote", ecozones_full, "| count:", arcpy.management.GetCount(ecozones_full)[0])

print("clipping ecozones to terrestrial land base boundary...")
ecozones_clipped = os.path.join(gdb, "ecozones_ctef_v2_2_terrestrial")
arcpy.analysis.Clip(ecozones_full, clip_layer, ecozones_clipped)
print("wrote", ecozones_clipped, "| count:", arcpy.management.GetCount(ecozones_clipped)[0])

print("total elapsed:", round(time.time() - start_time, 1), "sec")
