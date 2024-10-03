# Script to calcualte the area of vector habitat in each ecoregion
# And in each ecoregions existing protected area network
# And in each ecoregions WTw solution

# Workflow:
  # For ecoregion areas
    # Intersect habitat feature with ecoregions
    # Dissolve on ecoregion
    # Calculate area or length of habitat in each ecoregion
  # For PAs in each ecoregion
    # Clip habitat feature to PAs, then repeat the above steps

import arcpy

arcpy.env.overwriteOutput = True

### SETUP ################################

# Set input paths
ecoregions_path = "C:/Users/marc.edwards/Documents/gisdata/national_ecological_framework/Ecoregions/ecoregions.shp"
ecoregions_inland_path = "C:/Users/marc.edwards/Documents/gisdata/national_ecological_framework/Ecoregions/ecoregions_dslv_clipped_to_2016_census_boundary.shp"
protected_areas = "C:/Users/marc.edwards/Documents/gisdata/protected_areas_2024/ProtectedConservedArea.gdb/cpcad_ncc_dslv_july2024"
wtw_solution = "C:/Users/marc.edwards/Documents/PROJECTS/Canada_wide_ecoregion_assessments/processing/prioritizr/ecozones/Canada_wtw_2024_noIncludes.shp"

grassland_path = "C:/Users/marc.edwards/Documents/gisdata/habitat_metrics_Jul24_2024/habitat.gdb/AAFC_LUTS_2020"
wetland_path = "C:/Users/marc.edwards/Documents/gisdata/habitat_metrics_Jul24_2024/habitat.gdb/canvec_saturated_soil_2_merge_20230201_pw_dissolve"
lakes_path = "C:/Users/marc.edwards/Documents/gisdata/habitat_metrics_Jul24_2024/habitat.gdb/waterbody_2_proj_diss"
shoreline_path = "C:/Users/marc.edwards/Documents/gisdata/habitat_metrics_Jul24_2024/habitat.gdb/shoreline_merge"
rivers_path = "C:/Users/marc.edwards/Documents/gisdata/habitat_metrics_Jul24_2024/habitat.gdb/water_linear_flow_1"
rivers_50k_path = "C:/Users/marc.edwards/Documents/gisdata/hydrology/NHN/master_rivers.gdb/master_rivers"


# Set output paths
if not arcpy.Exists("C:/temp/habitat.gdb"):
    arcpy.CreateFileGDB_management("C:/temp", "habitat.gdb")

if not arcpy.Exists("../processing/habitat/habitat.gdb"):
    arcpy.CreateFileGDB_management("../processing/habitat", "habitat.gdb")


# Set prj
ncc_prj = "C:/Users/marc.edwards/Documents/gisdata/habitat_metrics_Jul24_2024/Forest_LC_30m_2022.tif"
arcpy.env.outputCoordinateSystem = arcpy.Describe(ncc_prj).spatialReference

# list of ecoregions to process - all the ecoregions is this list of ecozones
ecozone_list = [4,5,6,7,8,9,10,11,12,13,14,15]

eco_list = []
with arcpy.da.SearchCursor(ecoregions_path, ['ECOZONE', 'ECOREGION']) as cursor:
    for row in cursor:
        if row[0] in ecozone_list:
            eco_list.append(row[1])

eco_list = set(eco_list)


# Prep the ecoregions ready to do the intersects. Note that PAs are already dissolved so no prep needed

# Subset ecoregions by eco_list
query = """{0} IN {1}""".format(arcpy.AddFieldDelimiters(ecoregions_path, 'ECOREGION'), str(tuple(eco_list)))
ecoregions = arcpy.management.SelectLayerByAttribute(ecoregions_path, "NEW_SELECTION", query)

# Subset inland ecoregions by eco_list - using inland ecoregions to intersect lakes and rivers. This could be dropped if lakes and rivers clipped to inland area at source
query = """{0} IN {1}""".format(arcpy.AddFieldDelimiters(ecoregions_inland_path, 'ECOREGION'), str(tuple(eco_list)))
ecoregions_inland = arcpy.management.SelectLayerByAttribute(ecoregions_inland_path, "NEW_SELECTION", query)


