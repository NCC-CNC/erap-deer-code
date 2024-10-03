# Check for rasters with values that are too high.
# These are bugs caused in Dans scripts for species with very small ranges.
# The bug sets value to objectid instead of 1 if the area in a cell is <0.5 ha
# Fix is to set all values to 1 ha in these cases.

library(terra)

rij_list <- c("C:/Data/PRZ/WTW_DATA/WTW_NAT_DATA_20240522/biodiversity/RIJ_ECCC_CH.rds", 
              "C:/Data/PRZ/WTW_DATA/WTW_NAT_DATA_20240522/biodiversity/RIJ_ECCC_SAR.rds")
rij_list2 <- c("C:/Data/PRZ/WTW_DATA/WTW_NAT_DATA_20240522/biodiversity/RIJ_IUCN_AMPH.rds",
               "C:/Data/PRZ/WTW_DATA/WTW_NAT_DATA_20240522/biodiversity/RIJ_IUCN_BIRD.rds",
               "C:/Data/PRZ/WTW_DATA/WTW_NAT_DATA_20240522/biodiversity/RIJ_IUCN_MAMM.rds",
               "C:/Data/PRZ/WTW_DATA/WTW_NAT_DATA_20240522/biodiversity/RIJ_IUCN_REPT.rds",
               "C:/Data/PRZ/WTW_DATA/WTW_NAT_DATA_20240522/biodiversity/RIJ_NSC_END.rds",
               "C:/Data/PRZ/WTW_DATA/WTW_NAT_DATA_20240522/biodiversity/RIJ_NSC_SAR.rds",
               "C:/Data/PRZ/WTW_DATA/WTW_NAT_DATA_20240522/biodiversity/RIJ_NSC_SPP.rds")

# Search for layers with values that are higher than the max area of the cell
# Print names if any are found
for(rij in rij_list){
  x <- readRDS(rij)
  for(i in 1:length(rownames(x))){
    if(max(x[i,] > 100)){
      print(paste0(rownames(x)[i], " ----> ", max(x[i,])))
    }
  }
}
for(rij in rij_list2){
  x <- readRDS(rij)
  for(i in 1:length(rownames(x))){
    if(max(x[i,] > 1)){
      print(paste0(rownames(x)[i], " ----> ", max(x[i,])))
    }
  }
}



# Fix data

# T_NAT_ECCC_CH_END_COSEWIC_846
# Some squares in the map are set to 200 instead of 100. Fix: set all values > 200 to 100 ha
tif <- rast("Tiffs/T_NAT_ECCC_CH_END_COSEWIC_846.tif")
tif[tif > 100] <- 100
writeRaster(tif, "Tiffs/T_NAT_ECCC_CH_END_COSEWIC_846.tif", overwrite=TRUE, datatype = "INT2U")


# T_NAT_ECCC_CH_THR_COSEWIC_951
# Data are point counts all with small <0.5 ha buffers. Every value got set to a unique objectid. Fix: set all values to 1 ha
file.rename("Tiffs/T_NAT_ECCC_CH_THR_COSEWIC_951.tif", "Tiffs/T_NAT_ECCC_CH_THR_COSEWIC_951b.tif")
tif <- rast("Tiffs/T_NAT_ECCC_CH_THR_COSEWIC_951b.tif")
tif[tif > 0] <- 1
writeRaster(tif, "Tiffs/T_NAT_ECCC_CH_THR_COSEWIC_951.tif", overwrite=TRUE, datatype = "INT2U")
file.remove("Tiffs/T_NAT_ECCC_CH_THR_COSEWIC_951b.tif")

# T_NAT_ECCC_SAR_NOS_COSEWIC_882
# Just the values on the edge of the range got set to object id. Fix: set everything > 100 to 50ha
tif <- rast("Tiffs/T_NAT_ECCC_SAR_NOS_COSEWIC_882.tif")
tif[tif > 100] <- 50
writeRaster(tif, "Tiffs/T_NAT_ECCC_SAR_NOS_COSEWIC_882.tif", overwrite=TRUE, datatype = "INT2U")
