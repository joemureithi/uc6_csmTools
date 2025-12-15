#!/bin/bash
## -----------------------------------------------------------------------------------
## Script name: run_workflow.sh
## Purpose: Complete workflow example using csmTools CLI
## -----------------------------------------------------------------------------------

set -e  # Exit on error

# Configuration
WORKDIR="archive"
CLI_SCRIPT="inst/examples/csmtools_cli.R"
LON=10.645269
LAT=49.20868
START_DATE="2024-01-01"
END_DATE="2025-08-09"
EXP_ID="HWOC2501"
TEMPLATE_PATH="inst/extdata/template_icasa_vba.xlsm"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Starting csmTools workflow...${NC}\n"

# Create working directory
mkdir -p $WORKDIR

# Step 1: Extract field data
echo -e "${GREEN}Step 1: Extracting field data...${NC}"
Rscript $CLI_SCRIPT extract-field \
  --path $TEMPLATE_PATH \
  --exp-id $EXP_ID \
  --output $WORKDIR/field.json

# Step 2: Get weather data from NASA POWER
echo -e "\n${GREEN}Step 2: Downloading weather data...${NC}"
Rscript $CLI_SCRIPT get-weather \
  --lon $LON --lat $LAT \
  --from $START_DATE --to $END_DATE \
  --output $WORKDIR/weather_nasa.json

# Step 3: Get sensor data (optional - requires credentials)
if [ ! -z "$FROST_CLIENT_ID" ]; then
  echo -e "\n${GREEN}Step 3: Downloading sensor data...${NC}"
  Rscript $CLI_SCRIPT get-sensor \
    --lon $LON --lat $LAT \
    --from $START_DATE --to $END_DATE \
    --radius 10 \
    --output $WORKDIR/sensor.json
  
  # Combine sensor and NASA weather
  WEATHER_FILES="$WORKDIR/sensor.json $WORKDIR/weather_nasa.json"
else
  echo -e "\n${BLUE}Step 3: Skipping sensor data (no credentials)${NC}"
  WEATHER_FILES="$WORKDIR/weather_nasa.json"
fi

# Step 4: Convert weather to ICASA
echo -e "\n${GREEN}Step 4: Converting weather data to ICASA...${NC}"
Rscript $CLI_SCRIPT convert \
  --input $WORKDIR/weather_nasa.json \
  --from nasa-power --to icasa \
  --output $WORKDIR/weather_icasa.json

# Step 5: Get soil data
echo -e "\n${GREEN}Step 5: Extracting soil profile...${NC}"
Rscript $CLI_SCRIPT get-soil \
  --lon $LON --lat $LAT \
  --output $WORKDIR/soil.json

# Step 6: Assemble into ICASA format
echo -e "\n${GREEN}Step 6: Assembling ICASA dataset...${NC}"
Rscript $CLI_SCRIPT assemble \
  --components $WORKDIR/field.json $WORKDIR/weather_icasa.json $WORKDIR/soil.json \
  --output $WORKDIR/icasa.json \
  --action merge_properties

# Step 7: Convert to DSSAT format
echo -e "\n${GREEN}Step 7: Converting to DSSAT format...${NC}"
Rscript $CLI_SCRIPT convert \
  --input $WORKDIR/icasa.json \
  --from icasa --to dssat \
  --output $WORKDIR/dssat.json

# Step 8: Build DSSAT inputs
echo -e "\n${GREEN}Step 8: Building DSSAT input files...${NC}"
Rscript $CLI_SCRIPT build-inputs \
  --input $WORKDIR/dssat.json

# Step 9: Run simulation (if DSSAT is installed)
if [ -d ~/dssat ]; then
  echo -e "\n${GREEN}Step 9: Running DSSAT simulation...${NC}"
  Rscript $CLI_SCRIPT simulate \
    --filex ~/dssat/Wheat/HWOC2501.WHX \
    --treatments 1,3,7 \
    --dssat-dir ~/dssat \
    --output-dir ./simulations
else
  echo -e "\n${BLUE}Step 9: Skipping simulation (DSSAT not installed)${NC}"
  echo "To run simulations, install DSSAT using: bash install_dssat.sh"
fi

echo -e "\n${GREEN}✓ Workflow complete!${NC}"
echo "Output files saved to: $WORKDIR/"
ls -lh $WORKDIR/
