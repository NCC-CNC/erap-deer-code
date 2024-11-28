# clip all gis data to be shown in the pdf maps to each ecozone

# Then run the following workflow in ArcGIS Pro:
#1. Run this script
#2. Set up a map in ArcGIS Pro for the first ecozone with the required layers, in the correct order, with the names set in the TOC, and the color and legends you want
#3. Save as a template file
#4. Open a new map using the template, update the workspace source data location in the catalog pane, set the input to be the gdb for the next ecozone you want to make a map for
#5. Save as a new project file for the ecozone. 
#6. Export pdf map from Share>Export map. v1 I used 5000 px width or height depending on the shape of the ecozone. Max quality. Compress vetors. Best resample. Tick Export georeference infomraiton: PDF Layer only.
#7. Repeat for each ecozone.


import arcpy
from arcpy.sa import *
from pathlib import Path

arcpy.env.overwriteOutput = True

# Set prj
ncc_prj = "C:/Users/marc.edwards/Documents/gisdata/habitat_metrics_Jul24_2024/Forest_LC_30m_2022.tif" # This needs to point to any file with the NCC Albers prj
arcpy.env.outputCoordinateSystem = arcpy.Describe(ncc_prj).spatialReference

# Create output folder
map_dir = "../processing/Maps"
Path(map_dir).mkdir(parents=True, exist_ok=True)

# list of ecoregions to process - all the ecoregions is this list of ecozones
ecozone_list = [4,5,6,7,8,9,10,11,12,13,14,15]

# Set paths
# S drive location: S:/CONS_TECH/PRZ/DATA/PREP/xCANADA_WIDE_SOURCE/ecozones_albers_dslv.shp
ecozones = "C:/Users/marc.edwards/Documents/gisdata/national_ecological_framework/Ecozones/ecozones_albers_dslv.shp"
# S drive location: S:/ERAPs/output/ERAP_ecoregions.gdb/ERAP_ecoregions
ecoregions = "C:/Users/marc.edwards/Documents/gisdata/national_ecological_framework/Ecoregions/ecoregions_albers_dslv.shp"
# S drive location: S:/CONS_TECH/PRZ/DATA/PREP/xCANADA_WIDE_SOURCE/ecodistricts_albers_dslv.shp
ecodistricts = "C:/Users/marc.edwards/Documents/gisdata/national_ecological_framework/Ecodistricts/ecodistricts_albers_dslv.shp"

# S drive location: S:/CONS_TECH/PRZ/DATA/PREP/xCANADA_WIDE_SOURCE/protected_areas_2024.gdb/cpcad_ncc_dslv_july2024
cpcad_ncc_protected = "C:/Users/marc.edwards/Documents/gisdata/protected_areas_2024/ProtectedConservedArea.gdb/cpcad_ncc_dslv_july2024"
# S drive location: S:/CONS_TECH/PRZ/DATA/PREP/Habitat/Grassland/Processing.gdb/RasterToPoly/AAFC_LUTS_2020
grassland_path = "C:/Users/marc.edwards/Documents/gisdata/habitat_metrics_Jul24_2024/habitat.gdb/AAFC_LUTS_2020"
# S drive location: S:/CONS_TECH/PRZ/DATA/PREP/Habitat/Wetland/Processing.gdb/canvec_saturated_soil_2_merge_20230201_pw_dissolve
#wetland_path = "C:/Users/marc.edwards/Documents/gisdata/habitat_metrics_Jul24_2024/habitat.gdb/canvec_saturated_soil_2_merge_20230201_pw_dissolve"
wetland_path = "C:/temp/habitat.gdb/wetland_dslv" # fixed topology error by exploding
# S drive location: S:/CONS_TECH/PRZ/DATA/PREP/Habitat/Lakes/_archive/Z_DELETE/Waterbody.gdb/waterbody_2_proj_diss
lakes_path = "C:/Users/marc.edwards/Documents/gisdata/habitat_metrics_Jul24_2024/habitat.gdb/waterbody_2_proj_diss"
# S drive location: S:/CONS_TECH/PRZ/DATA/PREP/xCANADA_WIDE_SOURCE/shoreline.gdb/shoreline_merge
shoreline_path = "C:/Users/marc.edwards/Documents/gisdata/habitat_metrics_Jul24_2024/habitat.gdb/shoreline_merge"
# S drive location: S:/hydrology_data_temp_location/NHN/master_rivers.gdb/master_rivers
rivers_path = "C:/Users/marc.edwards/Documents/gisdata/hydrology/NHN/master_rivers.gdb/master_rivers"

