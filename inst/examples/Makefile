# Makefile for csmTools workflow
# Usage: make all LON=10.645 LAT=49.208 EXP_ID=HWOC2501

# Configuration
CLI := Rscript inst/examples/csmtools_cli.R
WORKDIR := archive
TEMPLATE := inst/extdata/template_icasa_vba.xlsm

# Location parameters (override with: make all LON=... LAT=...)
LON ?= 10.645269
LAT ?= 49.20868
EXP_ID ?= HWOC2501
START_DATE ?= 2024-01-01
END_DATE ?= 2025-12-31

# Output files
FIELD_DATA := $(WORKDIR)/field.json
WEATHER_DATA := $(WORKDIR)/weather_nasa.json
WEATHER_ICASA := $(WORKDIR)/weather_icasa.json
SOIL_DATA := $(WORKDIR)/soil.json
ICASA_DATA := $(WORKDIR)/icasa.json
DSSAT_DATA := $(WORKDIR)/dssat.json

# Phony targets
.PHONY: all clean help extract weather soil assemble convert

all: $(DSSAT_DATA)
	@echo "✓ Complete workflow finished!"
	@echo "Final output: $(DSSAT_DATA)"

help:
	@echo "csmTools Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  all       - Run complete workflow"
	@echo "  extract   - Extract field data only"
	@echo "  weather   - Download weather data only"
	@echo "  soil      - Download soil data only"
	@echo "  assemble  - Assemble ICASA dataset"
	@echo "  convert   - Convert to DSSAT format"
	@echo "  clean     - Remove all generated files"
	@echo ""
	@echo "Variables:"
	@echo "  LON        - Longitude (default: $(LON))"
	@echo "  LAT        - Latitude (default: $(LAT))"
	@echo "  EXP_ID     - Experiment ID (default: $(EXP_ID))"
	@echo "  START_DATE - Start date (default: $(START_DATE))"
	@echo "  END_DATE   - End date (default: $(END_DATE))"
	@echo ""
	@echo "Examples:"
	@echo "  make all"
	@echo "  make weather LON=12.5 LAT=51.3"
	@echo "  make clean"

# Extract field data
$(FIELD_DATA): $(TEMPLATE) | $(WORKDIR)
	@echo "→ Extracting field data..."
	@$(CLI) extract-field \
		--path $(TEMPLATE) \
		--exp-id $(EXP_ID) \
		--output $@

extract: $(FIELD_DATA)

# Download weather data
$(WEATHER_DATA): | $(WORKDIR)
	@echo "→ Downloading weather data..."
	@$(CLI) get-weather \
		--lon $(LON) --lat $(LAT) \
		--from $(START_DATE) --to $(END_DATE) \
		--output $@

weather: $(WEATHER_DATA)

# Convert weather to ICASA
$(WEATHER_ICASA): $(WEATHER_DATA)
	@echo "→ Converting weather to ICASA format..."
	@$(CLI) convert \
		--input $(WEATHER_DATA) \
		--from nasa-power --to icasa \
		--output $@

# Download soil data
$(SOIL_DATA): | $(WORKDIR)
	@echo "→ Extracting soil profile..."
	@$(CLI) get-soil \
		--lon $(LON) --lat $(LAT) \
		--output $@

soil: $(SOIL_DATA)

# Assemble ICASA dataset
$(ICASA_DATA): $(FIELD_DATA) $(WEATHER_ICASA) $(SOIL_DATA)
	@echo "→ Assembling ICASA dataset..."
	@$(CLI) assemble \
		--components $(FIELD_DATA) $(WEATHER_ICASA) $(SOIL_DATA) \
		--output $@ \
		--action merge_properties

assemble: $(ICASA_DATA)

# Convert to DSSAT format
$(DSSAT_DATA): $(ICASA_DATA)
	@echo "→ Converting to DSSAT format..."
	@$(CLI) convert \
		--input $(ICASA_DATA) \
		--from icasa --to dssat \
		--output $@

convert: $(DSSAT_DATA)

# Create working directory
$(WORKDIR):
	@mkdir -p $(WORKDIR)

# Clean generated files
clean:
	@echo "Cleaning generated files..."
	@rm -rf $(WORKDIR)
	@echo "✓ Clean complete"

# Print configuration
config:
	@echo "Configuration:"
	@echo "  LON        = $(LON)"
	@echo "  LAT        = $(LAT)"
	@echo "  EXP_ID     = $(EXP_ID)"
	@echo "  START_DATE = $(START_DATE)"
	@echo "  END_DATE   = $(END_DATE)"
	@echo "  WORKDIR    = $(WORKDIR)"
