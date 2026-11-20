# Recompute species protected-range area from CPCAD (vector), not the 1km
# grid WTW_NAT_SPECIES_METADATA.xlsx's Protected_Km2 column was built from
# -- clipped to the terrestrial land base throughout, since we only care
# about a species' full range inside the terrestrial polygon and its range
# inside the terrestrial protected areas, not an unclipped CPCAD figure.
#
# Protected_Km2 in the metadata was computed against the "Includes" 1km
# planning-unit grid used to build the WTW solution (see the plan addendum
# "WTW % must stay on the 1km grid" -- that grid is the right basis for WTW
# calculations specifically, but it's a coarser representation of what's
# actually protected than CPCAD's real polygons, so it's the wrong basis
# for a species-level protected-area figure). This intersects each
# species' national range raster directly against CPCAD instead, clipped
# to the terrestrial land base. An earlier, now-removed version of this
# script also computed an unclipped CPCAD figure (Protected_Km2_vector) as
# a first pass at this fix, before the terrestrial-clipped columns below
# existed -- confirmed on a 3-species smoke test (Moose, Pronghorn, Pallid
# Bat) that even that unclipped figure was already 14.5-33% lower than the
# grid-based Protected_Km2 for all three, not rounding noise; the
# terrestrial-clipped figures below only sharpen that further.
#
# New columns -- Total_Km2_terrestrial, Protected_Km2_terrestrial,
# Pct_Protected_terrestrial, Goal_terrestrial -- added alongside the
# original Total_Km2/Protected_Km2/Goal, not replacing them, and never
# touching the true original NAT_DATA_20260708/WTW_NAT_SPECIES_METADATA.xlsx
# (this script never opens it). Written in place into "6
# filter_species_metadata.R"'s already-filtered project copy
# (WTW_NAT_SPECIES_METADATA_project.xlsx) -- there's only one
# project-specific metadata file, not a chain of filtered-then-vector-
# then-terrestrial copies. New column names rather than overwrites, so
# any reader (this repo's own 07_species.R, or conservation-profiles'
# load_species_meta()) can tell whether it's looking at the updated file
# just by checking whether these columns exist, rather than trusting a
# path or version string.
#
# Uses the most current source data found on this machine, not the paths
# hardcoded in the legacy 5c_species_extractions.R / 1d_prioritizr_ecozones.R
# (both several data versions behind):
#   - Species rasters + metadata: project-specific outputs of "5 extract_
#     species_tiffs_from_sparse_matrices.R" and "6 filter_species_metadata.R"
#     (data_prep/tiffs and data_prep/WTW_NAT_SPECIES_METADATA_project.xlsx
#     in ERAPs_v2), not NAT_DATA_20260708 directly -- that data bundle's own
#     species tifs/metadata cover only some themes (this project filters to
#     IUCN_AMPH/BIRD/MAMM/REPT, NCC_SDM, NCC_SAR_AOH; ECCC_CH, ECCC_SAR,
#     NSC_END/SAR/SPP are dropped, deliberately, by those two scripts), and
#     NAT_DATA_20260708 itself has been through at least one archive/refresh
#     cycle since this pipeline was first built against it -- pointing at
#     the project's own filtered, extracted copies avoids depending on
#     NAT_DATA_20260708's internal layout staying stable.
#   - Protected areas: this script never reads cpcad_ncc_dslv_2025
#     directly -- only the two layers "4 prep_cpcad_ncc_2025_terrestrial.py"
#     derives from it (terrestrial_land_base and protected_terrestrial,
#     see below). See "3 prep_cpcad_ncc_2025.py"'s own header for how
#     cpcad_ncc_dslv_2025 itself is built (a true vector CPCAD-2025 +
#     NCC accomplishments dissolve, and the story of a first, wrong 2025
#     source layer that turned out to be a raster-to-point-buffer product
#     in disguise, not a real vector redigitization).
#
# All data_prep script output lives in
# C:/Users/marc.edwards/Documents/PROJECTS/ERAPs_v2/data_prep, not in this repo --
# shared across every data_prep script (not just this one).
#
# Total_Km2_terrestrial is species range area clipped to the terrestrial
# land base (Terrestrial_land_base/Terrestrial_Base_Data.gdb's
# geo_political_region_2_..._FInal_20250815, the same clip layer
# prep_ecoregions.py uses -- 158,199 features, MULTIPOLYGON, no curves,
# already in Canada_Albers_WGS_1984, confirmed via a plain sf::st_read
# smoke test, no Densify needed). Protected_Km2_terrestrial is the part of
# that which ALSO falls inside cpcad_ncc_dslv_2025 -- not just CPCAD's own
# BIOME='T' attribute filter (already applied when cpcad_ncc_dslv_2025 was
# built), since a BIOME='T' polygon can still dip into water at its edges
# relative to this more precise land/water boundary (it specifically
# handles Great Lakes and Ontario islands, per its own name).
# Goal_terrestrial uses calculate_targets() (functions/fct_calculate_targets.R,
# same function the legacy pipeline uses) against Total_Km2_terrestrial.
#
# Prerequisite: run "4 prep_cpcad_ncc_2025_terrestrial.py" (data_prep/,
# arcpy) first -- it copies the terrestrial land base locally and builds
# both terrestrial_land_base and protected_terrestrial (terrestrial x
# cpcad_ncc_dslv_2025) once, so this script just extracts species rasters
# against two static polygons rather than intersecting on every run. (That
# script has its own prerequisite on "3 prep_cpcad_ncc_2025.py".)
#
# Prerequisite: run "5 extract_species_tiffs_from_sparse_matrices.R" then
# "6 filter_species_metadata.R" first too -- 5 converts NAT_DATA_20260708's
# .rds sparse matrices into per-species tifs (filtered to the 6 themes
# above) in data_prep/tiffs; 6 builds the matching filtered metadata
# workbook in data_prep/, keeping only rows with an actual extracted tif
# (validated 1:1 when last run: 2,816 rows, 2,816 tifs, 0 unmatched either
# direction).
#
# This is a big, slow computation, two exact_extract() passes (one per
# boundary). Measured for an earlier single-pass version: 19.1 minutes for
# the full 2,816-species run -- far faster than the ~4.2 hour estimate
# extrapolated from per-species smoke-test timing, because one
# exact_extract() call across the whole raster stack beats one call per
# species. exact_extract() returns one row per polygon for each boundary
# layer (neither is unioned to a single multipart feature -- an earlier
# attempt at that hit a curve problem even after a plain dissolve, back
# when the CPCAD source itself contained curves); summed across all rows
# per species afterward below.

