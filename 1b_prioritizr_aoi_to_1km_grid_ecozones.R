# Data prep for Canada WTW run
# Adapted from wtw-data-prep scripts and using WTw v0.9

#===============================================================================

# 1.0 Load packages ------------------------------------------------------------

library(terra)
library(sf)
library(dplyr)

# 01 Set parameters ------------------------------------------------------------

# Set input file
ecozones <- st_read("../../../gisdata/national_ecological_framework/Ecozones/ecozones.shp")

CONSTANT_1KM_IDX_PATH <- "C:/Data/PRZ/WTW_DATA/WTW_NAT_DATA_20240110/nat_pu/Constant_1KM_IDX.tif"
CONSTANT_1KM_IDX <- rast(CONSTANT_1KM_IDX_PATH ) 

# set project folder
ecozone_folder <- "../data_prep/ecozones"

# list ecozones to process
ecozone_list <- c(4,5,6,7,8,9,10,11,12,13,14,15)

for(ecozone in ecozone_list){
  
  # 2.0 Set up -------------------------------------------------------------------
  
  # Input boundary shapefile path
  SHP <- file.path(ecozone_folder, ecozone, "PU/AOI.shp")
  
  # Output folder path to save PU.shp, PU.tif and PU0.tif
  OUTPUT <- file.path(ecozone_folder, ecozone, "PU")
  
  
  # 3.0 Processing ---------------------------------------------------------------
  
  # Read-in boundary shapefile
  Boundary <- read_sf(SHP) %>% 
    st_transform(crs = st_crs(CONSTANT_1KM_IDX))
  
  # Rasterize boundary polygon: 4700 rows, 5700 cols, 26790000 cells
  pu_1km <- Boundary %>%
    mutate(BURN = 1) %>%
    #st_buffer(1000) %>% # don't buffer because we don't want overlap in solutions. This approach will assign each PU to an ecozone based on its centroid so every PU will appear in exactly one ecozone
    rasterize(CONSTANT_1KM_IDX, "BURN")
  
  # Raster 1km grid, cell values are NCC indexes, mask values to boundary
  r_pu <- mask((pu_1km * CONSTANT_1KM_IDX), vect(Boundary)) 
  
  # Vector 1km grid
  v_pu <- st_as_sf(as.polygons(r_pu)) %>%
    rename(NCCID = BURN) %>%
    mutate(PUID = row_number()) %>%
    write_sf(file.path(OUTPUT, "PU.shp"), overwrite = TRUE) 
  
  # Create raster template matching vector grid extent
  r_pu_template <- rast(vect(v_pu), res = 1000)
  
  # Rasterize vector grid, values are all 1
  r_pu <- rasterize(vect(v_pu), r_pu_template, 1) %>%
    writeRaster(file.path(OUTPUT, "PU.tif"), datatype = "INT1U", overwrite = TRUE)
  
  # Convert all cell values to 0
  r_pu[r_pu > 0] <- 0
  writeRaster(r_pu, file.path(OUTPUT, "PU0.tif"), datatype = "INT1U", overwrite = TRUE)
  

}

# Remove objects
rm(list=ls())
gc()