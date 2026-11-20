# Adapted from conservation-profiles' R/04_build_species_tab.R --
# build_species_stack() is copied verbatim; load_species_meta() is adapted
# to prefer Protected_Km2_vector (data_prep/"7 recalc_species_protected_km2.R"'s
# CPCAD-vector recalculation) over the original grid-based Protected_Km2
# per row, per the plan's "Protected_Km2_vector" addendum and this repo's
# CONSERVATION_PROFILES_CHANGES.md item 9 -- tracked there for porting the
# same fix into conservation-profiles' own copy. extract_species_km2_bulk()
# is new: conservation-profiles' extract_species_km2() assumes boundary_sf
# is a single dissolved feature (it always unions its one custom landscape
# first) and doesn't carry a landscape identifier through the pivot, so it
# can't be reused as-is for this repo's ~150-landscapes-at-once case.

# Pulls the multi-band species raster stack from species_dir -- copied
# verbatim from conservation-profiles.
build_species_stack <- function(species_dir) {
  r_paths <- list.files(species_dir, recursive = TRUE, full.names = TRUE, pattern = ".tiff?$")
  r_stack <- terra::rast(r_paths)
  names(r_stack) <- basename(terra::sources(r_stack))
  r_stack
}

# Bulk equivalent of extract_species_km2() -- exact_extract() across every
# landscape and every species at once (boundary_sf keeps one row per
# landscape_id, not unioned to a single feature), same bulk-pass reasoning
# as every other shared helper in this pipeline. Returns a long data.frame:
# id_col, File, km2.
#
# r_stack's full band count (~2,816 species rasters) is too much for
# exact_extract() to hold in memory at once against this repo's landscapes --
# one large landscape's bounding box read across every band simultaneously
# raised "cannot allocate vector of size 59.2 Gb", even after exactextractr's
# own max_cells_in_memory fallback (reading row-by-row per feature) kicked
# in. Looping over the band stack in chunks keeps each exact_extract() call's
# peak memory to one chunk's worth of bands rather than all of them.
extract_species_km2_bulk <- function(r_stack, boundary_sf, id_col, chunk_size = 100) {
  n_bands <- terra::nlyr(r_stack)
  chunk_starts <- seq(1, n_bands, by = chunk_size)

  chunks <- lapply(chunk_starts, function(start) {
    end <- min(start + chunk_size - 1, n_bands)
    vals <- exactextractr::exact_extract(r_stack[[start:end]], boundary_sf, fun = "sum")
    names(vals) <- sub("^sum\\.", "", names(vals))
    vals[[id_col]] <- boundary_sf[[id_col]]
    tidyr::pivot_longer(vals, cols = -dplyr::all_of(id_col), names_to = "File", values_to = "km2")
  })
  df <- dplyr::bind_rows(chunks)

  # NCC_SAR_AOH stores ha per 1km cell, not km2 -- same /100 correction
  # data_prep/"7 recalc_species_protected_km2.R" applies, confirmed against
  # WTW_NAT_PREP_METADATA.csv's own unit column. Matched by this theme's
  # current name directly, not the old "ECCC" substring check
  # conservation-profiles' extract_species_km2() still uses -- that theme
  # was renamed since (ECCC_SAR -> NCC_SAR_AOH, ECCC_CH dropped entirely),
  # so the substring check would silently stop applying here too (see this
  # repo's CONSERVATION_PROFILES_CHANGES.md item 9).
  df$km2[grepl("NCC_SAR_AOH", df$File)] <- df$km2[grepl("NCC_SAR_AOH", df$File)] / 100
  df
}

# Loads Canada-wide species metadata from an Excel workbook (one sheet per
# source) -- same shape as conservation-profiles' load_species_meta(), with
# one addition: prefers Protected_Km2_vector over Protected_Km2 per row
# when present (species_metadata_path here is data_prep/"6
# filter_species_metadata.R"'s project-specific, already-filtered copy,
# further updated in place by "7 recalc_species_protected_km2.R" -- not the
# true original WTW_NAT_SPECIES_METADATA.xlsx).
load_species_meta <- function(species_metadata_path) {
  sheets <- readxl::excel_sheets(species_metadata_path)
  meta <- do.call(rbind, lapply(sheets, function(sheet) {
    readxl::read_excel(species_metadata_path, sheet) |>
      dplyr::select(dplyr::any_of(c(
        "Source", "File", "Theme", "Sci_Name", "Common_Name", "Threat",
        "Total_Km2", "Protected_Km2", "Protected_Km2_vector", "Pct_Protected", "Goal"
      )))
  }))

  if ("Protected_Km2_vector" %in% names(meta)) {
    meta$Protected_Km2 <- ifelse(!is.na(meta$Protected_Km2_vector), meta$Protected_Km2_vector, meta$Protected_Km2)
    meta$Protected_Km2_vector <- NULL
  }

  names(meta)[names(meta) == "Total_Km2"]     <- "Canada_Total_km2"
  names(meta)[names(meta) == "Protected_Km2"] <- "Canada_Protected_km2"
  names(meta)[names(meta) == "Pct_Protected"] <- "Canada_Pct_Protected"
  names(meta)[names(meta) == "Goal"]          <- "Canada_Pct_Goal"

  meta$Canada_Pct_Goal           <- meta$Canada_Pct_Goal * 100
  meta$Canada_km2_Goal           <- meta$Canada_Total_km2 * (meta$Canada_Pct_Goal / 100)
  meta$Canada_Protection_Gap_km2 <- pmax(meta$Canada_km2_Goal - meta$Canada_Protected_km2, 0)

  meta
}

# Per-landscape, per-Source summary -- same shape as conservation-profiles'
# summarise_species_tab(), minus its two Project_* columns (there's no
# custom-project overlay concept in this pipeline, only landscapes), plus
# grouping by landscape_id since this repo always has more than one.
summarise_species_tab <- function(species_tab) {
  species_tab |>
    dplyr::group_by(landscape_id, Source) |>
    dplyr::summarise(
      Landscape_count = dplyr::n(),
      National_or_landscape_protection_shortfall = sum(Canada_Protection_Gap_km2 > 0 | Landscape_Protection_Gap_km2 > 0),
      .groups = "drop"
    )
}