library(sf)
library(terra)
library(exactextractr)
library(readxl)
library(openxlsx)
source("R/fct_calculate_targets.R")

start_time <- Sys.time()

species_dir       <- "C:/Users/marc.edwards/Documents/PROJECTS/ERAPs_v2/data_prep/tiffs"
species_meta_path <- "C:/Users/marc.edwards/Documents/PROJECTS/ERAPs_v2/data_prep/WTW_NAT_SPECIES_METADATA_project.xlsx"

# All generated data lives in the external project folder, not in the repo
# -- data_prep_dir/repo_root above are only used to find this repo's own
# functions/ source file just below, nothing else.
output_dir      <- "C:/Users/marc.edwards/Documents/PROJECTS/ERAPs_v2/data_prep"
terrestrial_gdb <- file.path(output_dir, "terrestrial.gdb")

if (!dir.exists(terrestrial_gdb)) {
  stop("terrestrial.gdb not found -- run \"4 prep_cpcad_ncc_2025_terrestrial.py\" first (see this script's header comment)")
}

print("loading terrestrial land base layer...")
terrestrial_sf <- st_read(terrestrial_gdb, "terrestrial_land_base", quiet = TRUE)

print("loading terrestrial x protected intersection layer...")
protected_terrestrial_sf <- st_read(terrestrial_gdb, "protected_terrestrial", quiet = TRUE)

# Species raster stack -- all files at once; one exact_extract() call below
# extracts every band in a single pass, same pattern as
# conservation-profiles' extract_species_km2()/5c_species_extractions.R ---

print("listing species rasters...")
r_paths <- list.files(species_dir, recursive = TRUE, full.names = TRUE, pattern = "\\.tiff?$")
cat(length(r_paths), "species rasters found\n")

r_stack <- rast(r_paths)
names(r_stack) <- basename(sources(r_stack))

# Some species themes store ha per 1km cell, not km2 -- same /100
# correction extract_species_km2()/5c_species_extractions.R apply
# elsewhere. Applied identically to every boundary's raw sum below, since
# it's a property of how the raster itself stores values, not of which
# polygon it's summed against.
#
# Confirmed directly against WTW_NAT_PREP_METADATA.csv's own `unit`
# column, not assumed from naming: of the 6 themes this pipeline uses
# (IUCN_AMPH/BIRD/MAMM/REPT, NCC_SAR_AOH, NCC_SDM), only NCC_SAR_AOH is
# "ha" -- the other 5 are "km2" already. This used to be checked via
# grepl("ECCC", ...), because the pre-rename data called this same theme
# ECCC_SAR (which also stored ha) -- that source is now called
# NCC_SAR_AOH instead (no more "ECCC" in the filename at all: ECCC_CH has
# been dropped entirely, and ECCC_SAR was renamed, not just relabeled --
# same underlying data, per WTW_NAT_PREP_METADATA.csv). The old
# ECCC-substring check would have silently stopped applying this
# correction to this theme without erroring, so it's matched directly by
# its own current name instead.

is_ha_per_cell <- grepl("NCC_SAR_AOH", names(r_stack))

