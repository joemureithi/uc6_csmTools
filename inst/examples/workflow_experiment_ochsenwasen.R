## -----------------------------------------------------------------------------------
## Script name: example_pipeline_experiment.R
## Purpose of script: showcasing etl pipeline prototype of FAIRagro 
## UC6 as an example of application of FAIR RDM
##
## Author: Benjamin Leroy
## Date Created: 2024-01-31
## Copyright (c) Benjamin Leroy, 2024
## Email: benjamin.leroy@tum.de
## -----------------------------------------------------------------------------------
## Notes: data are at least partially simulated and do not represent the actual
## experiment results
## 
## -----------------------------------------------------------------------------------

# Load required libraries
# library(csmTools)
library(dplyr)
library(ggplot2)

script_args <- commandArgs(trailingOnly = FALSE)
script_file <- sub("^--file=", "", script_args[grep("^--file=", script_args)])
script_dir <- if (length(script_file) > 0) {
  dirname(normalizePath(script_file))
} else {
  getwd()
}

###----- Install/load package --------------------------------------------------------

# Install devtools if you haven't already
if (!requireNamespace("devtools", quietly = TRUE)) {
  install.packages("devtools")
}

root_dir <- normalizePath(file.path(script_dir, "..", ".."))

if (file.exists(file.path(root_dir, "DESCRIPTION")) && file.exists(file.path(root_dir, "NAMESPACE"))) {
  devtools::load_all(root_dir)
} else {
  devtools::install_github("fairagro/csmTools")
  library(csmTools)
}

###----- Crop management/manually input data (template) ------------------------------
## -----------------------------------------------------------------------------------
## This section demonstrates the import of ICASA-compliant field (meta)data via the
## manual csmTemplate
##
## -----------------------------------------------------------------------------------

template_path <- normalizePath(
  file.path(script_dir, "..", "extdata", "template_icasa_vba.xlsm"),
  mustWork = TRUE
)

# Extract template data
mngt_obs_icasa <- get_field_data(
  path = template_path,
  exp_id = "HWOC2501",
  headers = "long",
  keep_null_events = FALSE
)

# Retrieve cultivation season temporal coverage to identify weather requirements
mngt_tables <-
  mngt_obs_icasa[!names(mngt_obs_icasa) %in% c("GENERAL", "PERSONS", "INSTITUTIONS")]
cseason <- identify_production_season(
  mngt_tables,
  period = "cultivation_season",
  output = "bounds"
)
print(cseason)  # Note: the cultivation season overlaps 2024 and 2025


###----- IoT weather stations data ---------------------------------------------------
## -----------------------------------------------------------------------------------
## This section showcase the acquisition of IoT sensor data (weather ## time series)
## from a weather station operating on the study field in Triesdorf and stored on
## FROST server (OGC SensorThings API). The steps include (1) pulling the data;
## (2) transform to DSSAT input format.The 'extract' routine requires FROST server
## credentials.
##
## -----------------------------------------------------------------------------------

# --- Extract all sensor weather data from the field location for 2025 ---

# Set FROST server credentials
base_url <- "https://keycloak.hef.tum.de/realms/master/protocol/openid-connect/token"
user_url <- Sys.getenv("FROST_USER_URL")

# Prepare credentials list for get_sensor_data
frost_creds <- list(
  url = base_url,
  client_id = Sys.getenv("FROST_CLIENT_ID"),
  client_secret = Sys.getenv("FROST_CLIENT_SECRET"),
  username = Sys.getenv("FROST_USERNAME"),
  password = Sys.getenv("FROST_PASSWORD")
)

# Set query arguments
years <- sapply(cseason, lubridate::year)
start_date <- paste0(years[1], "-01-01")
end_date <- paste0(years[2], "-12-31")
end_date <- if (Sys.Date() <= end_date) cseason[2] else end_date
wth_parameters = c("air_temperature", "solar_radiation", "volume_of_hydrological_precipitation")
longitude = 10.645269
latitude = 49.20868


