# Builds one landscape-resiliency-assessment PDF per row of 09_gather_and_
# write.R's final attributes table, from erap_template.html -- same pattern
# as conservation-profiles' R/06_build_profile_html.R: inject a JSON object
# into the template between its BEGIN/END_REPORT_DATA markers, write a temp
# HTML next to the template (so the fonts/ and logo relative paths resolve),
# then pagedown::chrome_print() each one to PDF.
#
# Three inputs aren't already shaped the way the template needs them:
#  - Species header counts (total/at-risk species, how many of each need
#    more protection) aren't in any existing checkpoint -- species_summary.csv
#    is grouped by Source (data provider), not by Theme, so there's no
#    ready-made SAR/non-SAR split. Computed here directly from
#    species_table.csv's per-species rows instead.
#  - actions_table.csv's own Description/Action CMP 2.0/Indicator/Trigger
#    condition/"Map viewer name" columns are a snapshot of the reference
#    table joined in at whatever 08_actions.R run last wrote the checkpoint --
#    stale the moment the reference xlsx is edited afterwards without a full
#    pipeline rerun (confirmed: the checkpoint's ABC5 description still read
#    "...not triggered by the 20% rule" after the live xlsx was updated to
#    15%, matching the ABC4 threshold fix). Only landscape_id/ID/
#    Landscape_value are kept from actions_table.csv here; every
#    human-readable field is re-joined fresh from the live reference xlsx by
#    ID, so profiles always reflect its current wording.
#  - Indigenous territories (data_prep/"12 intersect_indigenous_territories.py")
#    aren't read into this pipeline anywhere else -- read directly from its
#    own output CSV (setup.toml's new [territories] section).
#
# French localization: every build_profiles()/build_report_data() call takes
# a `lang` ("en" or "fr") that picks the right TEMPLATE_LABELS entry (the
# template's own UI chrome -- see erap_template.html's LABELS object, same
# keys) and DATA_LABELS entry (pressure/habitat display names, month names
# for generated_date). Only "en" is filled in until the translation team
# returns the French strings -- add an "fr" entry to each list below (same
# keys) to turn that build on; no other code changes needed.
PRESSURE_COLS       <- c("energy_pcnt", "forestry_pcnt", "transport_low_pcnt", "transport_high_pcnt", "agriculture_pcnt", "builtup_pcnt")
HABITAT_AREA_TYPES   <- c("forest", "grassland", "wetland", "peatlands", "lakes")
HABITAT_LINEAR_TYPES <- c("rivers", "coastline")

DATA_LABELS <- list(
  en = list(
    pressures = c(
      energy_pcnt         = "Energy and mining",
      forestry_pcnt       = "Forestry",
      transport_low_pcnt  = "Transport \u2014 lower intensity",
      transport_high_pcnt = "Transport \u2014 higher intensity",
      agriculture_pcnt    = "Agriculture",
      builtup_pcnt        = "Urban and built up"
    ),
    habitat_area = c(
      forest    = "Forest",
      grassland = "Grassland",
      wetland   = "Wetland",
      peatlands = "Peatlands",
      lakes     = "Lakes"
    ),
    habitat_linear = c(
      rivers    = "Rivers",
      coastline = "Coastline"
    ),
    months = c("January", "February", "March", "April", "May", "June",
               "July", "August", "September", "October", "November", "December")
  )
  # fr = list(...)  -- add once translations arrive, same keys as en above.
)

