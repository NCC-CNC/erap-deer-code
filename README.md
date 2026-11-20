# erap-deer-code

Builds the national ERAP (Ecoregion Rapid Assessment Profile) table: habitat cover/protection/WTW-overlap, pressures, protected/intactness, species range/protection-gap metrics, and action recommendations, one row per ecoregion (and, going forward, one row per Priority Landscape).

Rebuilt from a chain of 19 loosely-coupled scripts with hardcoded absolute paths into a `setup.toml`-driven pipeline, matching the `conservation-profiles` pattern -- see `CHANGELOG.md` for the full list of structural and output-table changes this rebuild made.

## Data sources

- **Ecoregions/ecozones**: [Canadian Terrestrial Ecological Framework (CTEF) v2.2](https://www.natureserve.org/canada/featured-projects/national-ecological-framework-canada), downloaded from [open.canada.ca](https://open.canada.ca/data/en/dataset/3ef8e8a9-8d05-4fea-a8bf-7f5023d2b6e1), current version as of September 2026. Replaces an earlier internal ecoregions shapefile whose French ecoregion names turned out to be corrupted at the source and unrecoverable.
- **Priority Landscapes**: `NCC_landscapes_10072025_MarcEdits`, coastal boundaries realigned to the CanCoast coastline layer.

## Running the workflow

1. **`data_prep/` scripts, in numbered order** (see below) — one-time GIS/data prep that builds the reference layers and inputs `setup.toml` points at. All write their output to `C:/Users/marc.edwards/Documents/PROJECTS/ERAPs_v2/data_prep` (external, not this repo) — see each script's own header for its exact prerequisites and gotchas. arcpy scripts (`.py`) need ArcGIS Pro's own Python environment, not a plain Python install: `& "C:\Program Files\ArcGIS\Pro\bin\Python\envs\arcgispro-py3\python.exe" <script path>`.
2. **The pipeline itself**, once `setup_ecoregions.toml`/`setup_priority_landscapes.toml` point at real data-prep output:
   ```
   Rscript __pipeline__.R setup_ecoregions.toml
   Rscript __pipeline__.R setup_priority_landscapes.toml
   ```
   Each run writes its own checkpoint CSVs (`processing_dir`) and final output (`output_dir`'s `{output_name}_attributes.csv` + `{output_name}.gdb/{output_name}`) -- the two runs never share output, only the reference data in `setup.toml`'s non-`[landscape]` sections.
3. Every numbered step (`R/03_protected_intactness.R` .. `R/09_gather_and_write.R`) can be re-run on its own after a failure -- source `R/01_setup.R`/`R/02_load_landscapes.R` first to get `cfg`/`landscapes`, then just that step's file.

## `data_prep/`

One-time GIS/data prep, run in this numbered order, before the pipeline:

1. `prep_ecoregions.py` — builds the ecoregions reference layer from CTEF v2.2: dissolves to one row per ecoregion, joins ecozone names on, reprojects to Canada Albers, and clips to the terrestrial land base boundary (both the ecoregions and ecozone layers). Compressed-gdb gotcha: run `arcpy.management.UncompressFileGeodatabaseData(gdb_path)` on the CTEF source gdbs first if arcpy reports a feature class "does not exist or is not supported".
2. `intersect_priority_landscapes_ecoregions.py` — attributes each Priority Landscape with the ecoregion(s)/ecozone(s) it overlaps (`/`-joined where a landscape spans more than one), filtering boundary slivers between the two independently-digitized layers using a validated geometric rule (`perim_per_area_km >= 3.0`) — re-validate this rule whenever either source layer changes meaningfully.
3. `prep_cpcad_ncc_2025.py` — builds a true-vector CPCAD 2025 + NCC accomplishments dissolve (`cpcad_ncc_dslv_2025`), plus two NCC-only layers read by `R/08_actions.R` (`ncc_fs_ca_2025_dslv`, `ncc_fs_2025_dslv`).
4. `prep_cpcad_ncc_2025_terrestrial.py` — clips the terrestrial land base and `cpcad_ncc_dslv_2025` together, for the species protected-area recalculation below.
5. `extract_species_tiffs_from_sparse_matrices.R` — converts the national `.rds` sparse species matrices into per-species tifs, filtered to the 6 themes this pipeline uses.
6. `filter_species_metadata.R` — builds a project-specific copy of the species metadata workbook, matching 1:1 against the tifs from step 5.
7. `recalc_species_protected_km2.R` — recomputes species protected-range area from CPCAD (vector + terrestrial-clipped), writing new columns in place into step 6's workbook. Slow -- caches per-species-chunk results in `data_prep/cache/` (gitignored).
8. *(prioritizr solve chain -- `8 prioritizr/`, its own pre-existing `1`-`4`/`1e` numbering, run separately)*
9. `prep_wtw_erase_protected.py` — vectorizes the WTW no-Includes solution and erases `cpcad_ncc_dslv_2025` from it, producing the single `wtw_erased_protected` layer `setup.toml` points at (per `erap-deer-code#18`).
10. `gather_habitat_data.py` — reprojects the seven habitat source datasets into one `habitat/` folder, meant to run on whichever server has access to the source files, then be copied back here: the six vector layers go into `habitat/habitat.gdb`, and the forest raster into its own standalone `habitat/Forest_AAFC_LUTS_2020_NFIS_2022_30m.tif` -- kept out of the gdb because `ProjectRaster` into a File GDB raster dataset doesn't reliably carry the source's NoData value through (confirmed: background cells silently became a huge, valid-looking pixel value once read back via GDAL's OpenFileGDB raster driver, inflating every forest area figure hundreds of times over -- a plain GeoTIFF doesn't have this problem).
11. `gather_indigenous_territories.py` — downloads the full native-land.ca territories dataset and converts it to a local feature class.
12. `intersect_indigenous_territories.py` — intersects territories against ecoregions and Priority Landscapes separately, writing two CSVs (`erap-deer-code#28`) -- not currently consumed by the main pipeline, a standalone data product.

All generated GIS/data output lives in `C:/Users/marc.edwards/Documents/PROJECTS/ERAPs_v2/data_prep`, not in this repo.

## Notes on the ported methodology

**`wtw_percent` is % of the whole landscape covered by the WTW opportunity layer, with protected areas already erased out of that layer first (`erap-deer-code#18`)** -- not the legacy "% of the unprotected remainder" formula, and not a raster zonal-stat against the un-erased solution + a separate grid-based "Includes" layer. `06_wtw.R` intersects `wtw_erased_protected` (`data_prep/"9 prep_wtw_erase_protected.py"`'s output -- the WTW no-Includes solution with `cpcad_ncc_dslv_2025` erased out, as a true vector operation) directly against each landscape:

```
wtw_percent = wtw_area_km2 / landscape_km2 * 100
```

The erase step is what makes this safe to pair additively with `protected_pcnt` as a single "resiliency goal" figure (the issue's framing) -- without it, small protected areas the original 1km-grid prioritizr run missed would still show up as "WTW opportunity", double-counting the same ground under both percentages. `04_habitat.R`'s per-habitat WTW overlap (`forest_wtw_km2`, `coastline_wtw_km`, etc.) uses this same erased layer, for the same reason -- there is only one WTW input anywhere in this pipeline now, not a separate raster solution for `06_wtw.R` and a separate un-erased vector for habitat overlap.

This superseded an earlier note (kept here for context on why it isn't the current rule): the legacy pipeline's "% of unprotected land" formula needed its "already protected" figure (`includes_km2`) to come from the same rasterized 1km-grid layer the WTW solve itself was built against (`protected_grid_path`), never from intersecting the real CPCAD vector polygons -- mixing the two would have made the numerator and denominator disagree about what "protected" means. That concern doesn't disappear under the new formula, it just moves: `#18` handles it by cleaning the vector protected-areas layer *out of the WTW solution itself* before computing `wtw_area_km2`, rather than by keeping a separate grid-consistent "already protected" denominator term. `includes_km2`/`protected_grid_path` no longer exist anywhere in this pipeline.