# Data extraction and mapping
wth_sensor_raw <- get_sensor_data(
  url = user_url,
  creds = frost_creds,
  var = wth_parameters,
  lon = 10.645269,
  lat = 49.20868, 
  radius = 10,
  from = start_date,
  to = end_date,
  output_path = "./archive/tmp_weatherdata_sensor.json"
)

# --- Map raw weather data to ICASA ---
# Use the sensor data file path since it was saved
wth_field_icasa <- convert_dataset(
  dataset = "./archive/tmp_weatherdata_sensor.json",
  input_model = "user",
  output_model = "icasa",
  unmatched_code = "na"
)



###----- Complementary weather data --------------------------------------------------
## -----------------------------------------------------------------------------------
## This section showcase the extraction of standardization of weather data from a
## third-party databases (NASA POWER) to complement the field-measured weather data
## (i.e., fill data gaps).
##
## -----------------------------------------------------------------------------------

# --- Check coverage of field monitoring ---
c(min(wth_field_icasa$WEATHER_DAILY$weather_date),
  max(wth_field_icasa$WEATHER_DAILY$weather_date))
# >> Sensors were only installed in spring, no data from planting date!

# --- Download complementary weather data from NASA POWER ---
wth_nasa_raw <- get_weather_data(
  lon = longitude,
  lat = latitude,
  pars = c("air_temperature", "precipitation", "solar_radiation"),
  res = "daily",
  from = start_date,
  to = end_date,
  src = "nasa_power",
  output_path = "./archive/tmp_weatherdata_nasapower.json"
)

# --- Map complementary weather data to ICASA ---
wth_nasa_icasa <- convert_dataset(
  dataset = "./archive/tmp_weatherdata_nasapower.json",
  input_model = "nasa-power",
  output_model = "icasa",
  output_path = "./archive/tmp_weatherdata_icasa.json"
)

# -- Assemble composite weather dataset ---
# Combine sensor and NASA POWER weather data
weather_icasa <- assemble_dataset(
  components = list(wth_field_icasa, wth_nasa_icasa),
  keep_all = TRUE,
  action = "merge_properties",
  output_path = "./archive/tmp_weatherdata_combined.json"
)


###----- Soil profile data - external database --------------------------------------
## ----------------------------------------------------------------------------------
## This section demonstrates the sourcing of soil profile data from a a published
## dataset (Global 10-km Soil Grids DSSAT profiles). The data is first downloaded
## with the Dataverse API, and the closest profile to the set of input coordinates
## extracted. As the dataset already provides ready-to-use DSSAT formats, no
## mapping step is necesary here. 
## Data reference: https://doi.org/10.7910/DVN/1PEEY0
##
## ----------------------------------------------------------------------------------

#####----- Extract profile data from SoilGrids --------------------------------------
soil_icasa <- get_soil_profile(
  lon = longitude,
  lat = latitude,
  dir = tempdir(),  # "./xxxx/temp"
  output_path = "./archive/tmp_soildata_icasa.json"
)

# --- Renv version
# soil_icasa <- get_soilGrids_profile(
#   lon = longitude,
#   lat = latitude,
#   output_path = NULL
# )


###----- Soil profile data - external database --------------------------------------
## ----------------------------------------------------------------------------------
## This section demonstrates the sourcing of soil profile data from a a published
## dataset (Global 10-km Soil Grids DSSAT profiles). The data is first downloaded
## with the Dataverse API, and the closest profile to the set of input coordinates
## extracted. As the dataset already provides ready-to-use DSSAT formats, no
## mapping step is necesary here. 
## Data reference: https://doi.org/10.7910/DVN/1PEEY0
##

## ----------------------------------------------------------------------------------

phenology_path <- file.path(root_dir, "archive", "wheat_phenology_results.csv")

