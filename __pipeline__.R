# Entry point -- run directly from the repo root, once per landscape set.
# Change toml_path below and re-run (e.g. source()'d line by line, or the
# whole file) to switch between the two landscape sets.
#
# Every source()
# path below is relative to the repo root.

start_time <- Sys.time()

# toml_path <- "setup_ecoregions.toml"
toml_path <- "setup_priority_landscapes.toml"

source("R/01_setup.R")
print("01 setup...")
cfg <- setup(toml_path)

source("R/02_load_landscapes.R")
landscapes <- load_landscapes(cfg)

source("R/03_protected_intactness.R")
protected_intactness_tab <- protected_intactness(cfg, landscapes)
readr::write_csv(protected_intactness_tab, file.path(cfg$landscape$processing_dir, "protected_intactness.csv"))
# protected_intactness_tab <- readr::read_csv(file.path(cfg$landscape$processing_dir, "protected_intactness.csv"))

source("R/04_habitat.R")
habitat_tab <- habitat(cfg, landscapes)
readr::write_csv(habitat_tab, file.path(cfg$landscape$processing_dir, "habitat_table.csv"))
# habitat_tab <- readr::read_csv(file.path(cfg$landscape$processing_dir, "habitat_table.csv"))

source("R/05_pressures.R")
pressures_tab <- pressures(cfg, landscapes)
readr::write_csv(pressures_tab, file.path(cfg$landscape$processing_dir, "pressures_table.csv"))
# pressures_tab <- readr::read_csv(file.path(cfg$landscape$processing_dir, "pressures_table.csv"))

source("R/06_wtw.R")
wtw_tab <- wtw(cfg, landscapes)
readr::write_csv(wtw_tab, file.path(cfg$landscape$processing_dir, "wtw_table.csv"))
# wtw_tab <- readr::read_csv(file.path(cfg$landscape$processing_dir, "wtw_table.csv"))

source("R/fct_build_species_tab.R")
source("R/07_species.R")
species_out <- species(cfg, landscapes)
readr::write_csv(species_out$species_tab,     file.path(cfg$landscape$processing_dir, "species_table.csv"))
readr::write_csv(species_out$species_summary, file.path(cfg$landscape$processing_dir, "species_summary.csv"))
# species_out <- list(
#   species_tab     = readr::read_csv(file.path(cfg$landscape$processing_dir, "species_table.csv")),
#   species_summary = readr::read_csv(file.path(cfg$landscape$processing_dir, "species_summary.csv"))
# )

source("R/08_actions.R")
actions_out <- actions(cfg, landscapes, protected_intactness_tab, wtw_tab, species_out$species_tab)
readr::write_csv(actions_out$actions_long, file.path(cfg$landscape$processing_dir, "actions_table.csv"))
readr::write_csv(actions_out$actions_wide, file.path(cfg$landscape$processing_dir, "actions_summary.csv"))
# actions_out <- list(
#   actions_long = readr::read_csv(file.path(cfg$landscape$processing_dir, "actions_table.csv")),
#   actions_wide = readr::read_csv(file.path(cfg$landscape$processing_dir, "actions_summary.csv"))
# )

source("R/09_gather_and_write.R")
final_tab <- gather_and_write(cfg, landscapes, protected_intactness_tab, habitat_tab, pressures_tab, wtw_tab, actions_out$actions_wide)

end_time <- Sys.time()
print(end_time - start_time)
