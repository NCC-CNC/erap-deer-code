# Check for cases where the ecoregion total is greater than the national total
# Usually due to rounding error or bug in the species tiff

# 5c_species_extractions.R sets all values >100% to 100%. 
# This script checks for any cases that could be fixed in the source data.

library(tidyverse)

f_list <- list.files("processing/species/output_csv", full.names = TRUE)

df_list <- list()
for(f in f_list){
  df <- read_csv(f)
  df$Pct_Canada_range_in_ecoregion <- df$Ecoregion_Total_km2 / df$Canada_Total_km2 * 100
  x <- df[df$Pct_Canada_range_in_ecoregion > 100,]
  if(nrow(x) > 0){
    df_list[[f]] <- x
  }
}

out <- bind_rows(df_list)
write_csv(out, "C:/temp/species_check.csv")



# Check for NA values in all tables

for(f in f_list){
  df <- read_csv(f, show_col_types = FALSE)
  x <- df[rowSums(is.na(df[9:18])) > 0,]
  if(nrow(x) > 0){
    print(f)
    print(x)
  }
}