if (file.exists(phenology_path)) {
  gs_raw <- lookup_gs_dates(
    data = phenology_path,
    gs_scale = "zadok",
    gs_codes = c(10, 65, 87),
    date_select_rule = "median",
    output_path = file.path(root_dir, "archive", "tmp-phenology.json")
  )

  gs_icasa <- convert_dataset(
    dataset = gs_raw,
    input_model = "user",
    output_model = "icasa",
    output_path = file.path(root_dir, "archive", "tmp-phenology-icasa.json")
  )
} else {
  warning("Phenology results file not found at ", phenology_path, ". Skipping phenology processing.")
  gs_raw <- NULL
  gs_icasa <- NULL
}


###----- Data integration and mapping to DSSAT --------------------------------------
## ----------------------------------------------------------------------------------
## xxxxxx
##
## ----------------------------------------------------------------------------------

# --- Renv version
# dataset_icasa <- assemble_dataset(
#   components = list(mngt_obs_icasa, weather_icasa, soil_icasa),
#   output_path = NULL
# )

dataset_icasa <- assemble_dataset(
  components = list(
    "./archive/tmp_expdata_icasa.json",
    "./archive/tmp_soildata_icasa.json",
    "./archive/tmp_weatherdata_combined.json"
  ),
  keep_all = TRUE,
  output_path = "./archive/tmp_icasa.json"
)

# Map to DSSAT

# --- Renv version
# dataset_dssat <- convert_dataset(
#   dataset = dataset_icasa,
#   input_model = "icasa",
#   output_model = "dssat",
#   output_path = NULL
# )

dataset_dssat <- convert_dataset(
  dataset = "./archive/tmp_icasa.json",
  input_model = "icasa",
  output_model = "dssat",
  output_path = "./archive/dataset_dssat.json"
)


###----- Perform simulations --------------------------------------------------------
## ----------------------------------------------------------------------------------
## Compiles DSSAT input files from all the different data sections (weather, soil,
## crop management, cultivar parameters, measured data) and set controls for the
## simulations (DSSAT documentation ###).
## Simulation are performed using the written inputs
## 
## NB: this part require a local installation of DSSATCSM
## (default installation dir: "C:/DSSAT48")
##
## ----------------------------------------------------------------------------------

###----- Adjust data ----------------------------------------------------------------

# TODO: add default + calibration

# Normalize soil profile
soil_dssat_std <- normalize_soil_profile(
  data = dataset_dssat$SOIL,
  depth_seq = c(5,10,20,30,40,50,60,70,90,110,130,150,170,190,210),
  method = "linear"
)
#OPT1: take the whole DSSAT data and fetch the soil section
dataset_dssat$SOIL <- soil_dssat_std$SOIL
dataset_dssat$SOIL$SRGF <- 1

# Generate initial layers
init_layers <- calculate_initial_layers(
  soil_profile = dataset_dssat$SOIL,
  percent_available_water = 100,
  total_n_kgha = 50  # Value provided in field book, but only for 0-60 cm
  )
dataset_dssat$MANAGEMENT$INITIAL_CONDITIONS$ICBL <- list(init_layers$ICBL)
dataset_dssat$MANAGEMENT$INITIAL_CONDITIONS$SH2O <- list(init_layers$SH2O)
dataset_dssat$MANAGEMENT$INITIAL_CONDITIONS$SNH4 <- list(init_layers$SNH4)
dataset_dssat$MANAGEMENT$INITIAL_CONDITIONS$SNO3 <- list(init_layers$SNO3)

dataset_dssat$MANAGEMENT$FIELDS$ID_SOIL <- "IB00000007"
# The above overrides the soil ID to DSSAT's built-in generic loam, so DSSAT uses that soil instead of the SoilGrids-derived profile. 
# The CLI has no such override, so it uses the actual SoilGrids soil → much higher simulated yields → higher Y-axis.

###----- Compile crop modeling data -------------------------------------------------

# Set DSSAT executable path (cross-platform)
if (.Platform$OS.type == "unix") {
  Sys.setenv(DSSAT_CSM = file.path(Sys.getenv("HOME"), "dssat", "dscsm048"))
}

