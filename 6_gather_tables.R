# Gather ERAP tables into the csv that will be hosted in the map viewer

rm(list = ls(all.names = TRUE))
gc()

library(tidyverse)
library(sf)
library(openxlsx)

### 1. PREP ATTRIBUTE TABLE ###

# load tables
protected <- read_csv("processing/protected_intact_modified/protected_intact_modified.csv") %>%
  select(ECOREGION,
         ECOZONE,
         ecoregion_km2,
         protected_km2,
         protected_pcnt,
         protected_inland_pcnt,
         unprotected_intact_pcnt,
         unprotected_modified_pcnt)

habitat <- read_csv("processing/habitat/final_habitat_table.csv")

threats <- read_csv("processing/threats/direct_threats.csv") %>%
  select(ECOREGION,
         forestry_km2,
         agriculture_km2,
         transport_high_km2,
         transport_low_km2,
         energy_km2,
         builtup_km2)

wtw <- read_csv("processing/prioritizr/ecozones/Canada_wtw_2024_ecoregion_proportions.csv") %>%
  select(ECOREGION,
         wtw_area_km2,
         wtw_area_inland_km2,
         wtw_percent,
         wtw_inland_percent)

actions <- read_csv("processing/action_recommendations/action_recommendations_wide.csv")

df <- protected %>%
  left_join(habitat, by = "ECOREGION") %>%
  left_join(threats, by = "ECOREGION") %>%
  left_join(wtw, by = "ECOREGION") %>%
  left_join(actions, by = "ECOREGION")

write_csv(df, "output/ERAP_attributes.csv")
#write.xlsx(df, "output/ERAP_attributes.xlsx")



### 2. PREP ECOREGION SHP ###
ecozone_list <- c(4,5,6,7,8,9,10,11,12,13,14,15)
shp <- st_read("C:/Users/marc.edwards/Documents/gisdata/national_ecological_framework/Ecoregions/ecoregions_albers_dslv.shp") %>%
  filter(ECOZONE %in% ecozone_list) %>%# filter to the ecozone we ran prioritizr on
  select(ECOREGION,
         REGION_NAM,
         REGION_NOM)

st_write(shp, "ERAP_ecoregions.shp")