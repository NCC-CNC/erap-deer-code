# Gather the habitat source datasets into one "habitat" folder, meant to
# run on whatever server actually has access to these source files -- copy
# this script there, fill in the *_source/output_dir paths below for that
# machine, run it, then zip the output folder and bring it back here to
# unpack (as ERAPs_v2/data_prep/habitat/) and point setup.toml at.
#
# habitat_forest is a raster -- reprojected via ProjectRaster only if its
# source CRS doesn't already match TARGET_SR (plain file copy otherwise, so
# an already-aligned source isn't needlessly resampled), written as its own
# standalone .tif, NOT embedded in the gdb alongside the vectors.
# `ProjectRaster` into a File GDB raster dataset doesn't reliably carry the
# source tif's NoData value through -- confirmed directly: the gdb-embedded
# version read back with a real NoData value (255) silently turned into a
# valid pixel value once read via GDAL's OpenFileGDB raster driver (what
# terra/R use), so background/no-data cells summed as if they were ~255x a
# real forest cell, inflating every forest area figure hundreds of times
# over. A plain GeoTIFF carries NoData correctly through this same
# read path -- confirmed on a re-exported copy (cover% for Lake Erie
# Lowland dropped from a nonsensical 21834% back to 14.29%, matching the
# legacy pipeline's 14.28% almost exactly). Keep habitat_forest as a .tif
# for this reason -- don't move it back into the gdb.
#
# The other six (grassland/wetland/lakes/rivers/coastline/peatlands) are
# vectors, either .shp or already a gdb feature class -- reprojected via
# Project, into one output gdb. All seven land in one "habitat" folder
# (habitat.gdb for the six vectors, the forest tif alongside it), all in
# this project's standard CRS, so the whole habitat input set travels
# together, already aligned -- source datasets vary in CRS (confirmed:
# habitat_wetland's source ships in a geographic CRS, not Albers), so every
# input is explicitly reprojected rather than assumed to already match.
#
# Pressures are NOT included here -- already sourced locally, out of scope
# for this script.

import arcpy
import os
import shutil
import time

arcpy.env.overwriteOutput = True
start_time = time.time()

# This project's standard CRS (WGS_1984_Canada_Albers), captured directly
# from this repo's own reference layer (data_prep/ecoregions.gdb's
# ecoregions_ctef_v2_2_terrestrial) rather than referenced by path, since
# this script runs on a server that won't have that file available.
TARGET_SR = arcpy.SpatialReference()
TARGET_SR.loadFromString(
    'PROJCS["WGS_1984_Canada_Albers",GEOGCS["GCS_WGS_1984",DATUM["D_WGS_1984",'
    'SPHEROID["WGS_1984",6378137.0,298.257223563]],PRIMEM["Greenwich",0.0],'
    'UNIT["Degree",0.0174532925199433]],PROJECTION["Albers"],'
    'PARAMETER["False_Easting",0.0],PARAMETER["False_Northing",0.0],'
    'PARAMETER["Central_Meridian",-96.0],PARAMETER["Standard_Parallel_1",50.0],'
    'PARAMETER["Standard_Parallel_2",70.0],PARAMETER["Latitude_Of_Origin",40.0],'
    'UNIT["Meter",1.0]]'
)

# Set every path below to this server's actual location before running ----

habitat_forest_source     = r"S:\CONS_TECH\PRZ\DATA\PREP\Habitat\Forest\Forest_AAFC_LUTS_2020_NFIS_2022_30m.tif"  # raster (.tif)
habitat_grassland_source  = r":\CONS_TECH\PRZ\DATA\PREP\Habitat\Grassland\Grassland_Data.gdb\RasterToPoly\AAFC_LUTS_2020_v5_Grassland_Clip"  # vector (.shp or gdb feature class)
habitat_wetland_source    = r"S:\CONS_TECH\PRZ\DATA\PREP\Habitat\Wetland\Processing.gdb\canvec_saturated_soil_2_merge_20230201_pw_dissolve"  # vector
habitat_lakes_source      = r"S:\CONS_TECH\PRZ\DATA\PREP\Habitat\Lakes\CanVec_NHN_Hydro\Hydrol_Final.gdb\NHN_Waterbodies_2022_Dissolve_Lakes_LargeRivers"  # vector
habitat_rivers_source     = r"S:\CONS_TECH\PRZ\DATA\PREP\Habitat\Lakes\CanVec_NHN_Hydro\Hydrol_Final.gdb\NHN_Watercourses_LinearFlow_2022_Erase_Waterbodies"  # vector
habitat_coastline_source  = r"S:\CONS_TECH\PRZ\DATA\PREP\Habitat\Shoreline\Shoreline_Processing.gdb\Input\CanCoast_v3_prj"  # vector
habitat_peatlands_source  = r"S:\CONS_TECH\PRZ\DATA\IMET DASHBOARD\IMET DATA\IMET_PEATLANDS.gdb\IMET_Peatlands"  # vector