# Assemble full input dataset
dataset_dssat_input <- build_simulation_files(
  dataset = dataset_dssat,
  sol_append = FALSE,
  write = TRUE, write_in_dssat_dir = TRUE,
  control_config = list(
    RSEED = 1243, SMODEL = "WHAPS",  # general
    WATER = "Y", NITRO = "Y", TILL = "Y",  # options
    PHOTO = "C", MESEV = "S", # methods
    FERTI = "R", HARVS = "M",  # management
    GROUT = "Y", VBOSE = "Y"  # output
  )
)
# EDGE CASE: IF ICASA TEMPLATE GIVES TOT N LAYER FOR INIT COND BUT REST IS NA
# ONLY DEPTHS IN INIT COND TABLE AND PARSER FAILS

###----- Run DSSAT simulation ------------------------------------------------------

output_directory <- paste0(getwd(), "/simulations")

filex_path <- if (.Platform$OS.type == "unix") {
  file.path(Sys.getenv("HOME"), "dssat", "Wheat", "HWOC2501.WHX")
} else {
  "C:/DSSAT48/Wheat/HWOC2501.WHX"
}

sims <- run_simulations(
  filex_path = filex_path,
  treatments = c(1, 3, 7),
  framework = "dssat",
  dssat_dir = NULL,
  sim_dir = "./inst/extdata/test_fixtures"
)

print(sims$PlantGro)


###----- Plot output ---------------------------------------------------------------
plot_output <- function(sim_output){
  
  # Observed data
  obs_summary_growth <- sim_output$Summary %>%
    filter(TRNO %in% c(1,3,7))  # HDAT/MDAT already POSIXct from read_output
  
  # Simulated data
  sim_growth <- sim_output$PlantGro
  
  # Plot
  plot_growth <- sim_growth %>%
    mutate(TRNO = as.factor(TRNO)) %>%
    ggplot(aes(x = DATE, y = GWAD)) +
    # Line plot for simulated data
    geom_line(aes(group = TRNO, colour = TRNO, linewidth = "Simulated")) +
    # Points for observed data
    geom_point(data = obs_summary_growth,
               aes(x = HDAT, y = HWAM, colour = as.factor(TRNO), size = "Observed"), shape = 20) +
    # Phenology (estimated)
    # geom_vline(data = obs_summary_growth, aes(xintercept = EDAT), colour = "darkblue") +
    # geom_vline(data = obs_summary_growth, aes(xintercept = ADAT), colour = "darkgreen") +
    # geom_vline(data = obs_summary_growth, aes(xintercept = MDAT), colour = "purple") +
    # General appearance
    scale_colour_manual(name = "Fertilization (kg[N]/ha)",
                        breaks = c("1","3","7"),
                        labels = c("0","147","180"),
                        values = c("#999999", "#E18727", "#BC3C29")) +
    scale_size_manual(values = c("Simulated" = 1, "Observed" = 2), limits = c("Simulated", "Observed")) +
    scale_linewidth_manual(values = c("Simulated" = 1, "Observed" = 2), limits = c("Simulated", "Observed")) +
    labs(size = NULL, linewidth = NULL, y = "Yield (kg/ha)") +
    guides(
      size = guide_legend(
        override.aes = list(linetype = c("solid", "blank"), shape = c(NA, 16))
      )
    ) +
    theme_bw() + 
    theme(legend.text = element_text(size = 8), legend.title = element_text(size = 8),
          axis.title.x = ggplot2::element_blank(), axis.title.y = element_text(size = 10),
          axis.text = element_text(size = 9, colour = "black"))
  
  return(plot_growth)
}

print(plot_output(sims))


# TODO: comparison soil moisture measured vs simulated
# TODO: same thing for anthesis

tmp <- sims$Summary %>%
  select(TRNO, HWAM) %>%
  left_join(sims$PlantGro %>%
              filter(DATE == max(DATE)))
