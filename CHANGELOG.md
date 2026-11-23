# Changelog

## v0.2 release - 2026-11-20

### Structural code changes

- Rebuilt from 19 loosely-coupled scripts with hardcoded absolute paths into
  a toml-config-driven pipeline: `setup.toml` for all paths, numbered step
  scripts (`01_setup.R` .. `09_gather_and_write.R`) + `fct_` helpers, one
  entry point (`__pipeline__.R`), matching the `conservation-profiles`
  pattern.
- Pipeline now runs over two landscape sets -- ecoregions and Priority
  Landscapes -- via two `setup.toml` files (`setup_ecoregions.toml` /
  `setup_priority_landscapes.toml`), producing two outputs with an
  identical schema. Code uses generic "landscape" terminology throughout,
  not "ecoregion"/"boundary".
- New `landscape_id` column is the universal per-run join key across every
  step's checkpoint CSV, replacing `ECOREGION_ID` as the internal join key.
- Reused functions from `conservation-profiles`: `fct_read_feature.R`,
  `fct_read_raster.R` (verbatim); `build_species_stack()` (verbatim),
  `load_species_meta()`/`summarise_species_tab()` (adapted).
  `fct_intersect_vector_value.py`'s `intersect_vector_value()` rewritten as
  a bulk-pass function (`intersect_vector_values()`), plus a new
  `intersect_vector_geoms()` for callers needing the clipped geometry
  itself. A parallel bulk raster helper, `intersect_raster_values()`
  (`R/fct_intersect_raster_value.R`), does the same for rasters. Porting
  these back into `conservation-profiles` is tracked in
  `CONSERVATION_PROFILES_CHANGES.md`.
- Species raster prep (`5a`) referenced via `setup.toml` as a pre-generated
  input. The prioritizr optimization chain lives in-repo under
  `data_prep/8 prioritizr/`, feeding `ERAPs_v2` for `setup.toml` to
  reference.
- New `data_prep/` folder for one-time GIS prep scripts that run before the
  pipeline: ecoregions (CTEF v2.2), Priority Landscapes x ecoregions
  overlap attribution, CPCAD+NCC 2025 (unclipped and terrestrial-clipped),
  species tif extraction + metadata filtering + protected-area
  recalculation, the WTW erase, habitat source gathering, and Indigenous
  Territories x ecoregions/Priority Landscapes intersection. Generated GIS
  outputs live outside the repo (`C:/Users/marc.edwards/Documents/PROJECTS/ERAPs_v2`).
- Every numbered step reads its own `setup.toml` inputs + the step-02
  landscape table, writes one checkpoint CSV to `processing_dir`, and can
  be re-run independently.
- Dropped from this pass: `5b`/`5d` species QA checks;
  `8_clip_data_for_pdf_maps.py`; `fct_init_metadata.R`/`fct_sci_to_common.R`
  (unused). `fct_calculate_targets.R` is still used directly by
  `data_prep` scripts.
- `6_action_recommendations.R` ported as `R/08_actions.R`, generic over
  `landscape_id` (both landscape sets). Two new checkpoint CSVs per run
  (`actions_table.csv` long, `actions_summary.csv` wide). `actions_summary.csv`
  is joined into `09_gather_and_write.R`'s table; `actions_table.csv` is
  not, same as species.
  - `ABC2`/`ABC3` count SAR species only (Critical Habitat is no longer
    tracked; only the `SAR (NCC AOH)` theme survives).
  - `REST1`/`REST2` recomputed from `intact_km2`/`modified_km2`/
    `protected_intact_km2`/`protected_modified_km2`/`landscape_km2`/
    `protected_km2`, keeping both triggers' definitions and 30% thresholds
    unchanged from the legacy script.
  - `STEW1`/`PARTNER1` use NCC's fee-simple(+CA) properties as their own
    layer -- `data_prep/"3 prep_cpcad_ncc_2025.py"` persists
    `ncc_fs_ca_2025_dslv` (fee simple + conservation agreement) and
    `ncc_fs_2025_dslv` (fee simple only) (`setup.toml`'s new
    `ncc_fs_ca_path`/`ncc_fs_path`).
  - `ABC1`, `ABC4`, `ABC5` ported onto existing columns (`protected_pcnt`,
    `wtw_percent`, `wtw_area_km2`) unchanged.
  - New reference table `tables/ERAP Action recommendation reference.xlsx`
    (action ID -> CMP 2.0 action, description, indicator, trigger
    condition), checked into this repo (`setup.toml`'s new
    `[actions].actions_reference_path`).

### Output table & calculation changes

- `wtw_percent` redefined as % of the whole landscape (`wtw_area_km2 /
  landscape_km2 * 100`), not % of the unprotected remainder.
  `wtw_area_km2` comes from intersecting `wtw_erased_protected` (WTW
  solution, CPCAD+NCC erased) against each landscape, replacing raster
  zonal stats against the un-erased solution. No `includes_km2` column.