output_dir = r"C:/Users/marc.edwards/Desktop/gather_data"  # folder to create habitat/ in
habitat_dir = os.path.join(output_dir, "habitat")  # unpacks to ERAPs_v2/data_prep/habitat/
gdb_name    = "habitat.gdb"  # the six vectors only -- forest stays a standalone .tif, see header

# ---------------------------------------------------------------------------

vector_sources = {
    "habitat_grassland": habitat_grassland_source,
    "habitat_wetland":   habitat_wetland_source,
    "habitat_lakes":     habitat_lakes_source,
    "habitat_rivers":    habitat_rivers_source,
    "habitat_coastline": habitat_coastline_source,
    "habitat_peatlands": habitat_peatlands_source,
}

missing = [name for name, path in {"habitat_forest_source": habitat_forest_source, **vector_sources}.items() if not path]
missing += ["output_dir"] if not output_dir else []
if missing:
    raise ValueError(f"Set these paths before running: {', '.join(missing)}")

if not os.path.exists(habitat_dir):
    os.makedirs(habitat_dir)

gdb = os.path.join(habitat_dir, gdb_name)
if not arcpy.Exists(gdb):
    arcpy.management.CreateFileGDB(habitat_dir, gdb_name)

print("checking forest raster projection...")
forest_out = os.path.join(habitat_dir, os.path.basename(habitat_forest_source))
source_sr = arcpy.Describe(habitat_forest_source).spatialReference

# Compare defining parameters, not .name -- confirmed this project's own
# standard Albers CRS gets labelled both "WGS_1984_Canada_Albers" (TARGET_SR,
# as loaded here) and "Canada_Albers_WGS_1984" (how a GDAL-written tif in
# this same CRS reports it) depending on how/where it was written. Same
# projection, same parameters, just two Esri name aliases for it -- a plain
# name match would wrongly call these "different" and reproject a source
# that's already correctly aligned.
same_crs = (
    source_sr.projectionName == TARGET_SR.projectionName
    and source_sr.datumName == TARGET_SR.datumName
    and source_sr.falseEasting == TARGET_SR.falseEasting
    and source_sr.falseNorthing == TARGET_SR.falseNorthing
    and source_sr.centralMeridian == TARGET_SR.centralMeridian
    and source_sr.standardParallel1 == TARGET_SR.standardParallel1
    and source_sr.standardParallel2 == TARGET_SR.standardParallel2
    and source_sr.latitudeOfOrigin == TARGET_SR.latitudeOfOrigin
    and source_sr.linearUnitName == TARGET_SR.linearUnitName
)
if same_crs:
    # Already in this project's CRS -- plain file copy instead of
    # ProjectRaster, so the source's NoData value and every pixel are
    # carried through byte-for-byte. No resampling step means no chance of
    # it mishandling NoData the way the old gdb-embedded export did.
    print(f"  already matches target CRS ({source_sr.name}) -- copying, not reprojecting")
    shutil.copy2(habitat_forest_source, forest_out)
else:
    print(f"  reprojecting ({source_sr.name} -> {TARGET_SR.name})...")
    # NEAREST: forest cover is categorical (land-cover class codes) -- any other
    # resampling method would blend class codes into meaningless values.
    arcpy.management.ProjectRaster(habitat_forest_source, forest_out, TARGET_SR, "NEAREST")
print("  ->", forest_out)

for name, src in vector_sources.items():
    print(f"reprojecting {name}...")
    out_fc = os.path.join(gdb, name)
    arcpy.management.Project(src, out_fc, TARGET_SR)
    print("  ->", out_fc, "|", arcpy.management.GetCount(out_fc)[0], "features")

print("\nwrote", habitat_dir, "(", gdb, "+", forest_out, ")")
print("total elapsed:", round(time.time() - start_time, 1), "sec")
