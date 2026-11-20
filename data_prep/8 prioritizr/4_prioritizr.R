# Run prioritizr

# PU: all 1km cells in AOI
# Costs: 1
# Goals: Rodrigues Canada-wide goals (proportions that will be applid as relative targets) pulled from _project meta data table
# Themes: Species data - IUCN AOH Amphibians
#                        IUCN AOH Birds (Resident)
#                        IUCN AOH Birds (Breeding)
#                        IUCN AOH Birds (Non-Breeding)
#                        IUCN AOH Mammals
#                        IUCN AOH Reptiles
#                        NCC SAR AOH
#                        NCC SDM
#                        Includes: NAT_DATA Includes dataset (CPCAD_2025_NCCFSCA_20260428.tif)

rm(list = ls(all.names = TRUE))
gc()

# Load packages ------------------------------------------------------------

library(prioritizr)
library(dplyr)
library(terra)
library(tibble)
library(readr)
library(gurobi)
library(readxl)

terra::gdalCache(size = 24000) # set cache to 16gb
# Set parameters ------------------------------------------------------------

# set project folder
ecozone_folder <- "C:/Users/marc.edwards/Documents/PROJECTS/ERAPs_v2/data_prep/prioritizr/ecozones"

# open includes and convert na to zero
includes_rast <- rast("C:/Data/PRZ/NAT_DATA/NAT_DATA_20260708/includes/CPCAD_2025_NCCFSCA_20260428.tif")
includes_rast[is.na(includes_rast)] <- 0

# Open goals table as single table of species
input_data_path <- "C:/Users/marc.edwards/Documents/PROJECTS/ERAPs_v2/data_prep"
species_meta_path <- file.path(input_data_path, "WTW_NAT_SPECIES_METADATA_project.xlsx")

tibbles <- list()
for(sheet in excel_sheets(species_meta_path)){
  df <- read_excel(species_meta_path, sheet) %>%
    select(c("Source", "File", "Theme", "Sci_Name", "Common_Name", "Threat", "Total_Km2_terrestrial", "Protected_Km2_terrestrial", "Pct_Protected_terrestrial", "Goal_terrestrial"))
  tibbles[[sheet]] <- df
}
species_meta <- bind_rows(tibbles)

# list ecozones to process
ecozone_list <- c(4,5,6,7,8,9,10,11,12,13,14,15)

# Prep and run prioritizr for ecozones -------------------------------------

