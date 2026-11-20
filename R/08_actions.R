source("R/fct_intersect_raster_value.R") # for lookup_or_zero() -- no raster work in this step itself

# Ports 6_action_recommendations.R onto this pipeline's per-landscape
# checkpoint tables, generically over landscape_id (both the ecoregions and
# Priority Landscapes runs) instead of looping a hardcoded, ecozone-filtered
# ecoregion shapefile one row at a time. Trigger logic (abc1()..partner1())
# kept the same as the legacy script, except where an input it depended on
# no longer exists in this pipeline:
#   - ABC2/ABC3 originally counted SAR *and* Critical Habitat species
#     together. CH is no longer tracked anywhere in this pipeline's species
#     data (only the "SAR (NCC AOH)" theme remains -- see
#     R/fct_build_species_tab.R), so these two count SAR alone now.
#   - REST1/REST2's old inputs (a combined protected+intact coverage
#     estimate, and "% of unprotected land that's modified") no longer
#     exist as columns -- erap-deer-code#29 replaced them with full-
#     landscape intact/modified percentages using a different denominator
#     (protected_intact_pcnt is now the protected/intact *overlap*, not the
#     legacy combined estimate). Recomputed explicitly below from
#     intact_km2/modified_km2/protected_intact_km2/protected_modified_km2/
#     landscape_km2/protected_km2, reproducing the legacy formulas
#     (including their own denominator -- the pressure-raster-classified
#     subset of unprotected land, not the full unprotected land area)
#     exactly, so REST1/REST2's definitions and thresholds are unchanged
#     from the legacy script.
#   - STEW1/PARTNER1 need NCC's fee-simple(+CA) properties as their own
#     layer. data_prep/"3 prep_cpcad_ncc_2025.py" now persists
#     ncc_fs_ca_path (fee simple + conservation agreement) and ncc_fs_path
#     (fee simple only) instead of dissolving them away into the merged
#     CPCAD+NCC protected-areas layer, so they can be intersected per
#     landscape here the same bulk way as every other vector input.
#
# actions_wide (one row per landscape, a Yes/No column per trigger) IS
# joined into 09_gather_and_write.R's table, matching the legacy script's
# own 7_gather_tables.R join. actions_long (one row per landscape per
# triggered action) is NOT -- same reasoning as 07_species.R's own
# checkpoint tables: that shape doesn't fit the one-row-per-landscape
# schema, so it stays its own separate output.
actions <- function(cfg, landscapes, protected_intactness_tab, wtw_tab, species_tab) {
  print("08 actions...")

  landscape_path <- cfg$landscape$landscape_path
  name_col       <- cfg$landscape$name_col

  out <- protected_intactness_tab[, c(
    "landscape_id", "landscape_km2", "protected_km2", "protected_pcnt",
    "intact_km2", "modified_km2", "protected_intact_km2", "protected_modified_km2"
  )]
  out <- dplyr::left_join(out, wtw_tab[, c("landscape_id", "wtw_area_km2", "wtw_percent")], by = "landscape_id")

  print("  SAR shortfall counts...")
  sar_counts <- species_tab |>
    dplyr::filter(Theme == "SAR (NCC AOH)", Canada_Protection_Gap_km2 > 0) |>
    dplyr::group_by(landscape_id) |>
    dplyr::summarise(
      SAR_99    = sum(Pct_Canada_range_in_landscape > 99),
      SAR_50_99 = sum(Pct_Canada_range_in_landscape >= 50 & Pct_Canada_range_in_landscape <= 99),
      .groups = "drop"
    )
  out <- dplyr::left_join(out, sar_counts, by = "landscape_id")
  out <- tidyr::replace_na(out, list(SAR_99 = 0, SAR_50_99 = 0))

  print("  NCC fee-simple / conservation-agreement area...")
  fs_ca_ha <- intersect_vector_values(cfg$protected_data$ncc_fs_ca_path, landscape_path, name_col)
  fs_ha    <- intersect_vector_values(cfg$protected_data$ncc_fs_path,    landscape_path, name_col)
  out$ncc_fs_ca_km2 <- lookup_or_zero(fs_ca_ha, out$landscape_id) / 100
  out$ncc_fs_km2    <- lookup_or_zero(fs_ha,    out$landscape_id) / 100

  # REST1/REST2 port 6_action_recommendations.R's combined protected+intact
  # coverage estimate exactly, including its denominator: the "intact share
  # of the unprotected remainder" is restricted to the pressure-raster-
  # classified subset of unprotected land (unprotected_intact_km2 +
  # unprotected_modified_km2), which can fall slightly short of the full
  # unprotected land area (raster/polygon edge gaps -- see
  # 03_protected_intactness.R) -- not landscape_km2 - protected_km2.
  unprotected_km2          <- out$landscape_km2 - out$protected_km2
  unprotected_intact_km2   <- out$intact_km2    - out$protected_intact_km2
  unprotected_modified_km2 <- out$modified_km2  - out$protected_modified_km2
  unprotected_total_km2    <- unprotected_intact_km2 + unprotected_modified_km2

  out$protected_intact_pcnt <- round(
    (out$protected_km2 + unprotected_km2 * ifelse(unprotected_total_km2 > 0, unprotected_intact_km2 / unprotected_total_km2, 0))
      / out$landscape_km2 * 100,
    2
  )
  out$unprotected_modified_pcnt <- round(ifelse(unprotected_total_km2 > 0, unprotected_modified_km2 / unprotected_total_km2 * 100, 0), 2)

  # Trigger -> (value column, condition). Ported verbatim from
  # 6_action_recommendations.R's abc1()..partner1(), applied vectorized
  # across every landscape at once.
  trigger_col <- c(
    ABC1 = "protected_pcnt", ABC2 = "SAR_99", ABC3 = "SAR_50_99",
    ABC4 = "wtw_percent", ABC5 = "wtw_area_km2", STEW1 = "ncc_fs_ca_km2",
    REST1 = "protected_intact_pcnt", REST2 = "unprotected_modified_pcnt",
    PARTNER1 = "ncc_fs_km2"
  )
  out$ABC1     <- out$protected_pcnt < 30
  out$ABC2     <- out$SAR_99 > 0
  out$ABC3     <- out$SAR_50_99 >= 5
  out$ABC4     <- out$wtw_percent > 15
  out$ABC5     <- out$wtw_area_km2 > 10000
  out$STEW1    <- out$ncc_fs_ca_km2 > 0
  out$REST1    <- out$protected_intact_pcnt < 30
  out$REST2    <- out$unprotected_modified_pcnt >= 30
  out$PARTNER1 <- out$ncc_fs_km2 > 0

  action_ids <- names(trigger_col)

  actions_long <- do.call(rbind, lapply(action_ids, function(id) {
    sub <- out[out[[id]], ]
    if (nrow(sub) == 0) return(NULL)
    tibble::tibble(landscape_id = sub$landscape_id, ID = id, Landscape_value = sub[[trigger_col[[id]]]])
  }))
  actions_long$Landscape_value <- round(actions_long$Landscape_value, 2)

  # Landscapes with no triggered action get an explicit placeholder row,
  # same as the legacy script.
  no_action_ids <- setdiff(out$landscape_id, unique(actions_long$landscape_id))
  if (length(no_action_ids) > 0) {
    actions_long <- rbind(actions_long, tibble::tibble(
      landscape_id = no_action_ids, ID = "No recommended actions", Landscape_value = NA_real_
    ))
  }

  actions_ref <- readxl::read_excel(cfg$actions$actions_reference_path)
  actions_long <- actions_long |>
    dplyr::left_join(actions_ref, by = "ID") |>
    dplyr::select(landscape_id, ID, `Action CMP 2.0`, Description, Indicator, `Trigger condition`, Landscape_value)

  actions_wide <- out[, c("landscape_id", action_ids)]
  for (id in action_ids) actions_wide[[id]] <- ifelse(out[[id]], "Yes", "No")
  actions_wide$ABC_count         <- rowSums(out[, c("ABC1", "ABC2", "ABC3", "ABC4", "ABC5")])
  actions_wide$Restoration_count <- rowSums(out[, c("REST1", "REST2")])

  list(actions_long = actions_long, actions_wide = actions_wide)
}
