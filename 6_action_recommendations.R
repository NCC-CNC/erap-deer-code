# create table of action recommendations based on ERAP data
# logic for making recommendations matches the Action_recommendation_reference.xlsx

library(tidyverse)
library(sf)
library(readxl)

rm(list = ls(all.names = TRUE))
gc()

# Get list of ecoregions
ecozone_list <- c(4,5,6,7,8,9,10,11,12,13,14,15)
ecoregions <- st_read("C:/Users/marc.edwards/Documents/gisdata/national_ecological_framework/Ecoregions/ecoregions_albers_dslv.shp") %>%
  filter(ECOZONE %in% ecozone_list) # filter to the ecozone we ran prioritizr on

# Generate a table of CH and SAR shortfall counts by extracting the values from the summary tab for each ecoregions species table
shortfall_df <- tibble(ECOREGION = as.numeric(), CH_99 = as.numeric(), CH_50_99 = as.numeric(), SAR_99 = as.numeric(), SAR_50_99 = as.numeric())
for(f in list.files("output/species_tables/", full.names = TRUE)){
  df <- read_excel(f, sheet = 1)
  
  shortfall_df <- rbind(shortfall_df,
                        tibble(ECOREGION = as.numeric(str_replace(strsplit(f, "_ecoregion_")[[1]][2], ".xlsx", "")),
                               CH_99 = ifelse(is.null(df$ECCC_CH[4]), 0, df$ECCC_CH[4]),
                               CH_50_99 = ifelse(is.null(df$ECCC_CH[5]), 0, df$ECCC_CH[5]),
                               SAR_99 = ifelse(is.null(df$ECCC_SAR[4]), 0, df$ECCC_SAR[4]),
                               SAR_50_99 = ifelse(is.null(df$ECCC_SAR[5]), 0, df$ECCC_SAR[5])
                        ))
}

# Load actions table
actions <- read_excel("C:/Users/marc.edwards/Documents/Github/erap_code/tables/ERAP Action recommendation reference.xlsx")

# load tables
protected <- read_csv("processing/protected_intact_modified/protected_intact_modified.csv")
wtw <- read_csv("processing/prioritizr/ecozones/Canada_wtw_2024_ecoregion_proportions.csv")

# Calc area of NCC fs+ca and fs in each ecoregion
fs_ca <- st_read("C:/Users/marc.edwards/Documents/gisdata/protected_areas_2024/accomp.gdb", "filtered_fs_ca")
fs <- st_read("C:/Users/marc.edwards/Documents/gisdata/protected_areas_2024/accomp.gdb", "filtered_fs")


# Set up recommendation functions - return TRUE if action is recommended

abc1 <- function(x){
  # Trigger: current protection <30%
  return(x < 30)
}
abc2 <- function(x){
  # Trigger: Count of SAR with national protection shortfall and >99% of range in the ecoregion > 0
  return(x > 0)
}
abc3 <- function(x){
  # Trigger: Count of SAR with national protection shortfall and 50-99% of range in the ecoregion >= 5
  return(x >= 5)
}
abc4 <- function(x){
  # Trigger: Percent of ecoregion overlapping national Where to Work solution > 20%
  return(x > 20)
}
abc5 <- function(x){
  # Trigger: Area in ecoregion overlapping national Where to Work solution > 10,000 km2
  return(x > 10000)
}
stew1 <- function(x){
  # Trigger: Area of NCC fee-simple or CA properties > 0 km2
  return(x > 0)
}
rest1 <- function(x){
  # Trigger: Percent of ecoregion classed as currently protection or unprotected intact land < 30%
  return(x < 30)
}
rest2 <- function(x){
  # Trigger: Unprotected modified land >=30%
  return(x >= 30)
}
partner1 <- function(x){
  # Trigger: Area of NCC fee-simple land > 0km2
  return(x > 0)
}

