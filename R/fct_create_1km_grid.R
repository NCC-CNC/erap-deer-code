# Ported from https://github.com/NCC-CNC/wtw-data-prep2/blob/main/R/fct_create_1km_grid.R

# aoi to 1km grid
create_1km_grid <- function(aoi_sf, grid_template_path) {
  
  # Read-in template and derive a per-cell unique index on the fly.
  # The index values stored in the national _1km/idx.tif are not reliable for
  # this: it's stored as float32, which loses precision above 2^24 (~16.78M)
  # and silently collides ~45k distinct index values onto neighbouring cells
  # per ecozone. Since as.polygons() below merges cells that share a value,
  # those collisions both corrupt the PU grid (cells silently absorbed into
  # neighbours instead of getting their own PU) and produce a mix of POLYGON/
  # MULTIPOLYGON features that OpenFileGDB refuses to write ("GDAL Error 6:
  # Unsupported geometry type"). terra::init(fun = "cell") guarantees a true
  # unique value per cell and inherits the template's NA mask/grid geometry.
  idx <- terra::init(terra::rast(grid_template_path), fun = "cell")
  
  # Project to Canada_Albers_WGS_1984
  aoi <- sf::st_transform(aoi_sf, crs = sf::st_crs(idx)) 
  
  # Rasterize boundary polygon: 4700 rows, 5700 cols, 26790000 cells
  pu_1km <- aoi |>
    dplyr::mutate(BURN = 1) |> 
    #sf::st_buffer(1000) |> # don't buffer because we don't want overlap between ecozones
    terra::rasterize(idx, "BURN")
  
  # Raster 1km grid, cell values are NCC indexes, mask values to aoi
  r_pu <- terra::mask((pu_1km * idx), terra::vect(aoi)) 
  
  # Vector 1km grid
  v_pu <- sf::st_as_sf(terra::as.polygons(r_pu)) |>
    dplyr::rename(NCCID = BURN) |>
    dplyr::mutate(PUID = dplyr::row_number()) 
  
  # Create raster template matching vector grid extent
  r_pu_template <- terra::rast(
    terra::vect(v_pu), res = 1000
  )
  
  # Rasterize vector grid, values are all 1
  r_pu <- terra::rasterize(
    terra::vect(v_pu), r_pu_template, 1)
  
  return(list(aoi = aoi, vector_grid = v_pu, raster_grid = r_pu))
}