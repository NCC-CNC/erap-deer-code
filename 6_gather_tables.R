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
         ecoregion_km2,
         ecoregion_inland_km2,
         protected_km2,
         protected_pcnt,
         protected_inland_pcnt,
         unprotected_intact_pcnt,
         unprotected_modified_pcnt)

habitat <- read_csv("processing/habitat/final_habitat_table.csv")

threats <- read_csv("processing/threats/direct_threats.csv") %>%
  round(2)

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

# Build ecozone names and join to ecoregions
ecozones <- st_read("C:/Users/marc.edwards/Documents/gisdata/national_ecological_framework/Ecozones/ecozones.shp") %>%
  st_drop_geometry() %>%
  distinct(ECOZONE, ZONE_NAME, ZONE_NOM)

# fix broken names
ecozones$ZONE_NAME[ecozones$ZONE_NAME == "Boreal PLain"] <- "Boreal Plain"
ecozones$ZONE_NOM[ecozones$ZONE_NAME == "Arctic Cordillera"] <- "Cordillère arctique"
ecozones$ZONE_NOM[ecozones$ZONE_NAME == "Taiga Cordillera"] <- "Taïga de la Cordillère"
ecozones$ZONE_NOM[ecozones$ZONE_NAME == "Taiga Plain"] <- "Taïga des plaines"
ecozones$ZONE_NOM[ecozones$ZONE_NAME == "Taiga Shield"] <- "Taïga du Bouclier"
ecozones$ZONE_NOM[ecozones$ZONE_NAME == "Boreal Cordillera"] <- "Cordillère boréale"
ecozones$ZONE_NOM[ecozones$ZONE_NAME == "Boreal Plain"] <- "Plaines boréales"
ecozones$ZONE_NOM[ecozones$ZONE_NAME == "Boreal Shield"] <- "Bouclier boréal"
ecozones$ZONE_NOM[ecozones$ZONE_NAME == "Montane Cordillera"] <- "Cordillère montagnarde"
ecozones$ZONE_NOM[ecozones$ZONE_NAME == "MixedWood Plain"] <- "Plaines à forêts mixtes"

ecozone_list <- c(4,5,6,7,8,9,10,11,12,13,14,15)
shp <- st_read("C:/Users/marc.edwards/Documents/gisdata/national_ecological_framework/Ecoregions/ecoregions_albers_dslv.shp") %>%
  filter(ECOZONE %in% ecozone_list) %>%# filter to the ecozone we ran prioritizr on
  left_join(ecozones, by = "ECOZONE") %>%
  select(ECOREGION,
         REGION_NAM,
         REGION_NOM,
         ECOZONE,
         ZONE_NAME,
         ZONE_NOM)

st_write(shp, "ERAP_ecoregions.shp")