- **`erap-deer-code#29`**: `unprotected_intact_pcnt`/`unprotected_modified_pcnt`
  replaced with four full-landscape figures -- `intact_pcnt`,
  `modified_pcnt`, `protected_intact_pcnt`, `protected_modified_pcnt` --
  all sharing one denominator, `intact_km2 + modified_km2`. New raw-area
  columns `intact_km2`, `modified_km2`, `protected_intact_km2`,
  `protected_modified_km2` also land in the output table.
- Collapsed the `ecoregion` vs. `ecoregion_inland` duplication to a single
  reference landscape polygon (the land-clipped one) -- dropped the
  full-extent-only columns: `ecoregion_km2`, `protected_km2` (full),
  `protected_pcnt` (full), `wtw_area_km2` (full), `wtw_percent` (full).
- Column renames from the single-polygon collapse + generic landscape
  terminology: `ecoregion_inland_km2` -> `landscape_km2`;
  `protected_inland_km2`/`_pcnt` -> `protected_km2`/`_pcnt`;
  `wtw_area_inland_km2` -> `wtw_area_km2`; `wtw_inland_percent` ->
  `wtw_percent`; `pcnt_ecoregion_forest/grassland/wetland/lakes_cover` ->
  `pcnt_landscape_..._cover`.
- Habitat type renamed: `shoreline` -> `coastline` (`habitat_shoreline` ->
  `habitat_coastline`, `shoreline_km` -> `coastline_km`, etc.) -- underlying
  dataset changed from `shoreline_merge` to CanCoast.
- Forest/grassland/wetland habitat sums now intersect the same land-clipped
  (terrestrial) landscape polygon lakes/rivers already use (previously the
  full extent).
- Coastline is the one habitat type that does not use the terrestrial
  landscape polygon: every landscape now has a second, marine-buffered
  polygon, and coastline cover (`coastline_km`) plus coastline's own
  protected/WTW overlap (`coastline_protected_km`/`coastline_wtw_km`) all
  intersect against that marine polygon instead. Applies to coastline only.
- Dropped the second rivers dataset (`rivers_1M_*`) -- only one rivers
  dataset (matching `conservation-profiles`' `habitat_rivers`) is carried
  forward.
- New habitat type: `peatlands` (vector, `habitat_peatlands`) -- same
  cover-type pattern as forest/grassland/wetland/lakes
  (`peatlands_km2`/`pcnt_landscape_peatlands_cover`, its own
  `pcnt_peatlands_protected`/`pcnt_peatlands_wtw`).
- Species: `Canada_Protected_km2` (and the `Canada_Protection_Gap_km2` it
  drives) now prefers `Protected_Km2_vector`/CPCAD-vector-recalculated
  protected area over the original 1km-grid-based `Protected_Km2`, per row,
  where available (`data_prep/"7 recalc_species_protected_km2.R"`).
- Dropped `protection_goal` and `wtw_eco_pcnt` from scope.
- Action-recommendation columns (`ABC1-5`, `STEW1`, `REST1-2`, `PARTNER1`,
  `ABC_count`, `Restoration_count`) are in the main attributes table via
  `R/08_actions.R`'s `actions_summary.csv` checkpoint.
- New `landscape_id` column, always populated in both runs.
- Ecoregions/ecozones data source switched to the Canadian Terrestrial
  Ecological Framework (CTEF) v2.2, replacing the old source shapefile.
  Six identity columns renamed repo-wide: `ECOREGION` -> `ECOREGION_ID`,
  `REGION_NAM` -> `ECOREGION_NAME_EN`, `REGION_NOM` -> `ECOREGION_NAME_FR`,
  `ECOZONE` -> `ECOZONE_ID`, `ZONE_NAME` -> `ECOZONE_NAME_EN`, `ZONE_NOM` ->
  `ECOZONE_NAME_FR`.
- `ECOREGION_ID`/`ECOREGION_NAME_EN`/`ECOREGION_NAME_FR`/`ECOZONE_ID`/
  `ECOZONE_NAME_EN`/`ECOZONE_NAME_FR` now populated via spatial overlap
  against the ecoregions layer in the Priority Landscapes run,
  `/`-joined where a landscape spans more than one ecoregion or ecozone.
  Sliver fragments from boundary misalignment between the two
  independently-digitized layers are excluded (`perim_per_area_km >= 3.0`).
- Hectares conversion: every `*_km2` column becomes `*_ha` (x 100) in the
  final assembly step; length columns (`rivers_km`, `coastline_km`) stay in
  km, unconverted.
- One unified schema now drives two separate output products:
  `ERAP_ecoregions` and `ERAP_priority_landscapes`.
- Adopted rounding conventions from the data alignment project
  ([erap-deer-code#23](https://github.com/NCC-CNC/erap-deer-code/issues/23)):
  no rounding on intermediate values, final output tables round every value
  (ha/km/%) to 2 decimal places.
- Output attributes are now joined to the terrestrial version of the 
ecoregions and Priority Landscapes.
