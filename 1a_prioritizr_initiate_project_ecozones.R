# Data prep for Canada WTW run
# Adapted from wtw-data-prep scripts and using WTw v0.9

# The Canada WTW run is done ecozone by ecozone, then each ecozone result is
# merged into a final Canada-wide map.
# I tested this approach vs. a full national run and the results are very similar.
# The ecozone approach ensures wide ranging species are represented in the solution
# in evert ecozone in which they occur. This cleans up the solution and reduces
# striping patterns in the output. It also makes it easy to run on a laptop instead
# of needing to run it on the Carleton server.

#===============================================================================

library(sf)

# 01 Set parameters ------------------------------------------------------------

# Set input file
ecozones <- st_read("../../../gisdata/national_ecological_framework/Ecozones/ecozones.shp")

# create project folder
ecozone_folder <- "../data_prep/ecozones"
dir.create(ecozone_folder, recursive = TRUE)

# list ecozones to process
ecozone_list <- c(4,5,6,7,8,9,10,11,12,13,14,15)


# 02 Processing ----------------------------------------------------------------
for(ecozone in ecozone_list){
  
  # create folder
  project_folder <- paste0(ecozone_folder, "/", ecozone)
  dir.create(project_folder, recursive = TRUE)
  
  # extract AOI
  aoi_shp <- ecozones[ecozones$ECOZONE == ecozone,]
  
  # create folder structure
  dir.create(file.path(project_folder, "PU"), recursive = TRUE)
  dir.create(file.path(project_folder, "Tiffs"), recursive = TRUE)
  dir.create(file.path(project_folder, "output"), recursive = TRUE)
  
  # Copy AOI into PU folder
  st_write(aoi_shp, file.path(project_folder, "PU/AOI.shp"), append = FALSE)
}
