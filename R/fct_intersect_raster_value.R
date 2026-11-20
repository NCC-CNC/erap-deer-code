source("R/fct_read_raster.R")

# Bulk raster-sum-by-landscape -- one exact_extract() call across every
# landscape at once instead of looping (see the plan addendum "resolved --
# one bulk-pass function replaces the loop-vs-bulk choice": the same
# dissolve-by-ID reasoning applies here, and exact_extract() already
# returns one value per feature when given a multi-row boundary_sf, so no
# looping is needed at all -- confirmed much faster in this project
# already, e.g. the species raster stack: 19 minutes for one bulk call vs.
# an estimated 4+ hours extrapolated from a per-feature loop).
#
# Same ha/coverage_area convention as conservation-profiles'
# intersect_raster_value() (R/03_extract_raster_data.R) -- raster must be
# coded 1/0 or 1/NoData for the sum to mean an area.
#
# Returns a named numeric vector (ha), keyed by id_col. A landscape with
# zero overlap (e.g. no protected area at all) is simply absent from
# boundary_sf and therefore absent from the result -- callers should treat
# a missing landscape_id as 0, not an error (e.g. `vals[landscape_id]`
# wrapped in `ifelse(is.na(.), 0, .)` after a left_join).
intersect_raster_values <- function(rast_path, boundary_sf, id_col) {
  if (nrow(boundary_sf) == 0) return(setNames(numeric(0), character(0)))
  r <- read_raster(rast_path)
  vals <- exactextractr::exact_extract(
    x = r,
    y = boundary_sf,
    fun = "sum",
    coverage_area = TRUE
  )
  setNames(round(vals / 10000, 4), boundary_sf[[id_col]])
}

# Looks up each id in `ids` from a named-vector-like result keyed by
# landscape_id (intersect_raster_values()'s own return, or a dict returned
# by R/fct_intersect_vector_value.py's python functions -- reticulate
# converts a python dict to a named R *list*, not a vector, so unlist()
# here is what makes this work for both sources), substituting 0 for an id
# that isn't present -- the "missing landscape_id means zero overlap"
# convention every caller of either source needs, written once here
# instead of repeated at each call site.
lookup_or_zero <- function(values, ids) {
  values <- unlist(values)
  out <- unname(values[ids])
  out[is.na(out)] <- 0
  out
}
