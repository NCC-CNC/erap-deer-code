# script to convert the WTW solution to a polygon for use in habitat extractions

import arcpy

wtw = "C:/Users/marc.edwards/Documents/PROJECTS/Canada_wide_ecoregion_assessments/processing/prioritizr/ecozones/Canada_wtw_2024_noIncludes.tif"
wtw_poly_temp = "C:/Users/marc.edwards/Documents/PROJECTS/Canada_wide_ecoregion_assessments/processing/prioritizr/ecozones/Canada_wtw_2024_noIncludes_temp.shp"
wtw_poly = "C:/Users/marc.edwards/Documents/PROJECTS/Canada_wide_ecoregion_assessments/processing/prioritizr/ecozones/Canada_wtw_2024_noIncludes.shp"

arcpy.conversion.RasterToPolygon(wtw, wtw_poly_temp, simplify = False)

x = arcpy.management.SelectLayerByAttribute(wtw_poly_temp, "NEW_SELECTION", "gridcode = 1")
arcpy.management.CopyFeatures(x, wtw_poly)

arcpy.management.Delete(wtw_poly_temp)