# TEMPLATE_LABELS' "en" entry must always mirror erap_template.html's own
# LABELS object key-for-key -- render_profile_pdf() injects whichever
# TEMPLATE_LABELS[[lang]] entry is passed to it in place of that object.
TEMPLATE_LABELS <- list(
  en = list(
    locale = "en-CA",
    eyebrow = "Landscape resiliency assessment",
    areaLabel = "Area",
    areaUnit = "ha",
    ecozoneLabel = "Ecozone(s)",
    logoAlt = "Nature Conservancy of Canada",
    footerOrg = "Nature Conservancy of Canada",
    footerGenerated = "Assessment generated",
    pageLabel1 = "Page 1/2",
    pageLabel2 = "Page 2/2",
    overviewTitle = "Overview",
    tileAreaProtected = "Area protected",
    tileWtw = "Where to Work priority",
    speciesAllTitle = "All species",
    speciesTotalLabel = "total species",
    speciesNeedProtectionLabel = "need more protection",
    speciesAtRiskTitle = "Species at risk",
    speciesAtRiskLabel = "at risk",
    intactnessTitle = "Landscape intactness",
    donutAriaTemplate = "Landscape intactness: intact {intactPct} percent, of which {protIntactPct} percent is protected; modified {modifiedPct} percent, of which {protModifiedPct} percent is protected",
    donutIntactLabel = "INTACT",
    colProtected = "Protected",
    colUnprotected = "Unprotected",
    colTotal = "Total",
    rowIntact = "Intact",
    rowModified = "Modified",
    intactHeadlineTemplate = "{pct}% of landscape is intact",
    unprotectedNone = "There is no unprotected area left in this landscape",
    unprotectedAllIntact = "Unprotected areas are all intact",
    unprotectedAllModified = "Unprotected areas are all modified",
    unprotectedMostlyIntact = "Unprotected areas are mostly intact",
    unprotectedMostlyModified = "Unprotected areas are mostly modified",
    unprotectedMix = "Unprotected areas are a mix of intact and modified land",
    pressuresTitle = "Pressures \u2014 % of landscape*",
    pressuresFootnote = "*Pressures can overlap so sums may not match modified %",
    habitatAreaTitle = "Area habitats \u2014 % of landscape cover*",
    habitatAreaFootnote = "*Habitats overlap so total % may exceed 100",
    habitatLinearTitle = "Linear habitats \u2014 total in landscape",
    habOfLandscape = "of landscape",
    habProtected = "protected",
    habWtw = "Where to Work priority",
    habLinearInLandscape = "in landscape",
    habLinearKmUnit = "km",
    actionsTitle = "Action recommendations",
    actionsEmpty = "No actions are currently recommended for this landscape.",
    territoriesTitle = "Indigenous territories",
    territoriesIntroTemplate = "List shows the % of the landscape covered by the territory, and the % of the full territory that falls in the landscape. Map data provided by {link} for educational and non-commercial use.",
    territoriesLinkText = "Native Land Digital",
    territoriesExampleTemplate = "List rows can be read as follows: {pctLandscape}% of the landscape is covered by the {name} territory, representing {pctTerritory}% of the total territory area",
    territoriesEmpty = "No Indigenous territories are recorded for this landscape in native-land.ca's dataset.",
    terrColTerritory = "Territory",
    terrColLandPct = "Land %",
    terrColTerrPct = "Terr %"
  )
  # fr = list(...)  -- add once translations arrive, same keys as en above.
)

# ECOREGION_NAME_FR is a true translation of this landscape's own name only
# when name_col is itself ECOREGION_NAME_EN (the ecoregions run) -- for
# Priority Landscapes that column instead lists the ecoregion(s) the
# landscape overlaps, so it must never stand in for the landscape's own
# name there. Priority Landscape names are the same in both languages
# (confirmed with Marc), so they fall through to landscape_id unchanged.
landscape_display_name <- function(row, lang, name_col) {
  has_fr_name <- lang == "fr" && identical(name_col, "ECOREGION_NAME_EN") &&
    !is.na(row$ECOREGION_NAME_FR) && nzchar(row$ECOREGION_NAME_FR)
  if (has_fr_name) row$ECOREGION_NAME_FR else row$landscape_id
}

# English: "November 25, 2026"; French: "25 novembre 2026" (day-month-year,
# no comma -- standard French date order, not a numeral house style).
format_generated_date <- function(date, lang) {
  month_name <- DATA_LABELS[[lang]]$months[as.integer(format(date, "%m"))]
  day  <- as.integer(format(date, "%d"))
  year <- format(date, "%Y")
  if (lang == "fr") paste0(day, " ", month_name, " ", year) else paste0(month_name, " ", day, ", ", year)
}

# "Need more protection" reuses the same per-species boolean
# summarise_species_tab() already sums per Source (Canada_Protection_Gap_km2 > 0
# OR Landscape_Protection_Gap_km2 > 0 -- a national or landscape-level
# shortfall), applied here per Theme instead: all species for the "All
# species" card, Theme == "SAR (NCC AOH)" for "Species at risk".
species_header_counts <- function(species_tab, id) {
  sub <- species_tab[species_tab$landscape_id == id, ]
  needs_protection <- sub$Canada_Protection_Gap_km2 > 0 | sub$Landscape_Protection_Gap_km2 > 0
  is_sar <- sub$Theme == "SAR (NCC AOH)"
  list(
    total                = nrow(sub),
    needProtection       = sum(needs_protection),
    atRisk               = sum(is_sar),
    atRiskNeedProtection = sum(is_sar & needs_protection)
  )
}

