# Ports 7_gather_tables.R -- joins every numbered step's checkpoint table by
# landscape_id, converts every *_km2 column to *_ha (x100; length columns
# like rivers_km/coastline_km are left alone -- hectares don't apply to a
# length), rounds every numeric value (ha, km, and pct alike) to 2 decimal
# places (the final-output-table rounding rule, erap-deer-code#23 -- never
# applied upstream, every checkpoint CSV before this step stays
# full-precision), and writes both the flat csv and the spatial layer
# (landscape polygon + every attribute) that feeds the map viewer.
#
# Species tables (07_species.R's own two checkpoint CSVs) are NOT joined in
# here -- same as the legacy 7_gather_tables.R, which never merges species
# data into ERAP_attributes.csv either (one row per species per landscape
# doesn't fit this one-row-per-landscape schema). They're their own
# separate output product.
#
# actions_wide (08_actions.R's wide checkpoint) IS joined in here, matching
# 7_gather_tables.R's own join of action_recommendations_wide.csv into
# ERAP_attributes.csv -- one row per landscape, same shape as every other
# table joined below.
#
# The spatial write uses sf::st_write()'s OpenFileGDB driver rather than
# arcgisbinding::arc.write() (what the legacy script used) -- avoids an
# extra GitHub-installed dependency for a plain attribute join + write onto
# geometry this pipeline already has in hand. If this machine's GDAL build
# doesn't support OpenFileGDB writing, switch to arc.write() instead (same
# shape, just a different write call).
gather_and_write <- function(cfg, landscapes, protected_intactness_tab, habitat_tab, pressures_tab, wtw_tab, actions_wide_tab) {
  print("09 gather and write...")

  df <- landscapes$loop_tab |>
    dplyr::left_join(protected_intactness_tab, by = "landscape_id") |>
    dplyr::left_join(habitat_tab,              by = "landscape_id") |>
    dplyr::left_join(pressures_tab,             by = "landscape_id") |>
    dplyr::left_join(wtw_tab,                   by = "landscape_id") |>
    dplyr::left_join(actions_wide_tab,          by = "landscape_id")

  km2_cols <- grep("_km2$", names(df), value = TRUE)
  for (col in km2_cols) {
    ha_col <- sub("_km2$", "_ha", col)
    df[[ha_col]] <- df[[col]] * 100
    df[[col]] <- NULL
  }

  numeric_cols <- names(df)[sapply(df, is.numeric)]
  for (col in numeric_cols) df[[col]] <- round(df[[col]], 2)

  out_csv <- file.path(cfg$landscape$output_dir, paste0(cfg$landscape$output_name, "_attributes.csv"))
  # write_excel_csv(), not write_csv() -- both are UTF-8, but only
  # write_excel_csv() adds the UTF-8 BOM Excel needs to auto-detect the
  # encoding; without it Excel falls back to the system codepage and
  # mangles accented ecoregion names (e.g. ECOREGION_NAME_FR) on open.
  readr::write_excel_csv(df, out_csv)
  print(paste0("wrote ", out_csv))

  shp <- landscapes$terrestrial_sf |>
    dplyr::select(landscape_id) |>
    dplyr::left_join(df, by = "landscape_id")

  out_gdb <- file.path(cfg$landscape$output_dir, paste0(cfg$landscape$output_name, ".gdb"))
  sf::st_write(shp, dsn = out_gdb, layer = cfg$landscape$output_name, driver = "OpenFileGDB", delete_layer = TRUE, quiet = TRUE)
  print(paste0("wrote ", out_gdb, "/", cfg$landscape$output_name))

  df
}
