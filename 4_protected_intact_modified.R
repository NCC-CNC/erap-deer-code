# Calculate the following for each ecoregion:
# ecoregion total area
# ecoregion inland area
# area in protection
# inland area in protection
# inland unprotected and intact (calculate as area in ecoregion minus area in PAs based on the HM raster layer)
# inland unprotected and modified (calculate as area in ecoregion minus area in PAs based on the HM raster layer)

# intact and modified layers are pre-calculated from the HM raster.
# Intact is defined as <0.1 and modified as >0.1

rm(list = ls(all.names = TRUE))
gc()

library(sf)
library(terra)
library(exactextractr)
library(tidyr)
library(dplyr)
library(readr)
library(readxl)
library(openxlsx)

# Setup ------------------------------------------------------------------------

# create output folder
if(!dir.exists("processing/protected_intact_modified/")){
  dir.create("processing/protected_intact_modified/")
}

# Load PAs
pa_sf <- st_read("C:/Users/marc.edwards/Documents/gisdata/protected_areas_2024/ProtectedConservedArea.gdb","cpcad_ncc_dslv_july2024")

# Open ecoregions
ecozone_list <- c(4,5,6,7,8,9,10,11,12,13,14,15)
ecoregions <- st_read("C:/Users/marc.edwards/Documents/gisdata/national_ecological_framework/Ecoregions/ecoregions_albers_dslv.shp") %>%
  filter(ECOZONE %in% ecozone_list) # filter to the ecozone we ran prioritizr on
ecoregions_inland <- st_read("C:/Users/marc.edwards/Documents/gisdata/national_ecological_framework/Ecoregions/ecoregions_dslv_clipped_to_2016_census_boundary.shp")

# Load intact and not-intact
intact <- rast("C:/Users/marc.edwards/Documents/gisdata/Canada_human_modification/HM_Aug21_2024_projected_30m/HM_CA_2022_r90_merged_prj_30_intact.tif")
modified <- rast("C:/Users/marc.edwards/Documents/gisdata/Canada_human_modification/HM_Aug21_2024_projected_30m/HM_CA_2022_r90_merged_prj_30_modified.tif")

# calculate conversion factor to km2
km2_conversion <- prod(res(intact)/1000)

# Prep output table
tib <- ecoregions %>%
  st_drop_geometry() %>%
  select("ECOREGION", "ECOZONE") %>%
  sort(c("ECOZONE", "ECOREGION")) %>%
  distinct() %>%
  mutate(ecoregion_km2 = NA,
         ecoregion_inland_km2 = NA,
         protected_km2 = NA,
         protected_inland_km2 = NA,
         protected_pcnt = NA,
         protected_inland_pcnt = NA,
         unprotected_inland_intact_km2 = NA,
         unprotected_intact_pcnt = NA,
         unprotected_inland_modified_km2 = NA,
         unprotected_modified_pcnt = NA) %>%
  as_tibble()


# Processing ------------------------------------------------------------------------

for(eco in tib$ECOREGION){
  
  print(paste0("processing ecoregion...", eco))
  
  # filter to get ecoregion polygons
  eco_sf <- ecoregions[ecoregions$ECOREGION == eco,]  %>%
    st_union()
  
  eco_inland_sf <- ecoregions_inland[ecoregions_inland$ECOREGION == eco,]  %>%
    st_union()
  
  # add ecoregion areas
  tib$ecoregion_km2[tib$ECOREGION == eco] <- ecoregions$area_km2[tib$ECOREGION == eco]
  tib$ecoregion_inland_km2[tib$ECOREGION == eco] <- ecoregions$land_km2[tib$ECOREGION == eco]
  
  # calc PA areas
  eco_pa_sf <- st_intersection(pa_sf, eco_sf) %>% st_union()
  tib$protected_km2[tib$ECOREGION == eco] <- sum(as.numeric(st_area(eco_pa_sf)))/1000000
  
  eco_pa_inland_sf <- st_intersection(pa_sf, eco_inland_sf) %>% st_union()
  tib$protected_inland_km2[tib$ECOREGION == eco] <- sum(as.numeric(st_area(eco_pa_inland_sf)))/1000000
  
  # extract intact and modified values for inland portion of ecoregion (i.e. exclude great lakes in ON from the HM layer)
  intact_eco <- exactextractr::exact_extract(intact, eco_inland_sf, 'sum') * km2_conversion
  modified_eco <- exactextractr::exact_extract(modified, eco_inland_sf, 'sum') * km2_conversion
  
  # extract protected areas intact and modified values for inland portion of ecoregion
  # We will subtract these from the ecoregion values to get the unprotected portion
  # if there's no PAs, set to zero
  if(tib$protected_inland_km2[tib$ECOREGION == eco] > 0){
    intact_pa <- exactextractr::exact_extract(intact, eco_pa_inland_sf, 'sum') * km2_conversion
    modified_pa <- exactextractr::exact_extract(modified, eco_pa_inland_sf, 'sum') * km2_conversion
  } else{
    intact_pa <- 0
    modified_pa <- 0
  }
  
  # Calculate unprotected areas of intact and modified by subtracted protected from ecoregion total
  tib$unprotected_inland_intact_km2[tib$ECOREGION == eco] <- intact_eco - intact_pa
  tib$unprotected_inland_modified_km2[tib$ECOREGION == eco] <- modified_eco - modified_pa
}

# Calculate % values for all rows
tib$protected_pcnt <- (tib$protected_km2 / tib$ecoregion_km2) * 100
tib$protected_inland_pcnt <- (tib$protected_inland_km2 / tib$ecoregion_inland_km2) * 100
tib$unprotected_intact_pcnt <- (tib$unprotected_inland_intact_km2 / (tib$unprotected_inland_intact_km2 + tib$unprotected_inland_modified_km2)) * 100
tib$unprotected_modified_pcnt <- (tib$unprotected_inland_modified_km2 / (tib$unprotected_inland_intact_km2 + tib$unprotected_inland_modified_km2)) * 100

# save table
write_csv(round(tib, 2), "processing/protected_intact_modified/protected_intact_modified.csv")
