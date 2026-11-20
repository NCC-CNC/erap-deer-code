# Build the "terrestrial AND protected" layer needed for
# recalc_species_protected_km2.R's *_terrestrial columns.
#
# In recalc_species_protected_km2.R we calculate
# Total_Km2_terrestrial as the species raster area clipped to the
# terrestrial land base.
#
# We also need Protected_Km2_terrestrial, the terrestrially-clipped
# species range that ALSO falls inside cpcad_ncc_dslv_2025
# (prep_cpcad_ncc_2025.py's output) -- i.e. the intersection of the
# terrestrial land base and the protected-areas layer.
#
# Terrestrial land base copied locally first as a precaution -- the 2025
# CPCAD/NCC sources turned out to be read-only at the ESRI workspace level
# (see prep_cpcad_ncc_2025.py's header) even though NTFS permissions were
# fine; copying first sidesteps that class of error regardless of whether
# it actually applies here.

import arcpy
import os
import time

arcpy.env.overwriteOutput = True
start_time = time.time()

terrestrial_source = r"C:\Users\marc.edwards\Documents\gisdata\Terrestrial_land_base\Terrestrial_Base_Data.gdb\geo_political_region_2_Dissolve_Erase_GL_Merge_ON_Islands_FInal_20250815"

# All data_prep script output lives in this project folder, not in the
# repo -- shared across every data_prep script that reads or writes GIS
# data (not just this one).
output_dir = r"C:\Users\marc.edwards\Documents\PROJECTS\ERAPs_v2\data_prep"
cpcad_ncc = os.path.join(output_dir, "protected_areas.gdb", "cpcad_ncc_dslv_2025")

gdb = os.path.join(output_dir, "terrestrial.gdb")
if not arcpy.Exists(gdb):
    arcpy.management.CreateFileGDB(output_dir, "terrestrial.gdb")

terrestrial_local = os.path.join(gdb, "terrestrial_land_base")
protected_terrestrial = os.path.join(gdb, "protected_terrestrial")

print("copying terrestrial land base locally (source features:", arcpy.management.GetCount(terrestrial_source)[0], ")...")
arcpy.management.CopyFeatures(terrestrial_source, terrestrial_local)

print("intersecting terrestrial land base with cpcad_ncc_dslv_2025 (cpcad features:", arcpy.management.GetCount(cpcad_ncc)[0], ")...")
arcpy.analysis.Intersect([terrestrial_local, cpcad_ncc], protected_terrestrial)
print("wrote", protected_terrestrial, "| count:", arcpy.management.GetCount(protected_terrestrial)[0])

print("total elapsed:", round(time.time() - start_time, 1), "sec")