# tifs
# S drive location: S:/CONS_TECH/PRZ/DATA/PREP/xCANADA_WIDE_SOURCE/Canada_wtw_2024.tif
where_to_work_prioritization = "C:/Users/marc.edwards/Documents/PROJECTS/Canada_wide_ecoregion_assessments/processing/prioritizr/ecozones/Canada_wtw_2024.tif"
# S drive location: S:/CONS_TECH/PRZ/DATA/NAT_1KM/biod/rich/biod_rich.tif
species_biodiversity_count = "C:/Data/PRZ/WTW_DATA/WTW_NAT_DATA_20240522/biodiversity/richness/BOID_COUNT.tif"
# S drive location: S:/CONS_TECH/PRZ/DATA/NAT_1KM/biod/rich/sar_rich.tif
species_sar_count = "C:/Data/PRZ/WTW_DATA/WTW_NAT_DATA_20240522/biodiversity/richness/ECCC_SAR_COUNT.tif"
# S drive location: S:/CONS_TECH/PRZ/DATA/PREP/Habitat/Forest/Forest_LC_30m_2022.tif
habitat_forests = "C:/Users/marc.edwards/Documents/gisdata/habitat_metrics_Jul24_2024/Forest_LC_30m_2022.tif"
# S drive location: S:/CONS_TECH/PRZ/DATA/PREP/xCANADA_WIDE_SOURCE/HM_CA_2022_r90_merged_prj_30_intact.tif
intact_land = "C:/Users/marc.edwards/Documents/gisdata/Canada_human_modification/HM_Aug21_2024_projected_30m/HM_CA_2022_r90_merged_prj_30_intact.tif"
# S drive location: S:/CONS_TECH/PRZ/DATA/PREP/xCANADA_WIDE_SOURCE/HM_CA_2022_r90_merged_prj_30_modified.tif
modified_land = "C:/Users/marc.edwards/Documents/gisdata/Canada_human_modification/HM_Aug21_2024_projected_30m/HM_CA_2022_r90_merged_prj_30_modified.tif"
# S drive location: S:/CONS_TECH/PRZ/DATA/PREP/xCANADA_WIDE_SOURCE/HM_CA_fr2022_r90_merged_prj_30.tif
threat_forestry = "C:/Users/marc.edwards/Documents/gisdata/Canada_human_modification/HM_Aug21_2024_projected_30m/HM_CA_fr2022_r90_merged_prj_30.tif"
# S drive location: S:/CONS_TECH/PRZ/DATA/PREP/xCANADA_WIDE_SOURCE/HM_CA_tr2022_r90_merged_prj_30.tif
threat_transport = "C:/Users/marc.edwards/Documents/gisdata/Canada_human_modification/HM_Aug21_2024_projected_30m/HM_CA_tr2022_r90_merged_prj_30.tif"
# S drive location: S:/CONS_TECH/PRZ/DATA/PREP/xCANADA_WIDE_SOURCE/HM_CA_en2022_r90_merged_prj_30.tif
threat_energy = "C:/Users/marc.edwards/Documents/gisdata/Canada_human_modification/HM_Aug21_2024_projected_30m/HM_CA_en2022_r90_merged_prj_30.tif"
# S drive location: S:/CONS_TECH/PRZ/DATA/PREP/xCANADA_WIDE_SOURCE/HM_CA_bu2022_r90_merged_prj_30.tif
threat_builtup = "C:/Users/marc.edwards/Documents/gisdata/Canada_human_modification/HM_Aug21_2024_projected_30m/HM_CA_bu2022_r90_merged_prj_30.tif"
# S drive location: S:/CONS_TECH/PRZ/DATA/PREP/xCANADA_WIDE_SOURCE/HM_CA_ag2022_r90_merged_prj_30.tif
threat_agriculture = "C:/Users/marc.edwards/Documents/gisdata/Canada_human_modification/HM_Aug21_2024_projected_30m/HM_CA_ag2022_r90_merged_prj_30.tif"
# S drive location: S:/CONS_TECH/PRZ/DATA/PREP/xCANADA_WIDE_SOURCE/HM_CA_2022_r90_merged_prj_30.tif
threat_human_modification = "C:/Users/marc.edwards/Documents/gisdata/Canada_human_modification/HM_Aug21_2024_projected_30m/HM_CA_2022_r90_merged_prj_30.tif"

