source("R/fct_read_feature.R")
source("R/fct_intersect_raster_value.R")

# Ports 4_protected_intact_modified.R, extended per erap-deer-code#29 (full-
# landscape intact/modified percentages, not just the unprotected remainder
# -- see the plan's #29 addendum for the decided workflow/denominator this
# follows exactly). One reference polygon per landscape throughout -- the
# land-clipped/terrestrial version, not the full extent (see the plan's
# "collapsing the ecoregion/ecoregion_inland duplication" addendum).
# Coastline is the only metric anywhere in this pipeline that uses the
# marine polygon instead, and it isn't computed here (see 04_habitat.R).
protected_intactness <- function(cfg, landscapes) {
  print("03 protected/intactness...")

  terrestrial_sf <- landscapes$terrestrial_sf
  name_col       <- cfg$landscape$name_col
  landscape_path <- cfg$landscape$landscape_path
  protected_path <- cfg$protected_data$protected_vector_path

  out <- sf::st_drop_geometry(terrestrial_sf)[, "landscape_id", drop = FALSE]
  out$landscape_km2 <- as.numeric(sf::st_area(terrestrial_sf)) / 1e6

  print("  protected area...")
  protected_ha <- intersect_vector_values(protected_path, landscape_path, name_col)
  out$protected_km2  <- lookup_or_zero(protected_ha, out$landscape_id) / 100
  out$protected_pcnt <- round(out$protected_km2 / out$landscape_km2 * 100, 2)

  # Protected area within each landscape, as geometry (not just a summed
  # area) -- needed to then sum pressure_intact/pressure_modified raster
  # area within it per landscape, which intersect_vector_values() can't do
  # (vector-vector only). One intersect+dissolve for every landscape at
  # once, read back into R, then exact_extract'd against both rasters in
  # two bulk calls -- not one arcpy call and one exact_extract per landscape.
  print("  protected area geometry (for intact/modified overlap)...")
  protected_in_landscape_path <- intersect_vector_geoms(landscape_path, protected_path, name_col)
  protected_in_landscape_sf   <- read_feature(protected_in_landscape_path)
  delete_fc(protected_in_landscape_path)
  protected_in_landscape_sf$landscape_id <- protected_in_landscape_sf[[name_col]]

  print("  intact/modified, full landscape...")
  intact_ha   <- intersect_raster_values(cfg$pressures_raster$pressure_intact,   terrestrial_sf, "landscape_id")
  modified_ha <- intersect_raster_values(cfg$pressures_raster$pressure_modified, terrestrial_sf, "landscape_id")
  out$intact_km2   <- lookup_or_zero(intact_ha,   out$landscape_id) / 100
  out$modified_km2 <- lookup_or_zero(modified_ha, out$landscape_id) / 100

  print("  intact/modified, protected portion...")
  protected_intact_ha   <- intersect_raster_values(cfg$pressures_raster$pressure_intact,   protected_in_landscape_sf, "landscape_id")
  protected_modified_ha <- intersect_raster_values(cfg$pressures_raster$pressure_modified, protected_in_landscape_sf, "landscape_id")
  out$protected_intact_km2   <- lookup_or_zero(protected_intact_ha,   out$landscape_id) / 100
  out$protected_modified_km2 <- lookup_or_zero(protected_modified_ha, out$landscape_id) / 100

  # Denominator is intact_km2 + modified_km2, not landscape_km2 -- the
  # pressure raster pair won't always fully cover the landscape polygon
  # exactly (alignment/edge gaps), so dividing by landscape_km2 directly
  # wouldn't guarantee intact_pcnt + modified_pcnt == 100. Dividing by their
  # own sum instead is still representative and guarantees the two
  # percentages sum to 100 exactly, per erap-deer-code#29.
  denom <- out$intact_km2 + out$modified_km2
  out$intact_pcnt             <- round(out$intact_km2             / denom * 100, 2)
  out$modified_pcnt           <- round(out$modified_km2           / denom * 100, 2)
  out$protected_intact_pcnt   <- round(out$protected_intact_km2   / denom * 100, 2)
  out$protected_modified_pcnt <- round(out$protected_modified_km2 / denom * 100, 2)

  out
}
