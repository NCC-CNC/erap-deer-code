# Sum forest area by ecoregion
# Sum forest area protected by ecoregion

# Using same method as for species sums.

start_time <- Sys.time()

library(sf)
library(terra)
library(exactextractr)
library(tidyr)
library(dplyr)
library(readr)
library(readxl)

# Load PAs
pa <- st_read("C:/Users/marc.edwards/Documents/gisdata/protected_areas_2024/ProtectedConservedArea.gdb","cpcad_ncc_dslv_july2024")
wtw <- st_read("C:/Users/marc.edwards/Documents/PROJECTS/Canada_wide_ecoregion_assessments/processing/prioritizr/ecozones/Canada_wtw_2024_noIncludes.shp")

# Load ecoregions
ecozone_list <- c(4,5,6,7,8,9,10,11,12,13,14,15)
ecoregions <- st_read("C:/Users/marc.edwards/Documents/gisdata/national_ecological_framework/Ecoregions/ecoregions_albers_dslv.shp") %>%
  filter(ECOZONE %in% ecozone_list) # filter to the ecozone we ran prioritizr on

# Load forests
forests <- rast("C:/Users/marc.edwards/Documents/gisdata/habitat_metrics_Jul24_2024/Forest_LC_30m_2022.tif")

# calculate conversion factor to km2
km2_conversion <- prod(res(forests)/1000)



# Run processing

ecoregion_list <- unique(ecoregions$ECOREGION)
tib <- tibble(ECOREGION = ecoregion_list, eco_km2 = -999, forest_km2 = -999, forest_protected_km2 = -999)

for(ecoregion in ecoregion_list){
  
  print(ecoregion)
  
  # get ecoregion polygon
  eco_sf <- ecoregions[ecoregions$ECOREGION == ecoregion,]
  tib$eco_km2[tib$ECOREGION == ecoregion] <- sum(as.numeric(st_area(eco_sf)))/1000000
  
  # extract values for ecoregion
  val_eco <- exactextractr::exact_extract(forests, st_union(eco_sf), 'sum') * km2_conversion
  
  # extract values for PA
  eco_pa_sf <- st_intersection(pa, eco_sf)
  if(nrow(eco_pa_sf) > 0){
    val_pa <- exactextractr::exact_extract(forests, st_union(eco_pa_sf), 'sum') * km2_conversion
  } else{
    val_pa <- 0 # if no pas set val to 0
  }
  
  # extract values for WTW
  eco_wtw_sf <- st_intersection(wtw, eco_sf)
  if(nrow(eco_wtw_sf) > 0){
    val_wtw <- exactextractr::exact_extract(forests, st_union(eco_wtw_sf), 'sum') * km2_conversion
  } else{
    val_wtw <- 0 # if no pas set val to 0
  }
  
  tib$forest_km2[tib$ECOREGION == ecoregion] <- val_eco
  tib$forest_protected_km2[tib$ECOREGION == ecoregion] <- val_pa
  tib$forest_wtw_km2[tib$ECOREGION == ecoregion] <- val_wtw
}

Sys.time() - start_time

# check all cells added positive values
min(tib$forest_km2)
min(tib$forest_protected_km2)
min(tib$forest_wtw_km2)
min(tib$eco_km2)

# check all forest areas are less than ecoregion areas and all protected less than total
min(tib$eco_km2 - tib$forest_km2)
min(tib$forest_km2 - tib$forest_protected_km2)
min(tib$forest_km2 - tib$forest_wtw_km2)

# save results table
write_csv(tib, "C:/Users/marc.edwards/Documents/PROJECTS/Canada_wide_ecoregion_assessments/processing/habitat/forests_sums.csv")