for ecozone in ecozone_list:

    print("ECOZONE..." + str(ecozone))
    
    # Set up gdb for ecozone
    gdb_name = "ecozone_" + str(ecozone) + ".gdb"
    gdb_path = map_dir + "/" + gdb_name
    if not arcpy.Exists(gdb_path):
        arcpy.CreateFileGDB_management(map_dir, gdb_name)

    aoi_name = "ecozone"
    aoi_path = gdb_path + "/" + aoi_name
    
    # extract ecozone boundary
    query = """{0} = {1}""".format(arcpy.AddFieldDelimiters(ecozones, 'ECOZONE'), str(ecozone))
    ecozone_extract = arcpy.management.SelectLayerByAttribute(ecozones, "NEW_SELECTION", query)
    arcpy.conversion.FeatureClassToFeatureClass(ecozone_extract, gdb_path, aoi_name)
    
    # Extract ecoregions and Ecodistricts
    query = """{0} = {1}""".format(arcpy.AddFieldDelimiters(ecoregions, 'ECOZONE'), str(ecozone))
    ecoregion_extract = arcpy.management.SelectLayerByAttribute(ecoregions, "NEW_SELECTION", query)
    arcpy.conversion.FeatureClassToFeatureClass(ecoregion_extract, gdb_path, "ecoregions")

    with arcpy.da.SearchCursor(ecoregions, ['ECOREGION'], 'ECOZONE = ' + str(ecozone)) as cursor:
        ecoregion_list = sorted({row[0] for row in cursor})
    query = """{0} IN {1}""".format(arcpy.AddFieldDelimiters(ecodistricts, 'ECOREGION'), str(tuple(ecoregion_list)))
    ecodistrict_extract = arcpy.management.SelectLayerByAttribute(ecodistricts, "NEW_SELECTION", query)
    arcpy.conversion.FeatureClassToFeatureClass(ecodistrict_extract, gdb_path, "ecodistricts")
    
    # Clip PAs
    print("Clip PAs...")
    arcpy.analysis.Clip(cpcad_ncc_protected, aoi_path, gdb_path + "/cpcad_ncc_protected")

    # Clip habitat vectors 
    print("Clip grassland...")
    arcpy.analysis.PairwiseClip(grassland_path, aoi_path, gdb_path + "/habitat_grassland")
    print("Clip wetland...")
    arcpy.analysis.PairwiseClip(wetland_path, aoi_path, gdb_path + "/habitat_wetland")
    print("Clip lakes...")
    arcpy.analysis.PairwiseClip(lakes_path, aoi_path, gdb_path + "/habitat_lakes")
    print("Clip rivers...")
    arcpy.analysis.PairwiseClip(rivers_path, aoi_path, gdb_path + "/habitat_rivers")
    print("Clip shoreline...")
    arcpy.analysis.PairwiseClip(shoreline_path, aoi_path, gdb_path + "/habitat_shoreline")
    
    # Clip all rasters to AOI
    print("Clip rasters...")
    arcpy.management.Clip(where_to_work_prioritization, "", gdb_path + "/where_to_work_prioritization", in_template_dataset = aoi_path, clipping_geometry = "ClippingGeometry")
    arcpy.management.Clip(species_biodiversity_count, "", gdb_path + "/species_biodiversity_count", in_template_dataset = aoi_path, clipping_geometry = "ClippingGeometry")
    arcpy.management.Clip(species_sar_count, "", gdb_path + "/species_sar_count", in_template_dataset = aoi_path, clipping_geometry = "ClippingGeometry")
    arcpy.management.Clip(habitat_forests, "", gdb_path + "/habitat_forests", in_template_dataset = aoi_path, clipping_geometry = "ClippingGeometry")
    arcpy.management.Clip(intact_land, "", gdb_path + "/intact_land", in_template_dataset = aoi_path, clipping_geometry = "ClippingGeometry")
    arcpy.management.Clip(modified_land, "", gdb_path + "/modified_land", in_template_dataset = aoi_path, clipping_geometry = "ClippingGeometry")
    arcpy.management.Clip(threat_forestry, "", gdb_path + "/threat_forestry", in_template_dataset = aoi_path, clipping_geometry = "ClippingGeometry")
    arcpy.management.Clip(threat_transport, "", gdb_path + "/threat_transport", in_template_dataset = aoi_path, clipping_geometry = "ClippingGeometry")
    arcpy.management.Clip(threat_energy, "", gdb_path + "/threat_energy", in_template_dataset = aoi_path, clipping_geometry = "ClippingGeometry")
    arcpy.management.Clip(threat_builtup, "", gdb_path + "/threat_builtup", in_template_dataset = aoi_path, clipping_geometry = "ClippingGeometry")
    arcpy.management.Clip(threat_agriculture, "", gdb_path + "/threat_agriculture", in_template_dataset = aoi_path, clipping_geometry = "ClippingGeometry")
    arcpy.management.Clip(threat_human_modification, "", gdb_path + "/threat_human_modification", in_template_dataset = aoi_path, clipping_geometry = "ClippingGeometry")
    
