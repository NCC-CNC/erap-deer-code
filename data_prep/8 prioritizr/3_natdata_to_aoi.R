# Ported from https://github.com/NCC-CNC/wtw-data-prep2/blob/main/R/03_natdata.R
#
# Sourced directly from the wtw-data-prep2 repo rather than copied in here, so
# this stays in sync with upstream instead of drifting.
#
#  -----------------------------------------------------------------------------

# Source natdata() from its own repo root, so its internal
# source("R/fct_align_pu.R") / source("R/utils_rij.R") calls resolve against
# that repo instead of this one.
wtw_data_prep2_dir <- "C:/Users/marc.edwards/Documents/Github/wtw-data-prep2"
old_wd <- getwd()
setwd(wtw_data_prep2_dir)
source("R/03_natdata.R")
setwd(old_wd)

# Get national data dir
natdata_dir <- "C:/Data/PRZ/NAT_DATA/NAT_DATA_20260708"

# natdata()'s rij_to_raster() writes via terra::crop(..., filename = ...),
# which does not create missing output directories ("[crop] path does not
# exist"). Pre-create every "tifs/<path>" folder the metadata CSV references
# for each ecozone, rather than patching that into the sourced function.
# Which datasets get extracted to tifs is controlled entirely by the "active"
# column in WTW_NAT_PREP_METADATA.csv (set manually, not by this pipeline).
# Active theme_group_name values as of NAT_DATA_20260708:
#   IUCN AOH Amphibians
#   IUCN AOH Birds (Resident)
#   IUCN AOH Birds (Breeding)
#   IUCN AOH Birds (Non-Breeding)
#   IUCN AOH Mammals
#   IUCN AOH Reptiles
#   NCC SAR AOH
#   NCC SDM
# Plus two active rows with no theme_group_name (not species themes):
#   CPCAD (include/protected), HFI (weight/pressures)
all_paths <- read.csv(file.path(natdata_dir, "WTW_NAT_PREP_METADATA.csv")) |>
  dplyr::filter(active == TRUE) |>
  dplyr::pull(path) |>
  unique()

for (ecozone in ecozone_list) {

  print(ecozone)

  project_dir <- paste0(ecozone_folder, "/", ecozone)

  for (p in all_paths) {
    dir.create(file.path(project_dir, "tifs", p), recursive = TRUE, showWarnings = FALSE)
  }

  natdata(natdata_dir = natdata_dir, project_dir = project_dir)
}
