source("R/fct_read_feature.R")

# Ports 5c_species_extractions.R, looped over landscapes instead of
# ecoregions one at a time, reusing conservation-profiles' species-stack/
# metadata functions (R/fct_build_species_tab.R, adapted -- see its header).
# Outputs are NOT joined into 09_gather_and_write.R's wide landscape table
# -- this is a long table (one row per species per landscape), same as the
# legacy pipeline's own per-ecoregion species CSVs/xlsx, which 7_gather_tables.R
# never merges into ERAP_attributes.csv either. Two checkpoint CSVs, kept
# as their own output product.
species <- function(cfg, landscapes) {
  print("07 species...")

  terrestrial_sf <- landscapes$terrestrial_sf
  name_col       <- cfg$landscape$name_col

  print("  loading species raster stack...")
  r_stack <- build_species_stack(cfg$species$species_dir)

  print("  protected area geometry...")
  protected_in_landscape_path <- intersect_vector_geoms(cfg$landscape$landscape_path, cfg$protected_data$protected_vector_path, name_col)
  protected_in_landscape_sf   <- read_feature(protected_in_landscape_path)
  delete_fc(protected_in_landscape_path)
  protected_in_landscape_sf$landscape_id <- protected_in_landscape_sf[[name_col]]

  print("  extracting species range per landscape...")
  df_total <- extract_species_km2_bulk(r_stack, terrestrial_sf, "landscape_id") |>
    dplyr::rename(Landscape_Total_km2 = km2)

  print("  extracting species range within protected areas...")
  df_protected <- extract_species_km2_bulk(r_stack, protected_in_landscape_sf, "landscape_id") |>
    dplyr::rename(Landscape_Protected_km2 = km2)

  df <- dplyr::left_join(df_total, df_protected, by = c("landscape_id", "File")) |>
    dplyr::filter(Landscape_Total_km2 > 0) |>
    tidyr::replace_na(list(Landscape_Protected_km2 = 0))

  print("  loading species metadata...")
  species_meta <- load_species_meta(cfg$species$species_metadata_path)

  species_tab <- dplyr::inner_join(species_meta, df, by = "File") |>
    dplyr::mutate(
      Landscape_Goal_km2            = Canada_Pct_Goal / 100 * Landscape_Total_km2,
      Landscape_Protection_Gap_km2  = pmax(Landscape_Goal_km2 - Landscape_Protected_km2, 0),
      Pct_Canada_range_in_landscape = pmin(Landscape_Total_km2 / Canada_Total_km2 * 100, 100)
    )

  species_summary <- summarise_species_tab(species_tab)

  list(species_tab = species_tab, species_summary = species_summary)
}
