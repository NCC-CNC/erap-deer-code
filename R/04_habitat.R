source("R/fct_read_feature.R")
source("R/fct_intersect_raster_value.R")

# Ports 2b_habitat_sum_forests_raster.R / 2c_habitat_sum_habitat_vectors.py /
# 2d_habitat_gather_output.R -- per-habitat total/protected/WTW cover,
# looped over landscapes instead of ecoregions one at a time.
#
# Non-linear habitats (forest, grassland, wetland, lakes, peatlands) use the
# terrestrial landscape polygon and get a cover-%-of-landscape column plus
# their own protected/WTW overlap, both as a % of that habitat's own total
# (not of the landscape) -- confirmed against the legacy
# 2d_habitat_gather_output.R / conservation-profiles' fct_build_custom_erap_row.R.
# forest is the one raster-based habitat; the other four are vector
# polygons, computed via the shared bulk intersect helpers.
#
# Linear habitats (rivers, coastline) have no cover-%-of-landscape column
# (a length has no area denominator) -- just their own protected/WTW %.
# coastline is the one habitat that uses the MARINE landscape polygon for
# all three of its own figures (cover, protected, WTW), not the terrestrial
# one -- see the plan's "marine landscape layer" addendum. rivers stays on
# the terrestrial polygon like every other non-coastline metric.
#
# Both the protected-area and WTW inputs are the single erased layers
# (protected_vector_path, canada_wtw_2026) -- per erap-deer-code#18,
# the same Canada_wtw_2026 layer used everywhere else in this
# pipeline, not a separate un-erased WTW vector.
habitat <- function(cfg, landscapes) {
  print("04 habitat...")

  terrestrial_sf <- landscapes$terrestrial_sf
  name_col       <- cfg$landscape$name_col
  landscape_path        <- cfg$landscape$landscape_path
  landscape_path_marine <- cfg$landscape$landscape_path_marine
  protected_path <- cfg$protected_data$protected_vector_path
  wtw_path       <- cfg$protected_data$canada_wtw_2026

  out <- sf::st_drop_geometry(terrestrial_sf)[, "landscape_id", drop = FALSE]
  landscape_km2 <- setNames(as.numeric(sf::st_area(terrestrial_sf)) / 1e6, terrestrial_sf$landscape_id)

  # Non-linear habitats -- forest is raster, the rest are vector polygons ---

  # Protected-area / WTW geometry within each landscape, built once and
  # reused for forest's raster extraction below (grassland/wetland/lakes/
  # peatlands don't need this -- they're pure vector-vector, handled by
  # intersect_vector_values()'s own chained-boundary intersect directly).
  print("  protected/WTW geometry (for forest overlap)...")
  protected_in_landscape_path <- intersect_vector_geoms(landscape_path, protected_path, name_col)
  protected_in_landscape_sf   <- read_feature(protected_in_landscape_path)
  delete_fc(protected_in_landscape_path)
  protected_in_landscape_sf$landscape_id <- protected_in_landscape_sf[[name_col]]

  wtw_in_landscape_path <- intersect_vector_geoms(landscape_path, wtw_path, name_col)
  wtw_in_landscape_sf   <- read_feature(wtw_in_landscape_path)
  delete_fc(wtw_in_landscape_path)
  wtw_in_landscape_sf$landscape_id <- wtw_in_landscape_sf[[name_col]]

  # total_ha/protected_ha/wtw_ha are ha throughout (both intersect_raster_values()
  # and intersect_vector_values() return ha -- the latter via reticulate as
  # a python dict, converted to an R named *list*, not a vector; lookup_or_zero()
  # unlists it). Converted to km2 here, in one place, rather than at each
  # call site before the dict/list has been unlisted -- dividing a list by
  # 100 directly would error.
  add_nonlinear <- function(out, hab, total_ha, protected_ha, wtw_ha) {
    out[[paste0(hab, "_km2")]]           <- lookup_or_zero(total_ha,     out$landscape_id) / 100
    out[[paste0(hab, "_protected_km2")]] <- lookup_or_zero(protected_ha, out$landscape_id) / 100
    out[[paste0(hab, "_wtw_km2")]]       <- lookup_or_zero(wtw_ha,       out$landscape_id) / 100

    cover_col <- paste0("pcnt_landscape_", hab, "_cover")
    out[[cover_col]] <- round(out[[paste0(hab, "_km2")]] / landscape_km2[out$landscape_id] * 100, 2)

    total <- out[[paste0(hab, "_km2")]]
    out[[paste0("pcnt_", hab, "_protected")]] <- round(ifelse(total > 0, out[[paste0(hab, "_protected_km2")]] / total * 100, 0), 2)
    out[[paste0("pcnt_", hab, "_wtw")]]       <- round(ifelse(total > 0, out[[paste0(hab, "_wtw_km2")]]       / total * 100, 0), 2)

    # Zero out protected/WTW % when cover itself rounds to zero -- a tiny
    # protected sliver over an even tinier total habitat area otherwise
    # blows up into a misleadingly large %. Ported from commit fa0e745
    # ("Set protected and wtw percents to zero if the ecoregion total %
    # rounds to zero", erap-deer-code#7), extended to peatlands (added
    # 2026-10-20, postdating that commit, same failure mode applies).
    zeroed <- out[[cover_col]] == 0
    out[[paste0("pcnt_", hab, "_protected")]][zeroed] <- 0
    out[[paste0("pcnt_", hab, "_wtw")]][zeroed] <- 0

    out
  }

  print("  forest (raster)...")
  forest_total_ha     <- intersect_raster_values(cfg$habitat_raster$habitat_forest, terrestrial_sf, "landscape_id")
  forest_protected_ha <- intersect_raster_values(cfg$habitat_raster$habitat_forest, protected_in_landscape_sf, "landscape_id")
  forest_wtw_ha       <- intersect_raster_values(cfg$habitat_raster$habitat_forest, wtw_in_landscape_sf, "landscape_id")
  out <- add_nonlinear(out, "forest", forest_total_ha, forest_protected_ha, forest_wtw_ha)

  for (hab in c("grassland", "wetland", "lakes", "peatlands")) {
    print(paste0("  ", hab, " (vector)..."))
    hab_path <- cfg$habitat_vector[[paste0("habitat_", hab)]]
    total_ha     <- intersect_vector_values(hab_path, landscape_path, name_col)
    protected_ha <- intersect_vector_values(hab_path, list(landscape_path, protected_path), name_col)
    wtw_ha       <- intersect_vector_values(hab_path, list(landscape_path, wtw_path), name_col)
    out <- add_nonlinear(out, hab, total_ha, protected_ha, wtw_ha)
  }

  # Linear habitats -- rivers (terrestrial), coastline (marine) ------------

  add_linear <- function(out, hab, total_km, protected_km, wtw_km) {
    out[[paste0(hab, "_km")]]           <- lookup_or_zero(total_km,     out$landscape_id)
    out[[paste0(hab, "_protected_km")]] <- lookup_or_zero(protected_km, out$landscape_id)
    out[[paste0(hab, "_wtw_km")]]       <- lookup_or_zero(wtw_km,       out$landscape_id)

    total <- out[[paste0(hab, "_km")]]
    out[[paste0("pcnt_", hab, "_protected")]] <- round(ifelse(total > 0, out[[paste0(hab, "_protected_km")]] / total * 100, 0), 2)
    out[[paste0("pcnt_", hab, "_wtw")]]       <- round(ifelse(total > 0, out[[paste0(hab, "_wtw_km")]]       / total * 100, 0), 2)
    out
  }

  print("  rivers (vector, terrestrial)...")
  rivers_path <- cfg$habitat_vector$habitat_rivers
  rivers_total_km     <- intersect_vector_values(rivers_path, landscape_path, name_col)
  rivers_protected_km <- intersect_vector_values(rivers_path, list(landscape_path, protected_path), name_col)
  rivers_wtw_km       <- intersect_vector_values(rivers_path, list(landscape_path, wtw_path), name_col)
  out <- add_linear(out, "rivers", rivers_total_km, rivers_protected_km, rivers_wtw_km)

  print("  coastline (vector, marine)...")
  coastline_path <- cfg$habitat_vector$habitat_coastline
  coastline_total_km     <- intersect_vector_values(coastline_path, landscape_path_marine, name_col)
  coastline_protected_km <- intersect_vector_values(coastline_path, list(landscape_path_marine, protected_path), name_col)
  coastline_wtw_km       <- intersect_vector_values(coastline_path, list(landscape_path_marine, wtw_path), name_col)
  out <- add_linear(out, "coastline", coastline_total_km, coastline_protected_km, coastline_wtw_km)

  out
}
