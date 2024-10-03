# WTW values are reported against two ecoregion options:
  # 1 - the full ecoregion polygon which extends into the oceans and great lakes
  # 2 - a clipped version of the ecoregions that removes oceans and great lakes using the 2016 cencus boundaries

# Intersect rasters with ecoregions to get the following values:

  # Area of ecoregion
  # Inland area of ecoregion (clipped to remove oceans and great lakes)

  # Area of solution (version that has includes removed) in full ecoregion
  # Inland area of solution (version that has includes removed)

  # Area of Includes
  # Inland area of Includes

# This lets us calculate the following value:
  # WTW area - WTw solution in the full ecoregion
  # WTW inland area - WTw area in the inland section of ecoregion
  # WTW % - % of the unproteted portion of the full ecoregion covered by WTw solution. Calculated as: wtw area / (ecoregion area - Includes area) * 100
  # WTW inland % - % of the inland unproteted portion of the full ecoregion covered by WTw solution. Calculated as: inland wtw area / (inland ecoregion area - inland Includes area) * 100
  

library(dplyr)
library(terra)
library(sf)
library(exactextractr)
library(readr)

# Set parameters ------------------------------------------------------------

# Open Includes
includes <- rast("C:/Users/marc.edwards/Documents/gisdata/protected_areas_2024/Dans_updated_WTW_Includes_July_2024/Existing_Conservation.tif")

# Open solution
s1 <- rast("processing/prioritizr/ecozones/Canada_wtw_2024_noIncludes.tif") # 79.2 M has

# Open ecoregions
ecozone_list <- c(4,5,6,7,8,9,10,11,12,13,14,15)
ecoregions <- st_read("C:/Users/marc.edwards/Documents/gisdata/national_ecological_framework/Ecoregions/ecoregions_albers_dslv.shp") %>%
  st_transform(st_crs(includes)) %>%
  filter(ECOZONE %in% ecozone_list) # filter to the ecozone we ran prioritizr on
ecoregions_inland <- st_read("C:/Users/marc.edwards/Documents/gisdata/national_ecological_framework/Ecoregions/ecoregions_dslv_clipped_to_2016_census_boundary.shp")


# calculate areas and populate table -------------------------------------

tib <- ecoregions %>%
  st_drop_geometry() %>%
  select("ECOREGION", "ECOZONE") %>%
  sort(c("ECOZONE", "ECOREGION")) %>%
  distinct() %>%
  mutate(wtw_area_km2 = NA,
         wtw_area_inland_km2 = NA,
         wtw_percent = NA,
         wtw_inland_percent = NA)

for(eco in tib$ECOREGION){
  
  print(paste0("processing ecoregion...", eco))

  # filter to get ecoregion polygons(s)
  eco_sf <- ecoregions[ecoregions$ECOREGION == eco,]
  eco_inland_sf <- ecoregions_inland[ecoregions_inland$ECOREGION == eco,]
  
  # calculate total ecoregion area (pre-calculated manually in arcgis)
  eco_area_km2 <- ecoregions$area_km2[ecoregions$ECOREGION == eco]
  eco_inland_area_km2 <- ecoregions$land_km2[ecoregions$ECOREGION == eco]
  
  # calculate Includes area
  includes_km2 <- sum(exact_extract(includes, eco_sf, 'sum'))
  includes_inland_km2 <- sum(exact_extract(includes, eco_inland_sf, 'sum'))
  
  # calculate prioritizr area
  prz_km2 <- sum(exact_extract(s1, eco_sf, 'sum'))
  prz_inland_km2 <- sum(exact_extract(s1, eco_inland_sf, 'sum'))
  
  # calculate % of non-include ecoregion area that is a priority 
  pcnt_prz <- (prz_km2 / (eco_area_km2 - includes_km2)) * 100
  pcnt_prz_inland <- (prz_inland_km2 / (eco_inland_area_km2 - includes_inland_km2)) * 100
  
  # add to table
  tib$wtw_area_km2[tib$ECOREGION == eco] <- round(prz_km2, 1)
  tib$wtw_area_inland_km2[tib$ECOREGION == eco] <- round(prz_inland_km2, 1)
  tib$wtw_percent[tib$ECOREGION == eco] <- round(pcnt_prz, 1)
  tib$wtw_inland_percent[tib$ECOREGION == eco] <- round(pcnt_prz_inland, 1)
}

write_csv(tib, "processing/prioritizr/ecozones/Canada_wtw_2024_ecoregion_proportions.csv")
