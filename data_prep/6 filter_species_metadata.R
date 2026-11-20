# Build a project-specific copy of WTW_NAT_SPECIES_METADATA.xlsx, filtered
# down to exactly the species this project's pipeline actually has rasters
# for.
#
# Three filters, matching extract_species_tiffs_from_sparse_matrices.R's own
# filter exactly:
#   1. Sheet-level: keep only IUCN_AMPH, IUCN_BIRD, IUCN_MAMM, IUCN_REPT,
#      NCC_SDM, NCC_SAR_AOH -- drop ECCC_CH, ECCC_SAR, NSC_END, NSC_SAR,
#      NSC_SPP entirely (no rasters were extracted for those themes).
#   2. Row-level, within the kept sheets: keep only rows whose File matches
#      an actual tif under ERAPs_v2/data_prep/tiffs. Sheet-level filtering
#      alone isn't quite enough -- a handful of species per theme can fall
#      entirely outside the 1km grid and never get a tif written (see the
#      commented-out validation snippet at the bottom of
#      extract_species_tiffs_from_sparse_matrices.R), so this re-checks
#      against the actual output files rather than assuming 1:1.
#   3. Cross-worksheet de-duplication: the same species can be catalogued
#      under more than one theme (e.g. a species-at-risk range also sits in
#      the general SDM run, or an outdated scientific name in one sheet vs.
#      the current name in another), which would otherwise double-count its
#      area in extract_species_km2_bulk(). Subspecies/variants and distinct
#      populations are matched on the full scientific name, not the species
#      binomial, so they are never flagged as duplicates of each other. Rules
#      worked out with Marc in a separate session -- see
#      C:/Users/marc.edwards/Documents/claude_projects/species_duplicates/species_dedup_handoff.md
#      for the full rationale (priority order, synonym list provenance, open
#      items) -- this filter keeps the handoff's algorithm exactly, run here
#      (after the tif-match filter) so ties resolve only among species that
#      actually have a raster in this project.
#
# Output goes to the external project folder, not this repo and not
# NAT_DATA -- same convention as every other data_prep script.

library(readxl)
library(openxlsx)

natdata_meta_path <- "C:/Data/PRZ/NAT_DATA/NAT_DATA_20260708/WTW_NAT_SPECIES_METADATA.xlsx"

output_dir <- "C:/Users/marc.edwards/Documents/PROJECTS/ERAPs_v2/data_prep"
tiffs_dir  <- file.path(output_dir, "tiffs")

if (!dir.exists(tiffs_dir)) {
  stop("tiffs/ not found -- run extract_species_tiffs_from_sparse_matrices.R first")
}

KEEP_SHEETS <- c("IUCN_AMPH", "IUCN_BIRD", "IUCN_MAMM", "IUCN_REPT", "NCC_SDM", "NCC_SAR_AOH")

print("listing extracted tifs...")
tif_paths <- list.files(tiffs_dir, recursive = TRUE, full.names = TRUE, pattern = "\\.tiff?$")
tif_basenames <- basename(tif_paths)
cat(length(tif_basenames), "tifs found\n")

all_sheets <- excel_sheets(natdata_meta_path)
dropped_sheets <- setdiff(all_sheets, KEEP_SHEETS)
cat("dropping sheets:", paste(dropped_sheets, collapse = ", "), "\n")
cat("keeping sheets:", paste(KEEP_SHEETS, collapse = ", "), "\n")

sheet_list <- list()
total_kept <- 0
total_dropped_rows <- 0
for (s in KEEP_SHEETS) {
  df <- as.data.frame(read_excel(natdata_meta_path, s))
  n_before <- nrow(df)
  df <- df[df$File %in% tif_basenames, ]
  n_after <- nrow(df)
  cat(sprintf("%-12s %5d rows -> %5d rows (%d dropped, no matching tif)\n", s, n_before, n_after, n_before - n_after))
  total_kept <- total_kept + n_after
  total_dropped_rows <- total_dropped_rows + (n_before - n_after)
  sheet_list[[s]] <- df
}

cat("\ntotal rows kept:", total_kept, "| total rows dropped (no matching tif):", total_dropped_rows, "\n")

