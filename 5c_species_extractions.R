# Extract species area for each ecoregion and calculate shortfall
# Ecoregion goals are set to match the national % goal for every species that
# has range in the ecoregion

# Nice alignment with understanding of WTW here. The shortfalls are exactly
# what WTW is using during the prioritization

start_time <- Sys.time()


# prep -------------------------------------------------------------------

# Load packages
library(sf)
library(terra)
library(exactextractr)
library(tidyr)
library(dplyr)
library(readr)
library(readxl)
library(openxlsx)

# prep -------------------------------------------------------------------

# create output folder
if(!dir.exists("processing/species/output_csv")){
  dir.create("processing/species/output_csv")
}
if(!dir.exists("output/species_tables")){
  dir.create("output/species_tables")
}

# Load PAs
pa <- st_read("C:/Users/marc.edwards/Documents/gisdata/protected_areas_2024/ProtectedConservedArea.gdb","cpcad_ncc_dslv_july2024")

# Load ecoregions and subset by those we want to include in ERAPs
ecozone_list <- c(4,5,6,7,8,9,10,11,12,13,14,15)
ecoregions <- st_read("C:/Users/marc.edwards/Documents/gisdata/national_ecological_framework/Ecoregions/ecoregions_albers_dslv.shp") %>%
  filter(ECOZONE %in% ecozone_list) # filter to the ecozone we ran prioritizr on

### open meta data and merge worksheets ###
input_data_path <- "C:/Data/PRZ/WTW_DATA/WTW_NAT_DATA_20240522"
species_meta_path <- file.path(input_data_path, "WTW_NAT_SPECIES_METADATA.xlsx")

tibbles <- list()
for(sheet in excel_sheets(species_meta_path)){
  df <- read_excel(species_meta_path, sheet) %>%
    select(c("Source", "File", "Theme", "Sci_Name", "Common_Name", "Threat", "Total_Km2", "Protected_Km2", "Pct_Protected", "Goal"))
  tibbles[[sheet]] <- df
}
# Rename some columns and calculate shortfall (calling this protection gap for clarity)
species_meta <- bind_rows(tibbles)
names(species_meta)[names(species_meta) == "Total_Km2"] <- "Canada_Total_km2"
names(species_meta)[names(species_meta) == "Protected_Km2"] <- "Canada_Protected_km2"
names(species_meta)[names(species_meta) == "Pct_Protected"] <- "Canada_Pct_Protected"
names(species_meta)[names(species_meta) == "Goal"] <- "Canada_Pct_Goal"
species_meta$Canada_Pct_Goal <- species_meta$Canada_Pct_Goal * 100
species_meta$Canada_km2_Goal <- species_meta$Canada_Total_km2 * (species_meta$Canada_Pct_Goal/100)
species_meta$Canada_Protection_Gap_km2 <- species_meta$Canada_km2_Goal - species_meta$Canada_Protected_km2
species_meta$Canada_Protection_Gap_km2[species_meta$Canada_Protection_Gap_km2 < 0] <- 0



# processing -------------------------------------------------------------------

# Get list of ecoregions to process
ecoregion_list <- unique(ecoregions$ECOREGION)

