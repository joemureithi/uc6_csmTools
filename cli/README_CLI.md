# Command-Line Interface Examples for csmTools

This directory contains command-line interface (CLI) examples for running csmTools workflows.

## Files

### 1. `csmtools_cli.R`
Main CLI script with subcommands for each workflow step.

**Features:**
- Modular subcommands (extract-field, get-weather, get-soil, etc.)
- Built-in help system
- Error handling and progress feedback
- Support for all major workflow steps

### 2. `run_workflow.sh`
Complete bash script demonstrating the full workflow.

**Features:**
- Runs all steps in sequence
- Optional sensor data collection (if credentials available)
- Colored output for better readability
- Automatic directory creation

### 3. `Makefile`
GNU Make-based workflow automation.

**Features:**
- Dependency-based execution (only runs necessary steps)
- Configurable parameters
- Parallel execution support (`make -j4`)
- Easy partial workflow execution

### 4. `CLI_README.md`
Complete documentation for the CLI tools.

## Quick Start

### Using the CLI Script

```bash
# Get help
Rscript inst/examples/csmtools_cli.R --help

# Extract field data
Rscript inst/examples/csmtools_cli.R extract-field \
  --path inst/extdata/template_icasa_vba.xlsm \
  --exp-id HWOC2501 \
  --output archive/field.json

# Get weather data
Rscript inst/examples/csmtools_cli.R get-weather \
  --lon 10.645269 --lat 49.20868 \
  --from 2024-01-01 --to 2025-12-31 \
  --output archive/weather.json
```

### Using the Shell Script

```bash
# Run complete workflow
bash inst/examples/run_workflow.sh
```

### Using Make

```bash
# Run complete workflow
make -f inst/examples/Makefile

# Run specific steps
make -f inst/examples/Makefile weather
make -f inst/examples/Makefile soil

# Custom parameters
make -f inst/examples/Makefile all LON=12.5 LAT=51.3

# Parallel execution
make -f inst/examples/Makefile -j4

# Clean up
make -f inst/examples/Makefile clean
```

## Comparison

| Approach | Best For | Pros | Cons |
|----------|----------|------|------|
| **CLI Script** | Individual steps, debugging | Flexible, detailed control | Requires writing commands |
| **Shell Script** | Complete automated runs | Simple to execute | Less flexible |
| **Makefile** | Complex workflows | Dependency management, parallel | Requires make knowledge |

## Prerequisites

### R Packages

```R
# Required for CLI
install.packages("argparse")

# Required for csmTools
renv::install(".")
```

### Environment Variables

For FROST sensor data access, create `.Renviron`:

```bash
FROST_CLIENT_ID=your_client_id
FROST_CLIENT_SECRET=your_client_secret
FROST_USERNAME=your_username
FROST_PASSWORD=your_password
FROST_USER_URL=https://your-frost-server/v1.0/
```

## Workflow Steps

1. **extract-field** - Extract field data from ICASA template
2. **get-weather** - Download weather data (NASA POWER)
3. **get-sensor** - Download sensor data (FROST server)
4. **get-soil** - Extract soil profile (SoilGrids)
5. **assemble** - Combine data components
6. **convert** - Convert between formats (ICASA ↔ DSSAT)
7. **build-inputs** - Generate DSSAT input files
8. **simulate** - Run DSSAT simulation

## Advanced Usage

### Custom Workflows

Create your own shell script combining commands:

```bash
#!/bin/bash
# Custom workflow

# Download multiple locations
for lat in 49.2 50.1 51.3; do
  Rscript inst/examples/csmtools_cli.R get-weather \
    --lon 10.6 --lat $lat \
    --from 2024-01-01 --to 2024-12-31 \
    --output weather_${lat}.json
done
```

### Integration with Other Tools

```bash
# Export to CSV for analysis
Rscript -e 'jsonlite::fromJSON("archive/icasa.json") %>% 
  .$WEATHER_DAILY %>% 
  write.csv("weather.csv")'

# Process with jq
cat archive/icasa.json | jq '.WEATHER_METADATA'

# Chain with Python
Rscript inst/examples/csmtools_cli.R get-weather ... | python process.py
```

## Troubleshooting

**Command not found:**
```bash
chmod +x inst/examples/csmtools_cli.R
```

**Missing argparse:**
```R
install.packages("argparse")
```

**FROST credentials:**
Check `.Renviron` file is properly configured.

**Make errors:**
Ensure GNU Make is installed: `make --version`

## See Also

- [CLI_README.md](CLI_README.md) - Detailed CLI documentation
- [workflow_experiment_ochsenwasen.R](workflow_experiment_ochsenwasen.R) - Original R script example
