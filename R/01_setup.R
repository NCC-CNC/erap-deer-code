# Installs any missing R packages, reads setup.toml, and points reticulate
# at the ArcGIS Pro python environment (arcgis_config.toml) for the
# arcpy-based vector intersections in R/fct_intersect_vector_value.py.
#
# Single-user repo -- no CODE_DIR indirection (unlike conservation-profiles,
# which shares its codebase across many per-project folders). Every
# source()/path in this pipeline is relative to the repo root, since
# __pipeline__.R is always run directly from there. Ports 0_initiate_project.R's
# folder-creation job, pointed at setup.toml's own output_dir/processing_dir
# (external, outside the repo) instead of a hardcoded local "processing"/"output".
setup <- function(toml_path) {
  required_pkgs <- c(
    "dplyr",
    "tidyr",
    "RcppTOML",
    "readr",
    "readxl",
    "sf",
    "terra",
    "exactextractr",
    "reticulate",
    "stringr",
    "openxlsx",
    "tibble",
    "jsonlite",
    "pagedown"
  )

  for (pkg in required_pkgs) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      message(sprintf("Installing %s...", pkg))
      install.packages(pkg, repos = "https://cloud.r-project.org")
    }
  }

  terra::gdalCache(size = 8000) # after install, terra may not exist yet on a fresh system

  cfg <- RcppTOML::parseTOML(toml_path)

  if (!dir.exists(cfg$landscape$output_dir))     dir.create(cfg$landscape$output_dir, recursive = TRUE)
  if (!dir.exists(cfg$landscape$processing_dir)) dir.create(cfg$landscape$processing_dir, recursive = TRUE)

  arcgis_cfg <- RcppTOML::parseTOML("arcgis_config.toml")
  reticulate::use_python(arcgis_cfg$python_path)
  reticulate::source_python("R/fct_intersect_vector_value.py", envir = globalenv())
  set_output_projection(cfg$habitat_raster$habitat_forest)

  cfg
}