# Validate: every kept row matches a tif (by construction, but confirm) ----
all_files <- unlist(lapply(sheet_list, function(df) df$File))
unmatched <- all_files[!all_files %in% tif_basenames]
if (length(unmatched) > 0) {
  stop("BUG: ", length(unmatched), " rows still don't match a tif after filtering: ", paste(head(unmatched, 5), collapse = ", "))
}
cat("validated: every row in the project metadata table matches a tif in", tiffs_dir, "\n")

# Informational only: tifs with no metadata row (not an error -- a File in
# the metadata not matching a tif is the case this script guards against,
# but the reverse -- a tif with no metadata row -- doesn't affect
# recalc_species_protected_km2.R, which only ever looks up by File) -------
tifs_without_metadata <- setdiff(tif_basenames, all_files)
cat(length(tifs_without_metadata), "tifs have no matching metadata row (informational only)\n")

# Cross-worksheet de-duplication (filter 3, see header) ---------------------
# Priority when the same species appears in several sheets (highest wins):
#   1 NCC_SAR_AOH, 2 IUCN_BIRD, 3 NCC_SDM, 4 IUCN_AMPH/IUCN_MAMM/IUCN_REPT
SHEET_TIER <- c(
  NCC_SAR_AOH = 1,
  IUCN_BIRD   = 2,
  NCC_SDM     = 3,
  IUCN_AMPH   = 4,
  IUCN_MAMM   = 4,
  IUCN_REPT   = 4
)

# Outdated/alternate scientific names -> the name used elsewhere for the
# same species (matched via common name in the original handoff analysis).
SYNONYM_KEY <- c(
  "passerculus bairdii"      = "ammodramus bairdii",
  "tryngites subruficollis"  = "calidris subruficollis",
  "otus flammeolus"          = "psiloscops flammeolus",
  "pekania pennanti"         = "martes pennanti",
  "leucophaeus atricilla"    = "larus atricilla",
  "dryocopus pileatus"       = "hylatomus pileatus",
  "puffinus creatopus"       = "ardenna creatopus",
  "canachites canadensis"    = "falcipennis canadensis",
  "picoides albolarvatus"    = "leuconotopicus albolarvatus",
  "phalaropus tricolor"      = "steganopus tricolor"
)

normalize_sci_name <- function(x) {
  x <- trimws(x)
  x <- sub("_aoh\\.tif$", "", x, ignore.case = TRUE) # IUCN_AMPH/REPT filename suffix
  x <- sub("_[0-9]+$", "", x)                        # IUCN_BIRD season suffix
  x <- gsub("_", " ", x)
  x <- gsub("\\s+", " ", x)
  x <- tolower(x)
  mapped <- SYNONYM_KEY[x]
  ifelse(is.na(mapped), x, unname(mapped))
}

for (s in names(sheet_list)) {
  sheet_list[[s]]$dedup_key  <- normalize_sci_name(sheet_list[[s]]$Sci_Name)
  sheet_list[[s]]$dedup_tier <- SHEET_TIER[[s]]
}
all_rows <- do.call(rbind, lapply(sheet_list, function(df) df[, c("dedup_key", "dedup_tier")]))
best_tier <- tapply(all_rows$dedup_tier, all_rows$dedup_key, min)

cat("\nremoving cross-worksheet duplicate species (lower-priority sheet dropped):\n")
total_removed_dedup <- 0
for (s in names(sheet_list)) {
  df <- sheet_list[[s]]
  keep <- df$dedup_tier == best_tier[df$dedup_key]
  cat(sprintf("%-12s %5d rows -> %5d rows (%d dropped, cross-worksheet duplicate)\n", s, nrow(df), sum(keep), nrow(df) - sum(keep)))
  total_removed_dedup <- total_removed_dedup + (nrow(df) - sum(keep))
  sheet_list[[s]] <- df[keep, setdiff(names(df), c("dedup_key", "dedup_tier")), drop = FALSE]
}
cat("total rows removed as cross-worksheet duplicates:", total_removed_dedup, "\n")

out_path <- file.path(output_dir, "WTW_NAT_SPECIES_METADATA_project.xlsx")
write.xlsx(sheet_list, out_path)
cat("\nwrote", out_path, "\n")
