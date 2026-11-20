source("R/fct_read_feature.R")

# Loads one landscape set (ecoregions OR Priority Landscapes, whichever
# setup.toml points at) -- both the terrestrial version (used by every step
# except coastline) and the marine version (buffered/unclipped, used only
# by 04_habitat.R's coastline step -- see the plan's "marine landscape
# layer" addendum). Every step after this one (03-07) only ever joins/loops
# on landscape_id, never on "ecoregion" by name -- that's what makes the
# same step code work unchanged for both landscape sets.
#
# landscape_id is name_col's values, copied onto both sf objects under one
# consistent column name regardless of which landscape set is active
# (ECOREGION_NAME_EN for the ecoregions run, NAME for Priority Landscapes).
# arcpy calls into R/fct_intersect_vector_value.py still dissolve on the
# *real* on-disk field name (name_col) -- landscape_id only exists as an R
# column, not written back onto the source feature class.
load_landscapes <- function(cfg) {
  landscape_cfg <- cfg$landscape
  name_col <- landscape_cfg$name_col

  terrestrial_sf <- read_feature(landscape_cfg$landscape_path)
  marine_sf      <- read_feature(landscape_cfg$landscape_path_marine)

  terrestrial_sf$landscape_id <- terrestrial_sf[[name_col]]
  marine_sf$landscape_id      <- marine_sf[[name_col]]

  # Six optional pass-through columns -- ECOREGION_ID/ECOREGION_NAME_EN/
  # ECOREGION_NAME_FR/ECOZONE_ID/ECOZONE_NAME_EN/ECOZONE_NAME_FR. Always
  # character, never numeric: the Priority Landscapes run can hold a
  # "/"-joined multi-value string in the same column (a landscape spanning
  # more than one ecoregion/ecozone -- see data_prep/"2 intersect_priority_
  # landscapes_ecoregions.py"), so both runs need to share one column type.
  # NA throughout when a *_col isn't set in setup.toml (not used by either
  # run currently -- both runs set all six -- but kept optional per the
  # original design).
  pass_through_cols <- list(
    ECOREGION_ID      = landscape_cfg$ecoregion_id_col,
    ECOREGION_NAME_EN = landscape_cfg$ecoregion_name_en_col,
    ECOREGION_NAME_FR = landscape_cfg$ecoregion_name_fr_col,
    ECOZONE_ID        = landscape_cfg$ecozone_id_col,
    ECOZONE_NAME_EN   = landscape_cfg$ecozone_name_en_col,
    ECOZONE_NAME_FR   = landscape_cfg$ecozone_name_fr_col
  )

  loop_tab <- sf::st_drop_geometry(terrestrial_sf)[, "landscape_id", drop = FALSE]
  for (out_col in names(pass_through_cols)) {
    src_col <- pass_through_cols[[out_col]]
    loop_tab[[out_col]] <- if (!is.null(src_col) && nzchar(src_col)) {
      as.character(terrestrial_sf[[src_col]])
    } else {
      NA_character_
    }
  }

  list(
    loop_tab       = loop_tab,        # one row per landscape: landscape_id + the six pass-through columns
    terrestrial_sf = terrestrial_sf,  # full geometry + attributes, used by every step except coastline
    marine_sf      = marine_sf        # full geometry, used only by 04_habitat.R's coastline step
  )
}
