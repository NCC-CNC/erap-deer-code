source("R/fct_intersect_raster_value.R")

# Ports 3_direct_threats.R -- % of each landscape covered by each pressure
# raster. The legacy script applied a >=0.1 (or 0-0.1 for transport_low)
# threshold to continuous footprint-intensity rasters itself; setup.toml's
# pressures_raster paths are already pre-thresholded binary (1/0) rasters
# (the "_binary"/"_binary_high"/"_binary_low" files), so no threshold logic
# is needed here -- same convention as intersect_raster_value() everywhere
# else in this pipeline (forest, intact/modified).
pressures <- function(cfg, landscapes) {
  print("05 pressures...")

  terrestrial_sf <- landscapes$terrestrial_sf
  landscape_km2 <- setNames(as.numeric(sf::st_area(terrestrial_sf)) / 1e6, terrestrial_sf$landscape_id)

  out <- sf::st_drop_geometry(terrestrial_sf)[, "landscape_id", drop = FALSE]

  pressure_map <- c(
    forestry        = "pressure_forestry",
    agriculture     = "pressure_agriculture",
    transport_high  = "pressure_transport_high",
    transport_low   = "pressure_transport_low",
    energy          = "pressure_energy",
    builtup         = "pressure_builtup"
  )

  for (col in names(pressure_map)) {
    print(paste0("  ", col, "..."))
    ha <- intersect_raster_values(cfg$pressures_raster[[pressure_map[[col]]]], terrestrial_sf, "landscape_id")
    km2 <- lookup_or_zero(ha, out$landscape_id) / 100
    out[[paste0(col, "_km2")]]  <- km2
    out[[paste0(col, "_pcnt")]] <- round(km2 / landscape_km2[out$landscape_id] * 100, 2)
  }

  out
}