build_report_data <- function(row, species_tab, actions_tab, territories_tab, logo_path, generated_date, lang = "en", name_col = NULL) {
  id <- row$landscape_id
  L  <- DATA_LABELS[[lang]]

  pressures <- lapply(PRESSURE_COLS, function(col) {
    list(name = unname(L$pressures[[col]]), pct = row[[col]])
  })
  pressures <- pressures[order(-vapply(pressures, `[[`, numeric(1), "pct"))]

  habitat_area <- lapply(HABITAT_AREA_TYPES, function(hab) {
    list(
      name         = unname(L$habitat_area[[hab]]),
      coverPct     = row[[paste0("pcnt_landscape_", hab, "_cover")]],
      protectedPct = row[[paste0("pcnt_", hab, "_protected")]],
      wtwPct       = row[[paste0("pcnt_", hab, "_wtw")]]
    )
  })
  habitat_area <- habitat_area[order(-vapply(habitat_area, `[[`, numeric(1), "coverPct"))]

  habitat_linear <- lapply(HABITAT_LINEAR_TYPES, function(hab) {
    list(
      name         = unname(L$habitat_linear[[hab]]),
      km           = row[[paste0(hab, "_km")]],
      protectedPct = row[[paste0("pcnt_", hab, "_protected")]],
      wtwPct       = row[[paste0("pcnt_", hab, "_wtw")]]
    )
  })
  habitat_linear <- habitat_linear[order(-vapply(habitat_linear, `[[`, numeric(1), "km"))]

  sp <- species_header_counts(species_tab, id)

  landscape_actions <- actions_tab[actions_tab$landscape_id == id, ]
  actions <- if (nrow(landscape_actions) == 1 && landscape_actions$ID[1] == "No recommended actions") {
    list()
  } else {
    lapply(seq_len(nrow(landscape_actions)), function(i) {
      list(title = landscape_actions$`Map viewer name`[i], description = landscape_actions$Description[i])
    })
  }

  landscape_territories <- territories_tab[territories_tab$landscape_id == id, ]
  landscape_territories <- landscape_territories[order(-landscape_territories$overlap_km2, landscape_territories$NATION_NAME), ]
  territories <- lapply(seq_len(nrow(landscape_territories)), function(i) {
    list(
      name          = landscape_territories$NATION_NAME[i],
      url           = landscape_territories$NATION_URL[i],
      pctLandscape  = landscape_territories$overlap_pcnt_landscape[i],
      pctTerritory  = landscape_territories$overlap_pcnt_territory[i]
    )
  })

  ecozone_name <- if (lang == "fr") row$ECOZONE_NAME_FR else row$ECOZONE_NAME_EN

  list(
    landscapeName = landscape_display_name(row, lang, name_col),
    areaHa        = round(row$landscape_ha, 0),
    ecozone       = ecozone_name,
    logoUrl       = logo_path,
    generatedDate = generated_date,
    overview      = list(protectedPct = row$protected_pcnt, wtwPct = row$wtw_percent),
    species       = sp,
    intactness    = list(
      intactPct            = row$intact_pcnt,
      modifiedPct          = row$modified_pcnt,
      protectedIntactPct   = row$protected_intact_pcnt,
      protectedModifiedPct = row$protected_modified_pcnt
    ),
    pressures     = pressures,
    habitatArea   = habitat_area,
    habitatLinear = habitat_linear,
    actions       = actions,
    territories   = territories
  )
}

