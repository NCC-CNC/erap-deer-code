# Gather all habitat sums into one table

rm(list = ls(all.names = TRUE))
gc()

library(readr)
library(dplyr)
library(sf)

# Load layers

# ecoregions: to make tibble
ecozone_list <- c(4,5,6,7,8,9,10,11,12,13,14,15)
ecoregions <- st_read("C:/Users/marc.edwards/Documents/gisdata/national_ecological_framework/Ecoregions/ecoregions_albers_dslv.shp") %>%
  filter(ECOZONE %in% ecozone_list) %>% # filter to the ecozone we ran prioritizr on
  select(ECOREGION, land_km2) %>%
  st_drop_geometry()

gdb <- "processing/habitat/habitat.gdb/"

# Forest
forest_df <- read_csv("processing/habitat/forests_sums.csv") %>%
  select(ECOREGION, forest_km2, forest_protected_km2, forest_wtw_km2)

# Grassland
grassland <- st_read(gdb, "grassland_by_ecoregion_table") %>% select(ECOREGION, grassland_km2) %>% as_tibble()
grassland_pas <- st_read(gdb, "grassland_by_ecoregion_pa_table") %>% select(ECOREGION, grassland_km2_pa) %>% as_tibble() %>% rename("grassland_protected_km2" = "grassland_km2_pa")
grassland_wtw <- st_read(gdb, "grassland_by_ecoregion_wtw_table") %>% select(ECOREGION, grassland_km2_wtw) %>% as_tibble() %>% rename("grassland_wtw_km2" = "grassland_km2_wtw")

# Wetland
wetland <- st_read(gdb, "wetland_by_ecoregion_table") %>% select(ECOREGION, wetland_km2) %>% as_tibble()
wetland_pas <- st_read(gdb, "wetland_by_ecoregion_pa_table") %>% select(ECOREGION, wetland_km2_pa) %>% as_tibble() %>% rename("wetland_protected_km2" = "wetland_km2_pa")
wetland_wtw <- st_read(gdb, "wetland_by_ecoregion_wtw_table") %>% select(ECOREGION, wetland_km2_wtw) %>% as_tibble() %>% rename("wetland_wtw_km2" = "wetland_km2_wtw")

# Lakes
lakes <- st_read(gdb, "lakes_by_ecoregion_table") %>% select(ECOREGION, lakes_km2) %>% as_tibble()
lakes_pas <- st_read(gdb, "lakes_by_ecoregion_pa_table") %>% select(ECOREGION, lakes_km2_pa) %>% as_tibble() %>% rename("lakes_protected_km2" = "lakes_km2_pa")
lakes_wtw <- st_read(gdb, "lakes_by_ecoregion_wtw_table") %>% select(ECOREGION, lakes_km2_wtw) %>% as_tibble() %>% rename("lakes_wtw_km2" = "lakes_km2_wtw")

# Rivers 1M
rivers_1m <- st_read(gdb, "rivers_by_ecoregion_table") %>% select(ECOREGION, rivers_km) %>% as_tibble() %>% rename("rivers_1M_km" = "rivers_km")
rivers_1m_pas <- st_read(gdb, "rivers_by_ecoregion_pa_table") %>% select(ECOREGION, rivers_km_pa) %>% as_tibble() %>% rename("rivers_1M_protected_km" = "rivers_km_pa")
rivers_1m_wtw <- st_read(gdb, "rivers_by_ecoregion_wtw_table") %>% select(ECOREGION, rivers_km_wtw) %>% as_tibble() %>% rename("rivers_1M_wtw_km" = "rivers_km_wtw")

# Rivers 50k
rivers <- st_read(gdb, "rivers_50k_by_ecoregion_table") %>% select(ECOREGION, rivers_50k_km) %>% as_tibble() %>% rename("rivers_km" = "rivers_50k_km")
rivers_pas <- st_read(gdb, "rivers_50k_by_ecoregion_pa_table") %>% select(ECOREGION, rivers_50k_km_pa) %>% as_tibble() %>% rename("rivers_protected_km" = "rivers_50k_km_pa")
rivers_wtw <- st_read(gdb, "rivers_50k_by_ecoregion_wtw_table") %>% select(ECOREGION, rivers_50k_km_wtw) %>% as_tibble() %>% rename("rivers_wtw_km" = "rivers_50k_km_wtw")