for(ecoregion in ecoregion_list){
  
  print(ecoregion)
  
  # get ecozone value
  ecozone <- unique(ecoregions$ECOZONE[ecoregions$ECOREGION == ecoregion])
  
  # get ecoregion polygon
  eco_sf <- ecoregions[ecoregions$ECOREGION == ecoregion,]
  
  # get list of species file names for all species in the ecozone. Can get this from the national prioritizr ecozone data prep
  # this reduces the number of intersections we need to do
  # Skip this if the national prioritizr data prep is not available - just use the full list or all files in the Tiffs folder
  files <- list.files(file.path("processing/prioritizr/ecozones/", ecozone, "Tiffs"), pattern = "^T_.*.tif$")
  
  # convert paths to the national version of these files
  files <- file.path("processing/species/Tiffs", files)
  
  # drop NSC_SAR to match Dan's LandR layers
  files <- files[!grepl("NSC_SAR", files)]
  
  # load all tiffs 
  sp_all <- rast(files)
  names(sp_all) <- basename(sources(sp_all))
  
  # extract values for ecoregion
  df_eco <- exactextractr::exact_extract(sp_all, eco_sf, 'sum') %>%
    pivot_longer(
      cols = colnames(.),
      names_to = "species",
      values_to = "Ecoregion_Total_km2"
    )
  
  # extract values for PA
  eco_pa_sf <- st_intersection(pa, eco_sf) # get polygons of all PAs in the ecoregion
  df_pa <- exactextractr::exact_extract(sp_all, st_union(eco_pa_sf), 'sum') %>%
    pivot_longer(
      cols = colnames(.),
      names_to = "species",
      values_to = "Ecoregion_Protected_km2"
    )
  
  # join ecoregions and pa sums, drop species with no coverage
  df <- left_join(df_eco, df_pa, by = join_by(species == species)) %>%
    filter(Ecoregion_Total_km2 > 0)
  
  # If no protected areas in ecoregion, all Ecoregion_Protected_km2 get set to NA. Convert these to zeros
  df$Ecoregion_Protected_km2[is.na(df$Ecoregion_Protected_km2)] <- 0
  
  # remove .sum from names
  df$species <- gsub('^sum.', '', df$species)
  
  # convert ECCC data from ha to km2
  df$Ecoregion_Total_km2[grepl('^T_NAT_ECCC', df$species)] <- df$Ecoregion_Total_km2[grepl('^T_NAT_ECCC', df$species)] / 100
  df$Ecoregion_Protected_km2[grepl('^T_NAT_ECCC', df$species)] <- df$Ecoregion_Protected_km2[grepl('^T_NAT_ECCC', df$species)] / 100
  
  # join national info from meta data table and add ecoregion specific columns
  out_df <- inner_join(species_meta, df, by = join_by(File == species)) %>%
    mutate(
      Ecoregion_Goal_km2 = (Canada_Pct_Goal/100) * Ecoregion_Total_km2,
      Ecoregion_Protection_Gap_km2 = Ecoregion_Goal_km2 - Ecoregion_Protected_km2,
      Ecozone = ecozone,
      Ecoregion = ecoregion,
      Pct_Canada_range_in_ecoregion = round((Ecoregion_Total_km2 / Canada_Total_km2) * 100, 1)
    )
  out_df$Ecoregion_Protection_Gap_km2[out_df$Ecoregion_Protection_Gap_km2 < 0] <- 0
  out_df$Pct_Canada_range_in_ecoregion[out_df$Pct_Canada_range_in_ecoregion > 100] <- 100 # set any values above 100% to 100% - but see 5d_species_table_checks.R to catch bugs
    
  # reorder columns
  out_df <- out_df[, c("Ecozone",
                       "Ecoregion",
                       "Source", 
                       "File", 
                       "Theme", 
                       "Sci_Name", 
                       "Common_Name", 
                       "Threat", 
                       "Canada_Total_km2", 
                       "Canada_Protected_km2", 
                       "Canada_Pct_Goal", 
                       "Canada_km2_Goal", 
                       "Canada_Protection_Gap_km2", 
                       "Ecoregion_Total_km2", 
                       "Ecoregion_Goal_km2",
                       "Ecoregion_Protected_km2",
                       "Ecoregion_Protection_Gap_km2",
                       "Pct_Canada_range_in_ecoregion")]
  
  # round
  out_df[c(9:17)] <- round(out_df[c(9:17)], 2)
  
  # save csv
  write_csv(out_df, file.path("output_csv", paste0("species_assessment_ecozone_", ecozone, "_ecoregion_", ecoregion, ".csv")))
  

  # save excel version with a different worksheet for each species group
  #out_df <- read_csv(file.path("output_csv", paste0("species_assessment_ecozone_", ecozone, "_ecoregion_", ecoregion, ".csv"))) # can use this line to run the code below without having to re-calc all csv tables
  
  # Create a summary table to be the first worksheet
  summary_tib <- out_df %>%
    group_by(Source) %>%
    summarise(
      "Count of species datasets" = n(),
      "Count of species datasets with Canada-wide protection gap" = sum(Canada_Protection_Gap_km2 > 0),
      "Count of species datasets with ecoregion protection gap" = sum(Ecoregion_Protection_Gap_km2 > 0),
      "Count of species datasets with >99% of range in ecoregion, and ecoregion protection gap" = sum((Pct_Canada_range_in_ecoregion > 99) & (Ecoregion_Protection_Gap_km2 > 0)),
      "Count of species datasets with 50-99% of range in ecoregion, and ecoregion protection gap" = sum((Pct_Canada_range_in_ecoregion > 50 & Pct_Canada_range_in_ecoregion < 99) & (Ecoregion_Protection_Gap_km2 > 0))
    ) %>%
    pivot_longer(cols = colnames(.[2:6])) %>%
    pivot_wider(names_from = Source, values_from = value) %>%
    mutate(Total = rowSums(.[3:ncol(.)]))
  names(summary_tib)[names(summary_tib) == "name"] <- ""
  
  source_list <- unique(species_meta$Source) # start with meta data list to make sure order is always the same
  source_list <- source_list[source_list %in% unique(out_df$Source)] # subset by the source's that occur in the ecoregion
  
  sheet_list <- list()
  sheet_list[["Summary"]] <- summary_tib # summary should be the first worksheet
  for(s in source_list){
    sheet_list[[s]] <- out_df[out_df$Source == s,] # add all other worksheets in order
  }
  write.xlsx(sheet_list, file.path("output/species_tables", paste0("species_assessment_ecozone_", ecozone, "_ecoregion_", ecoregion, ".xlsx")))
}


Sys.time() - start_time

