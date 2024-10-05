# Sum direct threat area by ecoregion to get the following area for direct threats:
  # Forestry - using intensity > 0.1. Note some older cut-blocks have intensity of <0.1
  # Transport High intensity - Transport values > 0.1 which include all major roads
  # Transport Low intensity - Transport values < 0.1 which include small forestry roads
  # Energy - All values > 0.1, i.e. all values
  # Built up - All values > 0.1, i.e. all values
  # Agriculture - All values > 0.1, i.e. all values

# Not currently reporting:
  # Pollution - difficult to put a footrpint on this because values are continuous and often very low
  # Human intrusion - I would consider this an indirect threat and correlated with roads and built up
  # Reservoirs - not sure this one will be of that much use for the ERAPs


rm(list = ls(all.names = TRUE))
gc()

start_time <- Sys.time()

library(sf)
library(terra)
library(exactextractr)
library(tidyr)
library(dplyr)
library(readr)

# create output folder
if(!dir.exists("output")){
  dir.create("output")
}

# Load threat data
forestry <- rast("C:/Users/marc.edwards/Documents/gisdata/Canada_human_modification/HM_Aug21_2024_projected_30m/HM_CA_fr2022_r90_merged_prj_30.tif")
transport <- rast("C:/Users/marc.edwards/Documents/gisdata/Canada_human_modification/HM_Aug21_2024_projected_30m/HM_CA_tr2022_r90_merged_prj_30.tif")
energy <- rast("C:/Users/marc.edwards/Documents/gisdata/Canada_human_modification/HM_Aug21_2024_projected_30m/HM_CA_en2022_r90_merged_prj_30.tif")
builtup <- rast("C:/Users/marc.edwards/Documents/gisdata/Canada_human_modification/HM_Aug21_2024_projected_30m/HM_CA_bu2022_r90_merged_prj_30.tif")
agriculture <- rast("C:/Users/marc.edwards/Documents/gisdata/Canada_human_modification/HM_Aug21_2024_projected_30m/HM_CA_ag2022_r90_merged_prj_30.tif")

# Open ecoregions
ecozone_list <- c(4,5,6,7,8,9,10,11,12,13,14,15)
ecoregions <- st_read("C:/Users/marc.edwards/Documents/gisdata/national_ecological_framework/Ecoregions/ecoregions_albers_dslv.shp") %>%
  filter(ECOZONE %in% ecozone_list) # filter to the ecozone we ran prioritizr on

# calculate conversion factor to km2
km2_conversion <- prod(res(forestry)/1000)

# Prep output table
tib <- ecoregions %>%
  st_drop_geometry() %>%
  select("ECOREGION", "land_km2") %>%
  sort(c("ECOREGION")) %>%
  distinct() %>%
  mutate(forestry_km2 = NA,
         forestry_pcnt = NA,
         agriculture_km2 = NA,
         agriculture_pcnt = NA,
         transport_high_km2 = NA,
         transport_high_pcnt = NA,
         transport_low_km2 = NA,
         transport_low_pcnt = NA,
         energy_km2 = NA,
         energy_pcnt = NA,
         builtup_km2 = NA,
         builtup_pcnt = NA) %>%
  as_tibble()

# Functions for calculating footprint greater than or less than 0.1
mod_area_fun_high <- function(df){
  df <- df[!is.na(df$value) & df$value >= 0.1,]
  sum(df$coverage_fraction)
}
mod_area_fun_low <- function(df){
  df <- df[!is.na(df$value) & df$value > 0 & df$value < 0.1,]
  sum(df$coverage_fraction)
}

for(eco in tib$ECOREGION){
  
  print(paste0("processing ecoregion...", eco))
  
  # filter to get ecoregion polygons
  eco_sf <- ecoregions[ecoregions$ECOREGION == eco,]  %>%
    st_union()
  
  # Get all footprint areas
  tib$forestry_km2[tib$ECOREGION == eco] <- exactextractr::exact_extract(forestry, eco_sf, summarize_df = TRUE, fun = mod_area_fun_high) * km2_conversion
  tib$transport_high_km2[tib$ECOREGION == eco] <- exactextractr::exact_extract(transport, eco_sf, summarize_df = TRUE, fun = mod_area_fun_high) * km2_conversion
  tib$transport_low_km2[tib$ECOREGION == eco] <- exactextractr::exact_extract(transport, eco_sf, summarize_df = TRUE, fun = mod_area_fun_low) * km2_conversion
  tib$energy_km2[tib$ECOREGION == eco] <- exactextractr::exact_extract(energy, eco_sf, summarize_df = TRUE, fun = mod_area_fun_high) * km2_conversion
  tib$agriculture_km2[tib$ECOREGION == eco] <- exactextractr::exact_extract(agriculture, eco_sf, summarize_df = TRUE, fun = mod_area_fun_high) * km2_conversion
  tib$builtup_km2[tib$ECOREGION == eco] <- exactextractr::exact_extract(builtup, eco_sf, summarize_df = TRUE, fun = mod_area_fun_high) * km2_conversion
}

tib[3:8] <- round(tib[3:8], 2)

tib$forestry_pcnt <- tib$forestry_km2 / tib$land_km2 * 100
tib$agriculture_pcnt <- tib$agriculture_km2 / tib$land_km2 * 100
tib$transport_high_pcnt <- tib$transport_high_km2 / tib$land_km2 * 100
tib$transport_low_pcnt <- tib$transport_low_km2 / tib$land_km2 * 100
tib$energy_pcnt <- tib$energy_km2 / tib$land_km2 * 100
tib$builtup_pcnt <- tib$builtup_km2 / tib$land_km2 * 100

tib$land_km2 <- NULL

# save results table
write_csv(tib, "processing/threats/direct_threats.csv")

Sys.time() - start_time