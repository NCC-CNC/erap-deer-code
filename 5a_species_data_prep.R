# Prep data for species area calculations
# Convert Dans rij matrices into national tiffs that can be used to calculate 
# species ranges in each ecoregion

# Start timer
start_time <- Sys.time()


# prep -------------------------------------------------------------------

# Load packages and functions
library(terra)
library(dplyr)
source("../prioritizr/scripts/functions/fct_matrix_intersect.R")
source("../prioritizr/scripts/functions/fct_matrix_to_raster.R")

# Set source data paths
input_data_path <- "C:/Data/PRZ/WTW_DATA/WTW_NAT_DATA_20240522"
ncc_1km <- rast(file.path(input_data_path, "nat_pu/NCC_1KM_PU.tif"))
ncc_1km_idx <- terra::init(ncc_1km, fun="cell")
ncc_1km_idx_NA <- terra::init(ncc_1km_idx, fun=NA)

# Set output folder for Tiffs
tiffs_folder <- "processing/species/Tiffs"

# Load national grid as rij
pu_rij <- prioritizr::rij_matrix(ncc_1km, c(ncc_1km, ncc_1km_idx))
rownames(pu_rij) <- c("AOI", "Idx")
rm(ncc_1km_idx) %>% gc(verbose = FALSE) # clear some RAM


# national data to PU -----------------------------------------------------

## ECCC Critical Habitat (theme) ----
natdata_rij <- readRDS(file.path(input_data_path, "biodiversity/RIJ_ECCC_CH.rds"))
matrix_overlap <- matrix_intersect(natdata_rij, pu_rij)
rm(natdata_rij) %>% gc(verbose = FALSE) # clear some RAM
matrix_to_raster(ncc_1km_idx_NA, matrix_overlap, ncc_1km, 
                 tiffs_folder, "", "INT2U") # no prefix needed

## ECCC Species at risk (theme) ----
natdata_rij <- readRDS(file.path(input_data_path, "biodiversity/RIJ_ECCC_SAR.rds"))
matrix_overlap <- matrix_intersect(natdata_rij, pu_rij)
rm(natdata_rij) %>% gc(verbose = FALSE) # clear some RAM
matrix_to_raster(ncc_1km_idx_NA, matrix_overlap, ncc_1km, 
                 tiffs_folder, "", "INT2U") # no prefix needed

## IUCN Amphibians (theme) ----
natdata_rij <- readRDS(file.path(input_data_path, "biodiversity/RIJ_IUCN_AMPH.rds"))
matrix_overlap <- matrix_intersect(natdata_rij, pu_rij)
rm(natdata_rij) %>% gc(verbose = FALSE) # clear some RAM
matrix_to_raster(ncc_1km_idx_NA, matrix_overlap, ncc_1km,
                 tiffs_folder, "T_NAT_IUCN_AMPH_", "INT1U")

## IUCN Birds (theme) ----
natdata_rij <- readRDS(file.path(input_data_path, "biodiversity/RIJ_IUCN_BIRD.rds"))
matrix_overlap <- matrix_intersect(natdata_rij, pu_rij)
rm(natdata_rij) %>% gc(verbose = FALSE) # clear some RAM
matrix_to_raster(ncc_1km_idx_NA, matrix_overlap, ncc_1km,
                 tiffs_folder, "T_NAT_IUCN_BIRD_", "INT1U")

## IUCN Mammals (theme) ----
natdata_rij <- readRDS(file.path(input_data_path, "biodiversity/RIJ_IUCN_MAMM.rds"))
matrix_overlap <- matrix_intersect(natdata_rij, pu_rij)
rm(natdata_rij) %>% gc(verbose = FALSE) # clear some RAM
matrix_to_raster(ncc_1km_idx_NA, matrix_overlap, ncc_1km,
                 tiffs_folder, "T_NAT_IUCN_MAMM_", "INT1U")

## IUCN Reptiles (theme) ----
natdata_rij <- readRDS(file.path(input_data_path, "biodiversity/RIJ_IUCN_REPT.rds"))
matrix_overlap <- matrix_intersect(natdata_rij, pu_rij)
rm(natdata_rij) %>% gc(verbose = FALSE) # clear some RAM
matrix_to_raster(ncc_1km_idx_NA, matrix_overlap, ncc_1km,
                 tiffs_folder, "T_NAT_IUCN_REPT_", "INT1U")

## Nature Serve Canada Endemics (theme) ----
natdata_rij <- readRDS(file.path(input_data_path, "biodiversity/RIJ_NSC_END.rds"))
matrix_overlap <- matrix_intersect(natdata_rij, pu_rij)
rm(natdata_rij) %>% gc(verbose = FALSE) # clear some RAM
matrix_to_raster(ncc_1km_idx_NA, matrix_overlap, ncc_1km,
                 tiffs_folder, "T_NAT_NSC_END_", "INT1U")

## Nature Serve Canada Species at risk (theme) ----
natdata_rij <- readRDS(file.path(input_data_path, "biodiversity/RIJ_NSC_SAR.rds"))
matrix_overlap <- matrix_intersect(natdata_rij, pu_rij) 
rm(natdata_rij) %>% gc(verbose = FALSE) # clear some RAM
matrix_to_raster(ncc_1km_idx_NA, matrix_overlap, ncc_1km,
                 tiffs_folder, "T_NAT_NSC_SAR_", "INT1U")

## Nature Serve Canada Common Species (theme) ----
natdata_rij <- readRDS(file.path(input_data_path, "biodiversity/RIJ_NSC_SPP.rds"))
matrix_overlap <- matrix_intersect(natdata_rij, pu_rij)
rm(natdata_rij) %>% gc(verbose = FALSE) # clear some RAM
matrix_to_raster(ncc_1km_idx_NA, matrix_overlap, ncc_1km,
                 tiffs_folder, "T_NAT_NSC_SPP_", "INT1U")

# End timer
end_time <- Sys.time()
end_time - start_time