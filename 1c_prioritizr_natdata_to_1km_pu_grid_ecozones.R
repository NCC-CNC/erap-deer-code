# Data prep for Canada WTW run
# Adapted from wtw-data-prep scripts and using WTw v0.9

#===============================================================================

# 1.0 Load packages ------------------------------------------------------------

library(sf)
library(terra)
library(dplyr)
library(prioritizr)
library(stringr)
library(gdalUtilities)
library(Matrix)
source("scripts/functions/fct_matrix_intersect.R")
source("scripts/functions/fct_matrix_to_raster.R")
terra::gdalCache(size = 16000) # set cache to 8gb

# 01 Set parameters ------------------------------------------------------------

# Set input file
ecozones <- st_read("../../../gisdata/national_ecological_framework/Ecozones/ecozones.shp")

## Set output folder and PU ----
input_data_path <- "C:/Data/PRZ/WTW_DATA/WTW_NAT_DATA_20240522"

# Set path for updated Includes layer
include_path <- "../../../gisdata/protected_areas_2024/Dans_updated_WTW_Includes_July_2024/Existing_Conservation.tif"

# set project folder
ecozone_folder <- "../prioritizr/ecozones"

# list ecozones to process
ecozone_list <- c(4,5,6,7,8,9,10,11,12,13,14,15)

