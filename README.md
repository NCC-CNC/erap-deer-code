# erap-deer-code

Builds the national ERAP (Ecoregion Rapid Assessment Profile) table: habitat cover/protection/WTW-overlap, pressures, protected/intactness, species range/protection-gap metrics, and action recommendations -- one row per ecoregion, and one row per Priority Landscape, via two separate pipeline runs over the same code.

## Requirements

- R, with packages installed automatically by `R/01_setup.R` on first run.
- ArcGIS Pro's licensed Python environment (for `arcpy`-based vector intersections) -- path set in `arcgis_config.toml`.
- The `data_prep/"8 prioritizr"` chain additionally needs a local clone of [`wtw-data-prep2`](https://github.com/NCC-CNC/wtw-data-prep2) and the `prioritizr` R package.

## Running the workflow

1. **`data_prep/` scripts, in numbered order** -- one-time GIS/data prep that builds the reference layers `setup.toml` points at. All write their output outside this repo. arcpy scripts (`.py`) need ArcGIS Pro's own Python environment: `& "<arcgis_config.toml's python_path>" <script path>`.
2. **The pipeline**, once `setup_ecoregions.toml` / `setup_priority_landscapes.toml` point at real data-prep output:
   ```
   Rscript __pipeline__.R   # toml_path is set near the top of the file -- edit it to switch landscape sets
   ```
   Each run writes its own checkpoint CSVs (`processing_dir`) and final output (`output_dir`'s `{output_name}_attributes.csv` + `{output_name}.gdb/{output_name}`).
3. Any numbered step (`R/03_protected_intactness.R` .. `R/09_gather_and_write.R`) can be re-run on its own after a failure -- source `R/01_setup.R` then `R/02_load_landscapes.R` first to get `cfg`/`landscapes`, then just that step's file.

## `data_prep/`

Run in this numbered order, before the pipeline:

1. `prep_ecoregions.py` -- builds the ecoregions reference layer: dissolves to one row per ecoregion, joins ecozone names on, reprojects to Canada Albers, clips to the terrestrial land base.
2. `intersect_priority_landscapes_ecoregions.py` -- attributes each Priority Landscape with the ecoregion(s)/ecozone(s) it overlaps.
3. `prep_cpcad_ncc_2025.py` -- builds a true-vector CPCAD + NCC accomplishments dissolve, plus two NCC-only layers (fee-simple+CA, fee-simple-only) read by `R/08_actions.R`.
4. `prep_cpcad_ncc_2025_terrestrial.py` -- clips the terrestrial land base and the CPCAD+NCC dissolve together, for the species protected-area recalculation below.
5. `extract_species_tiffs_from_sparse_matrices.R` -- converts the national sparse species matrices into per-species tifs.
6. `filter_species_metadata.R` -- builds a project-specific copy of the species metadata workbook, matching the tifs from step 5.
7. `recalc_species_protected_km2.R` -- recomputes species protected-range area from CPCAD, writing new columns into step 6's workbook.
8. *(prioritizr solve chain -- `8 prioritizr/`, its own numbering, run separately -- see below)*
9. `prep_wtw_erase_protected.py` -- vectorizes the WTW no-Includes solution and erases the CPCAD+NCC layer from it, producing `Canada_wtw_2026`.
10. `gather_habitat_data.py` -- reprojects the habitat source datasets into one local `habitat/` folder (vector layers into `habitat.gdb`, the forest raster as a standalone GeoTIFF).
11. `gather_indigenous_territories.py` -- downloads the native-land.ca territories dataset and converts it to a local feature class.
12. `intersect_indigenous_territories.py` -- intersects territories against ecoregions and Priority Landscapes, writing two standalone CSVs (not consumed by the main pipeline).
13. `repair_wetland_geometry.py` / 14. `repair_peatlands_geometry.py` -- run only if the main pipeline's intersect step errors on invalid topology in `habitat_wetland`/`habitat_peatlands`; repairs the feature class in place.

### `data_prep/8 prioritizr/`

The WTW opportunity-map solve, run ecozone by ecozone then merged:

1. `1_initiate_project_ecozones.R` -- sets up one WTW project per ecozone.
2. `2_aoi_to_1km_grid.R` -- builds the 1km planning-unit grid for each ecozone AOI.
3. `3_natdata_to_aoi.R` -- clips national input data to each AOI.
4. `4_prioritizr.R` -- runs the `prioritizr` solve per ecozone and merges results into the national `Canada_wtw_2026`/no-Includes rasters.
5. `1e_prioritizr_ecoregion_intersects.R` -- intersects the solve rasters against ecoregions.

## `R/`

1. `01_setup.R` -- installs required packages, reads `setup.toml`, points `reticulate` at the ArcGIS Pro Python environment.
2. `02_load_landscapes.R` -- loads the active landscape set (terrestrial + marine versions) and assigns `landscape_id`.
3. `03_protected_intactness.R` -- protected / intact / modified area and percent columns.
4. `04_habitat.R` -- habitat cover, protected overlap, and WTW overlap per habitat type.
5. `05_pressures.R` -- % of each landscape covered by each human-footprint pressure.
6. `06_wtw.R` -- WTW opportunity area/percent per landscape.
7. `07_species.R` -- species range/protection-gap metrics (own checkpoint CSVs, not joined into the main table).
8. `08_actions.R` -- action-recommendation trigger flags, joined against `tables/ERAP Action recommendation reference.xlsx`.
9. `09_gather_and_write.R` -- joins every step's checkpoint table, converts units, rounds, and writes the final CSV + spatial output.
10. `10_build_profiles.R` -- renders the per-landscape PDF report cards.

Helpers (`fct_*`): `fct_read_feature.R`/`fct_read_raster.R` (format-agnostic vector/raster readers), `fct_intersect_vector_value.py`/`fct_intersect_raster_value.R` (bulk vector/raster intersection against all landscapes at once), `fct_build_species_tab.R` (species stack + metadata join), `fct_calculate_targets.R` (Rodrigues-style conservation targets), `fct_create_1km_grid.R` (AOI-to-grid, used by the prioritizr chain).

## Config files

- `setup_ecoregions.toml` / `setup_priority_landscapes.toml` -- all pipeline paths and parameters, one per landscape set.
- `arcgis_config.toml` -- local path to the ArcGIS Pro Python environment.

## Input data

`setup.toml` only points at `data_prep/`'s own output, never at original raw/source datasets. Raw source paths are set near the top of each `data_prep/` script that needs one:

- `prep_ecoregions.py` -- ecoregions/ecozones source dataset.
- `intersect_priority_landscapes_ecoregions.py` -- Priority Landscapes source layer.
- `prep_cpcad_ncc_2025.py` / `prep_cpcad_ncc_2025_terrestrial.py` -- CPCAD + NCC accomplishments source.
- `extract_species_tiffs_from_sparse_matrices.R` -- national species sparse matrices.
- `gather_habitat_data.py` -- habitat source datasets (forest, grassland, wetland, lakes, rivers, peatlands, coastline).
- `gather_indigenous_territories.py` -- downloads directly from native-land.ca.
- `8 prioritizr/` scripts -- national WTW input data, via the `wtw-data-prep2` repo.
