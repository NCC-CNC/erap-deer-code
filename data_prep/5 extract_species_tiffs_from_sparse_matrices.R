# Convert .rds sparse matrices into tifs.
#
# Filters to a specific set of species groups (short_name) -- not every
# species theme in WTW_NAT_PREP_METADATA.csv gets extracted, deliberately.
# The kept set (IUCN_AMPH/BIRD/MAMM/REPT, NCC_SAR_AOH, NCC_SDM) excludes 5
# themes (ECCC_CH, ECCC_SAR, NSC_END, NSC_SAR, NSC_SPP), and is also used
# to build a filtered, project-specific copy of the metadata table in
# "6 filter_species_metadata.R".
#
# Output goes to the external project folder
# (C:/Users/marc.edwards/Documents/PROJECTS/ERAPs_v2/data_prep/tiffs), not
# back into NAT_DATA_20260708

library(prioritizr)
source("C:/Users/marc.edwards/Documents/Github/wtw-data-prep2/R/utils_rij.R")

natdata_dir <- "C:/Data/PRZ/NAT_DATA/NAT_DATA_20260708"
output_dir  <- "C:/Users/marc.edwards/Documents/PROJECTS/ERAPs_v2/data_prep"

# Read-in wtw prep metadata, filter for only active data
wtw_prep_meta <- read.csv(
  file.path(natdata_dir, "WTW_NAT_PREP_METADATA.csv")) |> 
  dplyr::filter(active == TRUE, short_name %in% c("IUCN_AMPH", "IUCN_BIRD_S1", "IUCN_BIRD_S2", "IUCN_BIRD_S3", "IUCN_MAMM", "IUCN_REPT", "NCC_SAR_AOH", "NCC_SDM"))

# NCC planning units
grid_template_path <- file.path(natdata_dir, "_1km/idx.tif")
ncc_1km <- terra::rast(grid_template_path)
ncc_1km_idx <- terra::init(ncc_1km, fun="cell") # 267,790,000 pu
ncc_1km_idx_NA <- terra::init(ncc_1km_idx, fun=NA)

pu_rij <- prioritizr::rij_matrix(ncc_1km, c(ncc_1km, ncc_1km_idx))
rownames(pu_rij) <- c("AOI", "Idx")

pu_1km_ext <- terra::ext(ncc_1km)

for (i in seq_len(nrow(wtw_prep_meta))) {
    row <- wtw_prep_meta[i, ]
    data_path <- file.path(natdata_dir, row$path, row$file_name)
    
    # check if data is a TIF
    if (tolower(tools::file_ext(data_path)) %in% c("tif", "tiff")) {
      r <- terra::rast(data_path)
      rij_data <- prioritizr::rij_matrix(ncc_1km, r)
      row_name <- tools::file_path_sans_ext(row$file_name)
      rownames(rij_data) <- c(row_name)
    } else {
      rij_data <- readRDS(file.path(data_path))
    }
    
    # intersect data_rij with pu_rij
    rij_data_clipped <- rij_clip(rij_data, pu_rij)
    
    # create output folder
    dir.create(file.path(output_dir, "tiffs", row$path), recursive = TRUE, showWarnings = FALSE)

    # export rij to raster tif
    rij_to_raster(
      ncc_1km_idx = ncc_1km_idx_NA,
      rij_data_clipped = rij_data_clipped,
      pu_1km_ext = pu_1km_ext,
      output_folder = file.path(output_dir, "tiffs", row$path),
      prefix = row$prefix,
      datatype = row$datatype,
      verbose = TRUE
    )
    
    # delete objects to save RAM
    rm(rij_data, rij_data_clipped)

}