# Each boundary's exact_extract() call materializes a full features x species
# matrix in memory. A first attempt at all three passes in one R session
# crashed on the second pass (terrestrial land base, 158,199 polygons) with
# "Error: std::bad_alloc" -- even after adding explicit rm()+gc() between
# passes, it crashed at the exact same spot again, and this machine had
# 39GB free at the time, so it isn't really about total memory, or about
# the previous pass's memory not being released -- exact_extract()
# building one 158,199 x 2,816 (~446M cell) result matrix in a single call
# is itself the problem, independent of what ran before it. Fixed by
# chunking the species raster stack -- each exact_extract() call processes
# CHUNK_SIZE species at a time, not all 2,816 at once, which caps the size
# of the single largest allocation regardless of boundary feature count.
# Each chunk is cached separately too, so a crash partway through one
# boundary's chunks only costs that one chunk, not the whole boundary.

CHUNK_SIZE <- 200

cache_dir <- file.path(output_dir, "cache")
if (!dir.exists(cache_dir)) dir.create(cache_dir)

sum_by_boundary <- function(boundary_sf, label, cache_key) {
  final_cache_path <- file.path(cache_dir, paste0(cache_key, ".rds"))
  if (file.exists(final_cache_path)) {
    print(paste0("loading cached result for ", label, "..."))
    return(readRDS(final_cache_path))
  }

  n_layers <- terra::nlyr(r_stack)
  chunk_starts <- seq(1, n_layers, by = CHUNK_SIZE)
  chunk_results <- vector("list", length(chunk_starts))

  for (i in seq_along(chunk_starts)) {
    chunk_cache_path <- file.path(cache_dir, paste0(cache_key, "_chunk_", i, ".rds"))
    if (file.exists(chunk_cache_path)) {
      chunk_results[[i]] <- readRDS(chunk_cache_path)
      next
    }
    lo <- chunk_starts[i]
    hi <- min(lo + CHUNK_SIZE - 1, n_layers)
    print(paste0(
      "extracting species area against ", label, " -- chunk ", i, " of ",
      length(chunk_starts), " (layers ", lo, "-", hi, ")..."
    ))
    chunk_stack <- r_stack[[lo:hi]]
    vals <- exact_extract(chunk_stack, boundary_sf, "sum", progress = FALSE)
    names(vals) <- sub("^sum\\.", "", names(vals))
    totals <- colSums(vals)
    rm(vals, chunk_stack)
    gc()
    saveRDS(totals, chunk_cache_path)
    chunk_results[[i]] <- totals
  }

  totals <- do.call(c, chunk_results)
  totals[is_ha_per_cell] <- totals[is_ha_per_cell] / 100
  saveRDS(totals, final_cache_path)
  totals
}

# Extract species area per boundary, in one pass each ------------------------

total_km2_terrestrial     <- sum_by_boundary(terrestrial_sf, "terrestrial land base", "cache_total_km2_terrestrial")
protected_km2_terrestrial <- sum_by_boundary(protected_terrestrial_sf, "terrestrial x protected intersection", "cache_protected_km2_terrestrial")

pct_protected_terrestrial <- round((protected_km2_terrestrial / total_km2_terrestrial) * 100, 2)

# calculate_targets() (functions/fct_calculate_targets.R) builds its result
# via rep(NA_real_, length(x)) and never copies x's names onto it, so the
# by-name lookups below (goal_terrestrial[df$File]) would silently return
# NA for every row without this -- confirmed directly (every row, not just
# the themes with no matching raster, came back NA before this fix).
goal_terrestrial <- calculate_targets(total_km2_terrestrial)
names(goal_terrestrial) <- names(total_km2_terrestrial)

# Join onto each sheet and write back in place, into species_meta_path
# itself (WTW_NAT_SPECIES_METADATA_project.xlsx, "6 filter_species_metadata.R"'s
# output) -- not a further separate copy, and never the true original
# NAT_DATA_20260708/WTW_NAT_SPECIES_METADATA.xlsx, which this script never
# opens at all.

print("writing updated metadata workbook...")
sheets <- excel_sheets(species_meta_path)
sheet_list <- list()
for (s in sheets) {
  df <- as.data.frame(read_excel(species_meta_path, s))
  df$Total_Km2_terrestrial      <- round(unname(total_km2_terrestrial[df$File]), 2)
  df$Protected_Km2_terrestrial  <- round(unname(protected_km2_terrestrial[df$File]), 2)
  df$Pct_Protected_terrestrial  <- unname(pct_protected_terrestrial[df$File])
  df$Goal_terrestrial           <- unname(goal_terrestrial[df$File])

  # Drop species with zero terrestrial range -- a species whose entire
  # modeled range falls outside the terrestrial land base (e.g. pelagic
  # seabirds, or a range too small/coastal to retain any area after
  # terrestrial clipping) has nothing meaningful to report here, and
  # Pct_Protected_terrestrial is undefined (0/0) for these rows anyway.
  n_before <- nrow(df)
  df <- df[df$Total_Km2_terrestrial > 0, ]
  cat(sprintf("%-12s dropped %d of %d rows with zero terrestrial range\n", s, n_before - nrow(df), n_before))

  sheet_list[[s]] <- df
}

write.xlsx(sheet_list, species_meta_path)
cat("wrote", species_meta_path, "\n")

print(Sys.time() - start_time)
