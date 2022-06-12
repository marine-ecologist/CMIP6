
library(HelpersMG)
library(aquamapsdata) #download_db()

default_db("sqlite")

######## CMIP6
### Source CMIP6 netcdf files are available from https://esgf-node.llnl.gov/search/cmip6/
### Model outputs vary spatial resolution (gridcell sizes) and temporal resolution (days, months, annual averages) across parameters
### This example uses the CMIP6 model for monthly sea surface temperature under ssp119 projections (2015-2100)
### CMIP6.ScenarioMIP.CCCma.CanESM5.ssp119.r11i1p1f1.Omon.tos.gn 
### where CanESM5 = Source.ID, ssp119=Experiment.ID, r11i1p1f1=Variant.Label, Omon=Frequency (monthly), tos=Variable (sea_surface_temperature)

# download .nc file with wget
# wget scripts for each nc available on esfg site
wget(url = stop("http://crd-esgf-drc.ec.gc.ca/thredds/fileServer/esgF_dataroot/AR6/CMIP6/ScenarioMIP/CCCma/CanESM5/ssp119/r11i1p1f1/Omon/tos/gn/v20190429/tos_Omon_CanESM5_ssp119_r11i1p1f1_gn_201501-210012.nc"))

### model outputs from CMIP 6 vary in resolution and are (sometimes) output on curvilinear grids. There are several ways of regridding spatial data
### in r using RGDAL (and other packages), but CDO (Climate Data Operators) is the most straight forward and time-effective approach. 
### CDO is a stand-alone command line code that requires separate installation (see https://code.mpimet.mpg.de/projects/cdo/)
### if using MacOS then macports provides a simple way of installation (https://ports.macports.org/port/cdo/)
### library(ClimateOperators) provides a wrapper to CDO once installed

### regrid CMIP files using bilinear grid interpolation. In this example I regrid the CMIP6 output from 1 x 1 to 0.5 x 0.5 
### to match resolution with species distribution maps in a later step:

library(ClimateOperators)
cdo(csl("remapbil","global_0.5"), "Datasets/CMIP6/tos_Omon_CanESM5_ssp119_r11i1p1f1_gn_201501-210012.nc","Datasets/CMIP6/tos_Omon_CanESM5_ssp119_r11i1p1f1_gn_201501-210012_cdoR_regrid.nc",debug=FALSE)

### after converting with CDO, read the regridded nc file through raster:
CanESM5_ssp119 <- raster::brick('Datasets/CMIP6/tos_Omon_CanESM5_ssp119_r11i1p1f1_gn_201501-210012_cdoR_regrid.nc', varname="tos") 

### raster files can be subset by date ranges and averaged to create a single averaged raster layer as follows:
CanESM5_ssp119 <- raster::brick('Datasets/CMIP6/tos_Omon_CanESM5_ssp119_r11i1p1f1_gn_201501-210012_cdoR_regrid.nc', varname="tos") %>% 
  subset(., which(getZ(.) >= as.Date("2099-01-01") & getZ(.) <= as.Date("2099-12-31"))) %>% 
  mean(., na.rm = TRUE)

######## World coastlines map
### Extract world coastline map from rnaturalearth package (available at different resolutions from "small" to "large")
### the following code takes the simple features output from ne_coastline and shifts the projection to centre on the 
### Pacific region. This approach avoids issues with cropping and recenter sf files (see the following for details) 
### https://stackoverflow.com/questions/68278789/how-to-rotate-world-map-using-mollweide-projection-with-sf-rnaturalearth-ggplot

target_crs <- st_crs("+proj=longlat +x_0=0 +y_0=0 +lat_0=0 +lon_0=180")
polygon <- st_polygon(x = list(rbind(c(-0.0001, 90), c(0, 90), c(0, -90), c(-0.0001, -90), c(-0.0001, 90)))) %>% st_sfc() %>% st_set_crs(4326)
worldrn_m <- ne_coastline(scale = "medium", returnclass = "sf") %>% st_make_valid() %>% st_difference(polygon) %>% st_transform(crs = target_crs)

######## Fish distributions
### Aquamaps (the base engine from www.fishbase.org) gives species distributions maps for marine fish species. The .csv files
### are available from www.aquamaps.com but library(aquamapsdata) allows for fuzzy searching and importing straight
### to raster files. Example distribution from aquamaps using the bluefin trevally (Caranx_melampygus):

Caranx_melampygus_aquamap <- aquamapsdata::am_raster(aquamapsdata::am_search_fuzzy("Caranx_melampygus")$key) %>% rasterToPolygons()

### The distribution raster output is then converted to a SpatialPolygonsDataFrame which in turn is used to mask the CMIP6 
### raster layer. Can be output as either sf polygons or sf ppints: 
Caranx_melampygus_SST_polygons <- raster::mask(CanESM5_ssp119, Caranx_melampygus_aquamap) %>% st_as_stars() %>% st_as_sf(merge = TRUE) %>% st_make_valid() %>% st_difference(polygon) %>% st_transform(crs = target_crs) %>% rename(SST=layer)
Caranx_melampygus_SST_points <- raster::mask(CanESM5_ssp119, Caranx_melampygus_aquamap) %>% st_as_stars() %>% st_as_sf(as_points=TRUE) %>% st_make_valid() %>% st_difference(polygon) %>% st_transform(crs = target_crs) %>% rename(SST=layer)
#st_as_sfc()

######## Plot outputs 
### Pacific centered worldmap of distribution of Caranx melampygus and mean monthly SST for 2099 under the ssp119 projection:

ggplot() + theme_bw() +
  geom_sf(data = Caranx_melampygus_SST_points,aes(col=SST), alpha=0.8) +
  geom_sf(data = worldrn_m, fill=NA, size=0.5) + xlim(-145,105) + ylim(-40,40) +
  geom_hline(yintercept=0, size=0.1) +
  scale_color_viridis() +
  scale_fill_viridis() +
  theme(legend.position="bottom") +
  theme(legend.key.width=unit(1, "cm")) +
  theme(axis.line = element_line(color='black'),
  plot.background = element_blank(),
  panel.grid.major = element_blank(),
  panel.grid.minor = element_blank())