for h in ["grassland", "wetland", "lakes", "rivers", "shoreline", "rivers_50k"]:
    
    print("Processing..." + h)

    # Set paths
    intersect = "C:/temp/habitat.gdb/intersect_" + h
    intersect_dslv = "../output/habitat.gdb/" + h + "_by_ecoregion"
    intersect_dslv_pas = "../output/habitat.gdb/" + h + "_by_ecoregion_pas"
    intersect_dslv_wtw = "../output/habitat.gdb/" + h + "_by_ecoregion_wtw"

    # Set parameters    
    if h == "grassland":
        aoi_path = ecoregions
        h_path = grassland_path
        colname = "grassland_km2"
        query = "!shape.area@squarekilometers!"
    if h == "wetland":
        aoi_path = ecoregions
        #h_path = wetland_path
        print("repairing geometry..")
        arcpy.management.MultipartToSinglepart(h_path, "C:/temp/habitat.gdb/wetland_dslv") # got an invalid topology error that needs fixing. Dissolve and RepairGeometry didn't work. Exploding did.
        h_path = "C:/temp/habitat.gdb/wetland_dslv"
        colname = "wetland_km2"
        query = "!shape.area@squarekilometers!"
    if h =="lakes":
        aoi_path = ecoregions_inland
        h_path = lakes_path
        colname = "lakes_km2"
        query = "!shape.area@squarekilometers!"
    if h =="shoreline":
        aoi_path = ecoregions
        h_path = shoreline_path
        colname = "shoreline_km"
        query = "!shape.length@kilometers!"
    if h =="rivers":
        aoi_path = ecoregions_inland
        h_path = rivers_path
        colname = "rivers_km"
        query = "!shape.length@kilometers!"
    if h =="rivers_50k":
        aoi_path = ecoregions_inland
        h_path = rivers_50k_path
        colname = "rivers_50k_km"
        query = "!shape.length@kilometers!"

    
    
    ### ECOREGION AREAS #######################

    # Intersect habitat with ecoregions
    print("intersect...")
    arcpy.analysis.Intersect([aoi_path, h_path], intersect)

    # Dissolve on ecoregion to make sure there is no overlap
    print("dissolve...")
    arcpy.analysis.PairwiseDissolve(intersect, intersect_dslv, "ECOREGION")
    
    # Calculate area field in km2
    arcpy.management.AddField(intersect_dslv, colname, "DOUBLE")
    arcpy.management.CalculateField(intersect_dslv, colname, query)
    

    ### PROTECTED AREAS #######################

    # Clip intersect_dslv to the PAs
    print("clip PAs...")
    arcpy.analysis.PairwiseClip(intersect_dslv, protected_areas, intersect_dslv_pas)
    arcpy.management.DeleteField(intersect_dslv_pas, colname)
    arcpy.management.AddField(intersect_dslv_pas, colname + "_pa", "DOUBLE")
    arcpy.management.CalculateField(intersect_dslv_pas, colname + "_pa", query)
    
    ### WTW solution #######################
    print("clip WTW...")
    arcpy.analysis.PairwiseClip(intersect_dslv, wtw_solution, intersect_dslv_wtw)
    arcpy.management.DeleteField(intersect_dslv_wtw, colname)
    arcpy.management.AddField(intersect_dslv_wtw, colname + "_wtw", "DOUBLE")
    arcpy.management.CalculateField(intersect_dslv_wtw, colname + "_wtw", query)
    
    ### EXPORT TABLES FOR FASTER READING IN R ###
    print("export tables...")
    arcpy.conversion.TableToTable(intersect_dslv, "../output/habitat.gdb", h + "_by_ecoregion_table")    
    arcpy.conversion.TableToTable(intersect_dslv_pas, "../output/habitat.gdb", h + "_by_ecoregion_pa_table")
    arcpy.conversion.TableToTable(intersect_dslv_wtw, "../output/habitat.gdb", h + "_by_ecoregion_wtw_table")