for(ecozone in ecozone_list){
  
  print(paste0("processing ecozone...", ecozone))
  
  # set paths
  tiffs <- file.path(ecozone_folder, ecozone, "tifs")
  output <- file.path(ecozone_folder, ecozone, "output")
  
  if(!dir.exists(output)){
    dir.create(output)
  }
  
  # open PUs
  pu <- rast(file.path(ecozone_folder, ecozone, "aoi/pu_1km.tif"))
  
  # 1. Get all theme rasters in a terra stack ------------------------------
  print("prep rasters...")
  include_list <- list.files(file.path(tiffs, "includes"), full.names = TRUE)
  #cost_list <- list.files(tiffs, pattern = "^W_NAT_Human_footrpint.*.tif$", full.names = TRUE)
  #cost_list <- list.files(tiffs, pattern = "^W_NAT_Carbon.*.tif$", full.names = TRUE)
  theme_list <- list.files(file.path(tiffs, "themes"), full.names = TRUE, recursive = TRUE)

  # Drop any theme raster with no matching species_meta row. natdata()
  # includes a species per-ecozone based on the rij values, but meta data
  # filters based on national tifs that have already rounded small values
  # to zero. rij_to_raster() rounds these to zero too so species that got dropped
  # from species_meta can get ecozone tifs with all zero values.
  theme_file_names <- tools::file_path_sans_ext(basename(theme_list))
  meta_file_names  <- tools::file_path_sans_ext(species_meta$File)
  missing <- setdiff(theme_file_names, meta_file_names)
  if (length(missing) > 0) {
    print(paste0(length(missing), " theme raster(s) with no species_meta match, dropping: ",
                 paste(missing, collapse = ", ")))
    theme_list <- theme_list[theme_file_names %in% meta_file_names]
  }

  theme_rasters <- rast(theme_list)
  include_rasters <- rast(include_list)
  #cost_rasters <- rast(cost_list)
  
  # set raster names to be file names so we can reference to metadata
  names(theme_rasters) <- tools::file_path_sans_ext(basename(sources(theme_rasters)))
  
  # 2. Convert to rij matrix
  print("rasters to rij...")
  theme_rij <- rij_matrix(pu, theme_rasters)
  include_rij <- rij_matrix(pu, include_rasters)
  #cost_rij <- rij_matrix(pu, cost_rasters)
  
  # 3. Get includes as logical vector
  locked_in <- as.logical(include_rij[1,] > 0)
  
  # 4. Get cost vector
  # for cost of 1
  cost <- rep(1, length(locked_in))
  
  # for cost using HF
  #hf_cost <- scales::rescale(cost_rij[1,], to = c(0.01, 1000))
  #carbon_cost <- scales::rescale(cost_rij[1,], to = c(1000, 0.01))
  
  # 5. Get features df
  features <- data.frame(
    id = seq_len(nrow(theme_rij)),
    name = row.names(theme_rij)
  )
  
  # 6. Get targets tibble
  # add raster names to meta
  targets <- tibble::tibble(
    feature = features$name,
    type = "relative",
    sense = ">=",
    target = 0
  )
  
  # fill in targets from meta table
  for(f in targets$feature){
    targets$target[targets$feature == f] <- species_meta$Goal_terrestrial[tools::file_path_sans_ext(species_meta$File) == f]
  }
  
  # 5. make problem
  print("call prioritizr...")
  p1 <- problem(
    x = cost,
    features = features,
    rij_matrix = theme_rij) %>%
    add_min_set_objective() %>%
    add_manual_targets(targets) %>%
    add_binary_decisions() %>%
    add_gurobi_solver(gap = 0) %>%
    add_locked_in_constraints(locked_in)
  
  # p2 <- problem(
  #   x = carbon_cost,
  #   features = features,
  #   rij_matrix = theme_rij) %>%
  #   add_min_set_objective() %>%
  #   add_manual_targets(targets) %>%
  #   add_binary_decisions() %>%
  #   add_gurobi_solver(gap = 0.01) %>%
  #   add_locked_in_constraints(locked_in)
  
  s1 <- solve(p1, force = TRUE)
  #s2 <- solve(p2, force = TRUE)
  
  # save output
  s1_rast <- pu
  values(s1_rast)[!is.na(values(s1_rast))] <- s1
  writeRaster(s1_rast, filename = file.path(output, "solution_1.tif"), overwrite=TRUE)
  write_csv(eval_n_summary(p1, s1), file.path(output, "eval_n_summary_s1.csv"), append = FALSE)
  write_csv(eval_target_coverage_summary(p1, s1), file.path(output, "eval_target_summary_s1.csv"), append = FALSE)
  
  # s2_rast <- pu
  # values(s2_rast)[!is.na(values(s2_rast))] <- s2
  # writeRaster(s2_rast, filename = file.path(output, "solution_carbon_cost.tif"), overwrite=TRUE)
  # write_csv(eval_n_summary(p2, s2), file.path(output, "eval_n_summary_carbon_cost.csv"), append = FALSE)
  # write_csv(eval_target_coverage_summary(p2, s2), file.path(output, "eval_target_summary_carbon_cost.csv"), append = FALSE)
  
  rm(list=c("p1", "p2", "s1", "s2", "theme_rasters", "targets", "features"))
}

#######
# Merge all ecozones together into national grid and save as single tif
#######

merge_list <- list()
for(ecozone in ecozone_list){
  merge_list[[as.character(ecozone)]] <- rast(file.path(ecozone_folder, ecozone, "output", "solution_1.tif"))
}
ecozone_solutions_1_merged <- terra::merge(sprc(merge_list))
writeRaster(ecozone_solutions_1_merged, file.path(ecozone_folder, "ecozones_solution_1_merged_temp.tif"))

## Align solution to same extent and same number of rows/cols as national grid
source("C:/Users/marc.edwards/Documents/Github/wtw-data-prep2/R/fct_align_pu.R")

natdata_dir <- "C:/Data/PRZ/NAT_DATA/NAT_DATA_20260708"
ncc_1km <- terra::rast(file.path(natdata_dir, "_1km/idx.tif"))

aligned <- align_pu(
  ncc_1km = ncc_1km,
  pu_1km_path = file.path(ecozone_folder, "ecozones_solution_1_merged_temp.tif")
)
writeRaster(aligned, file.path(ecozone_folder, "Canada_wtw_2026.tif"), overwrite = TRUE, datatype = "INT2U")

file.remove(file.path(ecozone_folder, "ecozones_solution_1_merged_temp.tif"))
file.remove(file.path(ecozone_folder, "ecozones_solution_1_merged_temp_align.tif"))

# Make a version that removes the includes
ecozones_merged <- rast(file.path(ecozone_folder, "Canada_wtw_2026.tif"))
ecozones_merged_noincludes <- ecozones_merged - includes_rast
writeRaster(ecozones_merged_noincludes, file.path(ecozone_folder, "Canada_wtw_2026_noIncludes.tif"), overwrite = TRUE, datatype = "INT2U")
