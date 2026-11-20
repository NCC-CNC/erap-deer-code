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
# Terrestrial-clipped, Canada Albers-projected ecozone layer built by
# "1 prep_ecoregions.py" (ecozones_ctef_v2_2_terrestrial) -- already in the
# right CRS and already clipped to the terrestrial land base, so ecozone
# extractions below don't pick up non-terrestrial area.
ecozones <- st_read(
  "C:/Users/marc.edwards/Documents/PROJECTS/ERAPs_v2/data_prep/ecoregions.gdb",
  "ecozones_ctef_v2_2_terrestrial"
)

# create project folder
ecozone_folder <- "C:/Users/marc.edwards/Documents/PROJECTS/ERAPs_v2/data_prep/prioritizr/ecozones"
dir.create(ecozone_folder, recursive = TRUE)

# list ecozones to process
ecozone_list <- c(4,5,6,7,8,9,10,11,12,13,14,15)


# 02 Processing ----------------------------------------------------------------
for(ecozone in ecozone_list){
  
  # create folder
  project_folder <- paste0(ecozone_folder, "/", ecozone)
  dir.create(project_folder, recursive = TRUE)
  
  # extract AOI
  aoi <- ecozones[ecozones$ECOZONE_ID == ecozone,]
  
  # create folder structure
  dir.create(file.path(project_folder, "aoi"), recursive = TRUE)
  dir.create(file.path(project_folder, "tifs"), recursive = TRUE)
  dir.create(file.path(project_folder, "output"), recursive = TRUE)
  
  # Copy AOI into PU folder
  st_write(aoi, dsn = file.path(project_folder, "aoi/AOI.gdb"), layer = "AOI",
           driver = "OpenFileGDB", append = FALSE)
}
