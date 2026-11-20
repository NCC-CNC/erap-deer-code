source("R/fct_intersect_raster_value.R") # for lookup_or_zero() -- no raster work in this step itself

# Ports 1e_prioritizr_ecoregion_intersects.R, per erap-deer-code#18's
# redefinition (see the plan's #18 addendum): wtw_percent is now % of the
# WHOLE landscape covered by the WTW opportunity layer, not % of the
# unprotected remainder, and wtw_area_km2 comes from intersecting
# wtw_erased_protected (the WTW solution with CPCAD+NCC protected areas
# already erased out -- data_prep/"9 prep_wtw_erase_protected.py") against
# each landscape as a vector-vector operation, not a raster exact_extract()
# against the un-erased solution + a separate grid-based "Includes" layer.
# includes_km2 no longer exists anywhere in this pipeline (retracted, see
# the plan's "includes_km2" addendum) -- this step never touches
# protected_grid_path.
wtw <- function(cfg, landscapes) {
  print("06 wtw...")

  terrestrial_sf <- landscapes$terrestrial_sf
  name_col       <- cfg$landscape$name_col
  landscape_km2  <- setNames(as.numeric(sf::st_area(terrestrial_sf)) / 1e6, terrestrial_sf$landscape_id)

  out <- sf::st_drop_geometry(terrestrial_sf)[, "landscape_id", drop = FALSE]

  wtw_ha <- intersect_vector_values(cfg$protected_data$wtw_erased_protected, cfg$landscape$landscape_path, name_col)
  out$wtw_area_km2 <- lookup_or_zero(wtw_ha, out$landscape_id) / 100
  out$wtw_percent  <- round(out$wtw_area_km2 / landscape_km2[out$landscape_id] * 100, 2)

  out
}
