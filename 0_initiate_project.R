# Intiate the project and folders structure

# Folders are arranged as follows:
# scripts - includes all scripts, to be run in order, to generate the ERAP data
# processing - interim datasets required for the ERAPs are stored here
# output - final ERAP tables and ecoregions are stored here

if(!dir.exists("processing")){
  dir.create("processing")
}

if(!dir.exists("output")){
  dir.create("output")
}