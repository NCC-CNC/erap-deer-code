# Ported from https://github.com/NCC-CNC/wtw-data-prep2/blob/main/R/02_aoi_to_1km_grid.R

# Pulled code out of a function to customize for this use case

# Create a 1km Planning Unit Grid from an AOI
#
# Generates a 1km raster and vector grid within a user-defined Area of 
# Interest (AOI), based on a raster template from national data. The grids are 
# written to the WTW project directory.
#
#  -----------------------------------------------------------------------------

# Source function
source("R/fct_create_1km_grid.R")

# Get 1km raster grid template
natdata_dir <- "C:/Data/PRZ/NAT_DATA/NAT_DATA_20260708"
grid_template_path <- file.path(natdata_dir, "_1km/idx.tif" )

for(ecozone in ecozone_list){
  
  print(ecozone)

  # Input boundary path
  project_dir <- paste0(ecozone_folder, "/", ecozone)

  # Read-in aoi shp
  aoi_sf <- sf::read_sf(file.path(project_dir, "aoi/AOI.gdb"), "AOI")

  # Create 1km grid
  pu_1km <- create_1km_grid(aoi_sf, grid_template_path)

  ## 1km vector grid - this write is making some buggy vectors in ArcGIS. Not actually used for anything downstream
  sf::write_sf(
    pu_1km$vector_grid, 
    dsn = file.path(project_dir, "aoi/AOI.gdb"), layer = "pu_1km",
           driver = "OpenFileGDB", append = FALSE
  )

  ## 1km raster grid
  terra::writeRaster(
    pu_1km$raster_grid, 
    file.path(project_dir, "aoi", "pu_1km.tif"),
    datatype = "INT1U",
    overwrite = TRUE
  )
}