# Prep output table to be filled
actions_out <- tibble(ECOREGION = as.numeric(),
                      ID = as.character(),
                      ECOREGION_Value = as.numeric()
)
for(eco in ecoregions$ECOREGION){
  
  eco_actions <- tibble(ECOREGION = as.numeric(),
                        ID = as.character(),
                        ECOREGION_Value = as.numeric())
  
  # Get ecoregion shape, NCC properties
  eco_sf <- ecoregions[ecoregions$ECOREGION == eco,] %>% st_union()
  # intersect ecoregion with Fee-simple and CA properties and calc area
  eco_fs_ca_sf <- st_intersection(fs_ca, eco_sf) %>% st_union()
  # intersect ecoregion with Fee-simple properties and calc area
  eco_fs_sf <- st_intersection(fs, eco_sf) %>% st_union()
  
  # Prep values to go into functions
  current_protection <- protected$protected_inland_pcnt[protected$ECOREGION == eco]
  
  SAR_99 <- max(c(shortfall_df$SAR_99[shortfall_df$ECOREGION == eco], shortfall_df$CH_99[shortfall_df$ECOREGION == eco])) # SAR or CH > 0
  SAR_50_99 <- shortfall_df$SAR_50_99[shortfall_df$ECOREGION == eco] # SAR > 5 (there are no ecoregions where CH > 5 and SAR < 5)
  
  wtw_inland_pcnt <- wtw$wtw_inland_percent[wtw$ECOREGION == eco]
  wtw_km2 <- wtw$wtw_area_km2[wtw$ECOREGION == eco]
  
  eco_fs_ca <- sum(as.numeric(st_area(eco_fs_ca_sf)))/1000000
  
  protected_intact_pcnt <- (protected$protected_inland_km2[protected$ECOREGION == eco] + # terrestrial protection... plus ....
                              ((protected$ecoregion_inland_km2[protected$ECOREGION == eco] - protected$protected_inland_km2[protected$ECOREGION == eco]) # terrestrial unprotected...
                               * (protected$unprotected_intact_pcnt[protected$ECOREGION == eco]/100)) # ... multiplied by % of unprotected land that is intact....to get estimate of intact unprotected areas
  ) / protected$ecoregion_inland_km2[protected$ECOREGION == eco] * 100 # all divided by the total terrestrial area to get % that could potentially be protected and intact
  
  unprotected_modified <- protected$unprotected_modified_pcnt[protected$ECOREGION == eco]
  
  eco_fs <- sum(as.numeric(st_area(eco_fs_sf)))/1000000
  
  # abc 1
  if(abc1(current_protection)){
    eco_actions <- rbind(eco_actions, tibble(ECOREGION = eco,
                                             ID = "ABC1",
                                             ECOREGION_value = current_protection))
  }
  # abc 2
  if(abc2(SAR_99)){
    eco_actions <- rbind(eco_actions, tibble(ECOREGION = eco,
                                             ID = "ABC2",
                                             ECOREGION_value = SAR_99))
  }
  # abc 3
  if(abc3(SAR_50_99)){
    eco_actions <- rbind(eco_actions, tibble(ECOREGION = eco,
                                             ID = "ABC3",
                                             ECOREGION_value = SAR_50_99))
  }
  # abc 4
  if(abc4(wtw_inland_pcnt)){
    eco_actions <- rbind(eco_actions, tibble(ECOREGION = eco,
                                             ID = "ABC4",
                                             ECOREGION_value = wtw_inland_pcnt))
  }
  # abc 5
  if(abc5(wtw_km2)){
    eco_actions <- rbind(eco_actions, tibble(ECOREGION = eco,
                                             ID = "ABC5",
                                             ECOREGION_value = wtw_km2))
  }
  # stew 1
  if(stew1(eco_fs_ca)){
    eco_actions <- rbind(eco_actions, tibble(ECOREGION = eco,
                                             ID = "STEW1",
                                             ECOREGION_value = eco_fs_ca))
  }
  # rest 1
  # Need to calc existing protection + intact unprotected area. 2 options for calculating intact unprotected area:
  # 1) Use the intact area from HM that intersects the inland ecoregion. This will often under estimate % value because some areas of the inland ecoregion polygon (along coasts) are not covered by HM raster.
  # 2) Multiply the % intact value by the unprotected inland area. intact value calculated as the ratio of intact to modified land for all unprotected HM pixels in the inland ecoregion polygon. 
  #    This approach essentially extrapolates the known ratio across the full area. Likely under estimates intact land because I'd assume coastal lands are more likely to be intact than modified.
  # Using option 2 for now.
  if(rest1(protected_intact_pcnt)){
    eco_actions <- rbind(eco_actions, tibble(ECOREGION = eco,
                                             ID = "REST1",
                                             ECOREGION_value = protected_intact_pcnt))
  }
  # rest 2
  if(rest2(unprotected_modified)){
    eco_actions <- rbind(eco_actions, tibble(ECOREGION = eco,
                                             ID = "REST2",
                                             ECOREGION_value = unprotected_modified))
  }
  # partner 1
  if(partner1(eco_fs)){
    eco_actions <- rbind(eco_actions, tibble(ECOREGION = eco,
                                             ID = "PARTNER1",
                                             ECOREGION_value = eco_fs))
  }
  # partner 2
  # if any actions have been recommended, add partnerships 2. Otherwise return 'no actions are recommended'.
  if(nrow(eco_actions) == 0){
    eco_actions <- rbind(eco_actions, tibble(ECOREGION = eco,
                                             ID = "No recommended actions",
                                             ECOREGION_value = NA))
  }
  
  # merge with master table
  actions_out <- rbind(actions_out, eco_actions)
}

actions_out <- left_join(actions_out, actions, by = "ID")  %>% rename("ECOREGION value" = "ECOREGION_value")
actions_out <- actions_out[c("ECOREGION",
                             "ID",
                             "Action CMP 2.0",
                             "Description",
                             "Indicator",
                             "Trigger condition",
                             "ECOREGION value"
)]

actions_out$`ECOREGION value` <- round(actions_out$`ECOREGION value`, 2)

write_csv(actions_out, "output/action_recommendations.csv")




# Make a wide version that can be joined to the ecoregions
actions_wide <- actions_out %>%
  mutate(Recommended = "Yes") %>%
  select(ECOREGION, "ID", Recommended) %>%
  pivot_wider(names_from = "ID", values_from = "Recommended")

actions_wide[is.na(actions_wide)] <- "No"
actions_wide$`No recommended actions` <- NULL

# Count occurences of ABC triggers and restoration triggers
actions_wide$ABC_count <- apply(actions_wide[c("ABC1","ABC2","ABC3","ABC4","ABC5")], 1, function(x){length(which(x=="Yes"))})
actions_wide$Restoration_count <- apply(actions_wide[c("REST1","REST2")], 1, function(x){length(which(x=="Yes"))})

actions_wide <- actions_wide[c("ECOREGION",
                               "ABC1",
                               "ABC2",
                               "ABC3",
                               "ABC4",
                               "ABC5",
                               "STEW1",
                               "REST1",
                               "REST2",
                               "PARTNER1",
                               "ABC_count",
                               "Restoration_count"
)]

write_csv(actions_wide, "processing/action_recommendations/action_recommendations_wide.csv")