render_profile_pdf <- function(report_data, labels, output_path, template_path) {
  json_str   <- jsonlite::toJSON(report_data, auto_unbox = TRUE, pretty = TRUE)
  labels_str <- jsonlite::toJSON(labels, auto_unbox = TRUE, pretty = TRUE)
  html_text  <- paste(readLines(template_path, encoding = "UTF-8", warn = FALSE), collapse = "\n")

  html_text <- sub(
    "(?s)/\\* >>> BEGIN_REPORT_DATA[^*]*\\*/.*?/\\* >>> END_REPORT_DATA <<< \\*/",
    paste0("/* >>> BEGIN_REPORT_DATA (pipeline replaces this object) <<< */\nconst REPORT_DATA = ",
           json_str,
           ";\n/* >>> END_REPORT_DATA <<< */"),
    html_text,
    perl = TRUE
  )
  html_text <- sub(
    "(?s)/\\* >>> BEGIN_LABELS[^*]*\\*/.*?/\\* >>> END_LABELS <<< \\*/",
    paste0("/* >>> BEGIN_LABELS (pipeline replaces this object) <<< */\nconst LABELS = ",
           labels_str,
           ";\n/* >>> END_LABELS <<< */"),
    html_text,
    perl = TRUE
  )

  # Write next to the template so its relative fonts/ and logo paths resolve.
  tmp_html <- tempfile(fileext = ".html", tmpdir = normalizePath(dirname(template_path), mustWork = FALSE))
  on.exit(unlink(tmp_html), add = TRUE)
  writeLines(html_text, tmp_html, useBytes = TRUE)

  # --no-sandbox: Chrome/Edge's sandbox needs OS-level process isolation
  # that's often blocked under a restricted server/service account, which
  # otherwise crashes the render process mid-print (surfaces as a WebSocket
  # connection reset, not a clean error) -- same flag conservation-profiles
  # uses for the same reason.
  pagedown::chrome_print(
    tmp_html,
    output = normalizePath(output_path, mustWork = FALSE),
    wait = 5,
    extra_args = c("--disable-gpu", "--no-sandbox")
  )
}

# lang selects both label sets above and the output subfolder
# (profiles_dir/eng or profiles_dir/fr) and logo (cfg$report$logo_path vs
# logo_path_fr), so an "en" and an "fr" build never collide or mix text.
build_profiles <- function(cfg, final_tab, species_tab, actions_tab, lang = "en") {
  print(paste0("10 build profiles (", lang, ")..."))

  template_path <- cfg$report$template_path
  logo_path     <- if (lang == "fr") cfg$report$logo_path_fr else cfg$report$logo_path
  profiles_dir  <- file.path(cfg$report$profiles_dir, if (lang == "fr") "fr" else "eng")
  if (!dir.exists(profiles_dir)) dir.create(profiles_dir, recursive = TRUE)

  # Falls back to the English reference columns when the French ones don't
  # exist yet in the actions xlsx (translation pending) -- picks them up
  # automatically once Marc adds "Map viewer name (FR)"/"Description (FR)",
  # no code change needed then.
  actions_ref_raw <- readxl::read_excel(cfg$actions$actions_reference_path)
  title_col <- if (lang == "fr" && "Map viewer name (FR)" %in% names(actions_ref_raw)) "Map viewer name (FR)" else "Map viewer name"
  desc_col  <- if (lang == "fr" && "Description (FR)"    %in% names(actions_ref_raw)) "Description (FR)"    else "Description"
  actions_ref <- actions_ref_raw[, c("ID", title_col, desc_col)]
  names(actions_ref) <- c("ID", "Map viewer name", "Description")
  actions_tab <- actions_tab[, c("landscape_id", "ID", "Landscape_value")] |>
    dplyr::left_join(actions_ref, by = "ID")

  territories_tab <- readr::read_csv(cfg$territories$territories_path, show_col_types = FALSE)
  names(territories_tab)[names(territories_tab) == cfg$landscape$name_col] <- "landscape_id"

  generated_date <- format_generated_date(Sys.Date(), lang)
  labels         <- TEMPLATE_LABELS[[lang]]

  for (i in seq_len(nrow(final_tab))) {
    row <- final_tab[i, ]
    print(paste0("  ", i, "/", nrow(final_tab), ": ", row$landscape_id))
    report_data <- build_report_data(row, species_tab, actions_tab, territories_tab, logo_path, generated_date, lang, cfg$landscape$name_col)
    # Transliterate accented characters (e.g. french landscape names) to their
    # closest ascii equivalent before stripping -- otherwise every accent
    # becomes a bare underscore instead of the letter it replaces.
    safe_name   <- iconv(row$landscape_id, from = "UTF-8", to = "ASCII//TRANSLIT")
    # A " - " separator (e.g. Priority Landscapes' "BC - Northwest" region
    # prefix) collapses to one underscore instead of "_-_" -- a bare
    # compound-word hyphen with no surrounding space (e.g. ecoregions'
    # "Algonquin-Lake Nipissing") is untouched, since \\s+ requires space on
    # both sides.
    safe_name   <- gsub("\\s+-\\s+", "_", safe_name)
    safe_name   <- gsub("[^A-Za-z0-9_-]+", "_", safe_name)
    output_path <- file.path(profiles_dir, paste0(safe_name, ".pdf"))
    render_profile_pdf(report_data, labels, output_path, template_path)
  }
}