for(ecozone in ecozone_list){
  
  print(paste0("processing ecozone...", ecozone))
  
  # 2.0 Set up -------------------------------------------------------------------
  
  pu_path <- file.path(ecozone_folder, ecozone, "PU/PU.tif")
  tiffs_folder <- file.path(ecozone_folder, ecozone, "Tiffs")
  
  # 3.0 prep folders and PUs -----------------------------------------------------
  
  ## Read-in PU .tiff ----
  pu_1km <- rast(pu_path)
  pu_1km_ext <- ext(pu_1km) # get extent
  
  ## Read-in national 1km grid (all of Canada) ----
  ncc_1km <- rast(file.path(input_data_path, "nat_pu/NCC_1KM_PU.tif"))
  ncc_1km_idx <- terra::init(ncc_1km, fun="cell") # 267,790,000 pu
  ncc_1km_idx_NA <- terra::init(ncc_1km_idx, fun=NA)
  
  ## Align pu to same extent and same number of rows/cols as national grid ----
  ### get spatial properties of ncc grid
  proj4_string <- terra::crs(ncc_1km,  proj=TRUE) # projection string
  bbox <- terra::ext(ncc_1km) # bounding box
  ### variables for gdalwarp
  te <- c(bbox[1], bbox[3], bbox[2], bbox[4]) # xmin, ymin, xmax, ymax
  ts <- c(terra::ncol(ncc_1km), terra::nrow(ncc_1km)) # ncc grid: columns/rows
  ### gdalUtilities::gdalwarp does not require a local GDAL installation ----
  gdalUtilities::gdalwarp(srcfile = pu_path,
                          dstfile = paste0(tools::file_path_sans_ext(pu_path), "_align.tif"),
                          te = te,
                          t_srs = proj4_string,
                          ts = ts,
                          overwrite = TRUE)
  
  ## Get aligned planning units ---- 
  aoi_pu <- rast(paste0(tools::file_path_sans_ext(pu_path), "_align.tif"))
  # Create pu_rij matrix: 11,010,932 planing units activated 
  pu_rij <- prioritizr::rij_matrix(ncc_1km, c(aoi_pu, ncc_1km_idx))
  rownames(pu_rij) <- c("AOI", "Idx")
  rm(ncc_1km_idx) %>% gc(verbose = FALSE) # clear some RAM
  
  
  # 4.0 national data to PU -----------------------------------------------------
  
  ## ECCC Critical Habitat (theme) ----
  natdata_rij <- readRDS(file.path(input_data_path, "biodiversity/RIJ_ECCC_CH.rds"))
  matrix_overlap <- matrix_intersect(natdata_rij, pu_rij)
  rm(natdata_rij) %>% gc(verbose = FALSE) # clear some RAM
  matrix_to_raster(ncc_1km_idx_NA, matrix_overlap, pu_1km_ext, 
                   tiffs_folder, "", "INT2U") # no prefix needed
  
  ## ECCC Species at risk (theme) ----
  natdata_rij <- readRDS(file.path(input_data_path, "biodiversity/RIJ_ECCC_SAR.rds"))
  matrix_overlap <- matrix_intersect(natdata_rij, pu_rij)
  rm(natdata_rij) %>% gc(verbose = FALSE) # clear some RAM
  matrix_to_raster(ncc_1km_idx_NA, matrix_overlap, pu_1km_ext, 
                   tiffs_folder, "", "INT2U") # no prefix needed
  
  ## IUCN Amphibians (theme) ----
  natdata_rij <- readRDS(file.path(input_data_path, "biodiversity/RIJ_IUCN_AMPH.rds"))
  matrix_overlap <- matrix_intersect(natdata_rij, pu_rij)
  rm(natdata_rij) %>% gc(verbose = FALSE) # clear some RAM
  matrix_to_raster(ncc_1km_idx_NA, matrix_overlap, pu_1km_ext,
                   tiffs_folder, "T_NAT_IUCN_AMPH_", "INT1U")
  
  ## IUCN Birds (theme) ----
  natdata_rij <- readRDS(file.path(input_data_path, "biodiversity/RIJ_IUCN_BIRD.rds"))
  matrix_overlap <- matrix_intersect(natdata_rij, pu_rij)
  rm(natdata_rij) %>% gc(verbose = FALSE) # clear some RAM
  matrix_to_raster(ncc_1km_idx_NA, matrix_overlap, pu_1km_ext,
                   tiffs_folder, "T_NAT_IUCN_BIRD_", "INT1U")
  
  ## IUCN Mammals (theme) ----
  natdata_rij <- readRDS(file.path(input_data_path, "biodiversity/RIJ_IUCN_MAMM.rds"))
  matrix_overlap <- matrix_intersect(natdata_rij, pu_rij)
  rm(natdata_rij) %>% gc(verbose = FALSE) # clear some RAM
  matrix_to_raster(ncc_1km_idx_NA, matrix_overlap, pu_1km_ext,
                   tiffs_folder, "T_NAT_IUCN_MAMM_", "INT1U")
  
  ## IUCN Reptiles (theme) ----
  natdata_rij <- readRDS(file.path(input_data_path, "biodiversity/RIJ_IUCN_REPT.rds"))
  matrix_overlap <- matrix_intersect(natdata_rij, pu_rij)
  rm(natdata_rij) %>% gc(verbose = FALSE) # clear some RAM
  matrix_to_raster(ncc_1km_idx_NA, matrix_overlap, pu_1km_ext,
                   tiffs_folder, "T_NAT_IUCN_REPT_", "INT1U")
  
  ## Nature Serve Canada Endemics (theme) ----
  natdata_rij <- readRDS(file.path(input_data_path, "biodiversity/RIJ_NSC_END.rds"))
  matrix_overlap <- matrix_intersect(natdata_rij, pu_rij)
  rm(natdata_rij) %>% gc(verbose = FALSE) # clear some RAM
  matrix_to_raster(ncc_1km_idx_NA, matrix_overlap, pu_1km_ext,
                   tiffs_folder, "T_NAT_NSC_END_", "INT1U")
  
  ## Nature Serve Canada Species at risk (theme) ----
  natdata_rij <- readRDS(file.path(input_data_path, "biodiversity/RIJ_NSC_SAR.rds"))
  matrix_overlap <- matrix_intersect(natdata_rij, pu_rij) 
  rm(natdata_rij) %>% gc(verbose = FALSE) # clear some RAM
  matrix_to_raster(ncc_1km_idx_NA, matrix_overlap, pu_1km_ext,
                   tiffs_folder, "T_NAT_NSC_SAR_", "INT1U")
  
  ## Nature Serve Canada Common Species (theme) ----
  natdata_rij <- readRDS(file.path(input_data_path, "biodiversity/RIJ_NSC_SPP.rds"))
  matrix_overlap <- matrix_intersect(natdata_rij, pu_rij)
  rm(natdata_rij) %>% gc(verbose = FALSE) # clear some RAM
  matrix_to_raster(ncc_1km_idx_NA, matrix_overlap, pu_1km_ext,
                   tiffs_folder, "T_NAT_NSC_SPP_", "INT1U")
  
  ## Protected (include) ----
  ### Canadian protected and conserved areas database - Terrestrial Biomes (CPCAD) +
  ### NCC Fee simple (FS) + NCC conservation agreements (CA) 
  natdata_r <- rast(include_path)
  natdata_rij <- prioritizr::rij_matrix(ncc_1km, natdata_r)
  rownames(natdata_rij) <- c("Protected")
  matrix_overlap  <- matrix_intersect(natdata_rij, pu_rij) 
  rm(natdata_rij) # clear some RAM
  matrix_to_raster(ncc_1km_idx_NA, matrix_overlap, pu_1km_ext,
                   tiffs_folder, "I_NAT_", "INT1U")
  
  ## Human footprint (weight) ----
  natdata_r <- rast(file.path(input_data_path, "threats/CDN_HF_cum_threat_20221031_NoData.tif"))
  natdata_rij <- prioritizr::rij_matrix(ncc_1km, natdata_r)
  rownames(natdata_rij) <- c("Human_footprint")
  matrix_overlap  <- matrix_intersect(natdata_rij, pu_rij) 
  rm(natdata_rij) # clear some RAM
  matrix_to_raster(ncc_1km_idx_NA, matrix_overlap, pu_1km_ext,
                   tiffs_folder, "W_NAT_", "FLT4S")
  
  ## Carbon weight ----
  natdata_r <- rast(file.path(input_data_path, "carbon/Carbon_Mitchell_2021_t.tif"))
  natdata_rij <- prioritizr::rij_matrix(ncc_1km, natdata_r)
  rownames(natdata_rij) <- c("Carbon_storage")
  matrix_overlap  <- matrix_intersect(natdata_rij, pu_rij) 
  rm(natdata_rij) # clear some RAM
  matrix_to_raster(ncc_1km_idx_NA, matrix_overlap, pu_1km_ext,
                   tiffs_folder, "W_NAT_", "FLT4S")
  
  
  ### Fix tiffs known to have bugs - see 5b_species_data_check.R for details
  if(file.exists(file.path(tiffs_folder, "T_NAT_ECCC_CH_END_COSEWIC_846.tif"))){
    print("Fixing...T_NAT_ECCC_CH_END_COSEWIC_846")
    file.rename(file.path(tiffs_folder, "T_NAT_ECCC_CH_END_COSEWIC_846.tif"), file.path(tiffs_folder, "T_NAT_ECCC_CH_END_COSEWIC_846_delete.tif"))
    tif <- rast(file.path(tiffs_folder, "T_NAT_ECCC_CH_END_COSEWIC_846_delete.tif"))
    tif[tif > 100] <- 100
    writeRaster(tif, file.path(tiffs_folder, "T_NAT_ECCC_CH_END_COSEWIC_846.tif"), overwrite=TRUE, datatype = "INT2U")
    file.remove(file.path(tiffs_folder, "T_NAT_ECCC_CH_END_COSEWIC_846_delete.tif"))
  }
  
  if(file.exists(file.path(tiffs_folder, "T_NAT_ECCC_CH_THR_COSEWIC_951.tif"))){
    print("Fixing...T_NAT_ECCC_CH_THR_COSEWIC_951")
    file.rename(file.path(tiffs_folder, "T_NAT_ECCC_CH_THR_COSEWIC_951.tif"), file.path(tiffs_folder, "T_NAT_ECCC_CH_THR_COSEWIC_951_delete.tif"))
    tif <- rast(file.path(tiffs_folder, "T_NAT_ECCC_CH_THR_COSEWIC_951_delete.tif"))
    tif[tif > 0] <- 1
    writeRaster(tif, file.path(tiffs_folder, "T_NAT_ECCC_CH_THR_COSEWIC_951.tif"), overwrite=TRUE, datatype = "INT2U")
    file.remove(file.path(tiffs_folder, "T_NAT_ECCC_CH_THR_COSEWIC_951_delete.tif"))
  }
  
  if(file.exists(file.path(tiffs_folder, "T_NAT_ECCC_SAR_NOS_COSEWIC_882.tif"))){
    print("Fixing...T_NAT_ECCC_SAR_NOS_COSEWIC_882")
    file.rename(file.path(tiffs_folder, "T_NAT_ECCC_SAR_NOS_COSEWIC_882.tif"), file.path(tiffs_folder, "T_NAT_ECCC_SAR_NOS_COSEWIC_882_delete.tif"))
    tif <- rast(file.path(tiffs_folder, "T_NAT_ECCC_SAR_NOS_COSEWIC_882_delete.tif"))
    tif[tif > 100] <- 50
    writeRaster(tif, file.path(tiffs_folder, "T_NAT_ECCC_SAR_NOS_COSEWIC_882.tif"), overwrite=TRUE, datatype = "INT2U")
    file.remove(file.path(tiffs_folder, "T_NAT_ECCC_SAR_NOS_COSEWIC_882_delete.tif"))
  }
}



# 5.0 Clear R environment ------------------------------------------------------ 

# Remove objects
rm(list=ls())
gc()