# Shoreline
shoreline <- st_read(gdb, "shoreline_by_ecoregion_table") %>% select(ECOREGION, shoreline_km) %>% as_tibble()
shoreline_pas <- st_read(gdb, "shoreline_by_ecoregion_pa_table") %>% select(ECOREGION, shoreline_km_pa) %>% as_tibble() %>% rename("shoreline_protected_km" = "shoreline_km_pa")
shoreline_wtw <- st_read(gdb, "shoreline_by_ecoregion_wtw_table") %>% select(ECOREGION, shoreline_km_wtw) %>% as_tibble() %>% rename("shoreline_wtw_km" = "shoreline_km_wtw")


# Join tables
habitat_tib <- 
  left_join(ecoregions, forest_df, by = 'ECOREGION') %>%
  mutate(pcnt_ecoregion_forest_cover = forest_km2 / land_km2 * 100,
         pcnt_forest_protected = forest_protected_km2 / forest_km2 * 100,
         pcnt_forest_wtw = forest_wtw_km2 / forest_km2 * 100) %>%
  left_join(., grassland, by = 'ECOREGION') %>%
  left_join(., grassland_pas, by = 'ECOREGION') %>%
  left_join(., grassland_wtw, by = 'ECOREGION') %>%
  mutate(pcnt_ecoregion_grassland_cover = grassland_km2 / land_km2 * 100,
         pcnt_grassland_protected = grassland_protected_km2 / grassland_km2 * 100,
         pcnt_grassland_wtw = grassland_wtw_km2 / grassland_km2 * 100) %>%
  left_join(., wetland, by = 'ECOREGION') %>%
  left_join(., wetland_pas, by = 'ECOREGION') %>%
  left_join(., wetland_wtw, by = 'ECOREGION') %>%
  mutate(pcnt_ecoregion_wetland_cover = wetland_km2 / land_km2 * 100,
         pcnt_wetland_protected = wetland_protected_km2 / wetland_km2 * 100,
         pcnt_wetland_wtw = wetland_wtw_km2 / wetland_km2 * 100) %>%
  left_join(., lakes, by = 'ECOREGION') %>%
  left_join(., lakes_pas, by = 'ECOREGION') %>%
  left_join(., lakes_wtw, by = 'ECOREGION') %>%
  mutate(pcnt_ecoregion_lakes_cover = lakes_km2 / land_km2 * 100,
         pcnt_lakes_protected = lakes_protected_km2 / lakes_km2 * 100,
         pcnt_lakes_wtw = lakes_wtw_km2 / lakes_km2 * 100) %>%
  left_join(., rivers_1m, by = 'ECOREGION') %>%
  left_join(., rivers_1m_pas, by = 'ECOREGION') %>%
  left_join(., rivers_1m_wtw, by = 'ECOREGION') %>%
  mutate(pcnt_rivers_1M_protected = rivers_1M_protected_km / rivers_1M_km * 100,
         pcnt_rivers_1M_wtw = rivers_1M_wtw_km / rivers_1M_km * 100) %>%
  left_join(., rivers, by = 'ECOREGION') %>%
  left_join(., rivers_pas, by = 'ECOREGION') %>%
  left_join(., rivers_wtw, by = 'ECOREGION') %>%
  mutate(pcnt_rivers_protected = rivers_protected_km / rivers_km * 100,
         pcnt_rivers_wtw = rivers_wtw_km / rivers_km * 100) %>%
  left_join(., shoreline, by = 'ECOREGION') %>%
  left_join(., shoreline_pas, by = 'ECOREGION') %>%
  left_join(., shoreline_wtw, by = 'ECOREGION') %>%
  mutate(pcnt_shoreline_protected = shoreline_protected_km / shoreline_km * 100,
         pcnt_shoreline_wtw = shoreline_wtw_km / shoreline_km * 100) %>%
  round(2)
habitat_tib[is.na(habitat_tib)] <- 0
habitat_tib$land_km2 <- NULL # remove land km2 column

write_csv(habitat_tib, "processing/habitat/final_habitat_table.csv")