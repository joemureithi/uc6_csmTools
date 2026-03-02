# Debugging Summary – `workflow_experiment_ochsenwasen.R`

**Date:** 2026-03-02  
**Script:** `inst/examples/workflow_experiment_ochsenwasen.R`

---

## Overview

This document summarises the bugs identified and fixes applied while running the Ochsenwäsen experiment workflow end-to-end on a Linux machine. The fixes span the example script itself, two package source files, and the local DSSAT environment setup.

---

## Bugs Fixed

### 1. Soil and weather sections dropped from assembled ICASA dataset

**File:** `inst/examples/workflow_experiment_ochsenwasen.R`  
**Symptom:** `convert_dataset()` (ICASA → DSSAT) crashed with `Must supply .init when .x is empty` because `SOIL_META`, `SOIL_GENERAL`, `SOIL_LAYERS`, `WEATHER_METADATA`, and `WEATHER_DAILY` were absent from the assembled dataset.  
**Root cause:** `assemble_dataset()` was called without `keep_all = TRUE`. With the default `keep_all = FALSE`, the output structure is taken only from the first component (`tmp_expdata_icasa.json`), so the soil and weather sections contributed by the second and third components were silently discarded.

```r
# Before
dataset_icasa <- assemble_dataset(
  components = list(
    "./archive/tmp_expdata_icasa.json",
    "./archive/tmp_soildata_icasa.json",
    "./archive/tmp_weatherdata_combined.json"
  ),
  output_path = "./archive/tmp_icasa.json"
)

# After
dataset_icasa <- assemble_dataset(
  components = list(
    "./archive/tmp_expdata_icasa.json",
    "./archive/tmp_soildata_icasa.json",
    "./archive/tmp_weatherdata_combined.json"
  ),
  keep_all = TRUE,
  output_path = "./archive/tmp_icasa.json"
)
```

---

### 2. `build_simulation_files()` called with wrong argument name

**File:** `inst/examples/workflow_experiment_ochsenwasen.R`  
**Symptom:** Control parameters were silently ignored (unmatched argument).  
**Root cause:** The script passed `control_args = list(...)` but the function signature uses `control_config`. Additionally, `control_config` only accepted a file path (character), not a named list.

**Script fix:** renamed `control_args` → `control_config`.

**Package fix (`R/build_simulation_files.R`):** Extended the `control_config` loading block to also accept a named list directly, not just a YAML/JSON file path:

```r
if (!is.null(control_config)) {
  if (is.list(control_config)) {
    control_args <- control_config          # accept list directly
  } else {
    # existing file-based loading (yaml / json) ...
  }
}
```

---

### 3. `calculate_initial_layers()` — data.frame input not resolved correctly

**File:** `R/calculate_initial_layers.R`  
**Symptom:** `Error in resolve_input(soil_profile): Unsupported input type. Input must be a character string (JSON filepath) or an R list.`  
**Root cause:** The function wrapped the input data.frame into `data = list(SOIL = soil_profile)` but then called `resolve_input(soil_profile)` (the original bare data.frame) instead of `resolve_input(data)`.

```r
# Before
if (is.data.frame(soil_profile)) {
  data <- list(SOIL = soil_profile)
}
data_list <- resolve_input(soil_profile)   # ← still the raw df

# After
if (is.data.frame(soil_profile)) {
  soil_profile <- list(SOIL = soil_profile)
}
data_list <- resolve_input(soil_profile)   # ← now the wrapped list
```

---

### 4. DSSAT paths hardcoded to Windows (`C:/DSSAT48/`)

**File:** `inst/examples/workflow_experiment_ochsenwasen.R`  
**Symptom:** `dscsm048` binary and `.WHX` experiment file not found on Linux.  
**Fix:** Added cross-platform path detection before both `build_simulation_files()` and `run_simulations()`:

```r
# Set DSSAT executable path (cross-platform)
if (.Platform$OS.type == "unix") {
  Sys.setenv(DSSAT_CSM = file.path(Sys.getenv("HOME"), "dssat", "dscsm048"))
}

filex_path <- if (.Platform$OS.type == "unix") {
  file.path(Sys.getenv("HOME"), "dssat", "Wheat", "HWOC2501.WHX")
} else {
  "C:/DSSAT48/Wheat/HWOC2501.WHX"
}
```

---

### 5. `View()` calls fail in non-interactive `Rscript` execution

**File:** `inst/examples/workflow_experiment_ochsenwasen.R`  
**Symptom:** `Error in View(sims$plant_growth): invalid 'x' argument`  
**Fix:** Replaced `View()` with `print()`:

```r
# Before: View(sims$plant_growth)
# After:
print(sims$PlantGro)
```

---

### 6. Wrong output list keys for DSSAT simulation results

**File:** `inst/examples/workflow_experiment_ochsenwasen.R`  
**Symptom:** `Error in UseMethod("filter"): no applicable method for 'filter' applied to an object of class "NULL"`  
**Root cause:** The script referenced `sims$plant_growth` and `sims$SUMMARY`, but `run_simulations()` names output elements after the file basename (without extension), i.e. `PlantGro` and `Summary`.

| Wrong key | Correct key |
|---|---|
| `sims$plant_growth` | `sims$PlantGro` |
| `sims$SUMMARY` | `sims$Summary` |

---

### 7. Non-existent column `GWAM` in `Summary.OUT`

**File:** `inst/examples/workflow_experiment_ochsenwasen.R`  
**Symptom:** `object 'GWAM' not found` in ggplot aesthetics.  
**Root cause:** DSSAT 4.8 `Summary.OUT` uses `HWAM` (harvest dry matter at maturity) rather than `GWAM`.  
**Fix:** Replaced all references to `GWAM` with `HWAM`.

---

### 8. Incorrect date parsing of `HDAT`/`MDAT`

**File:** `inst/examples/workflow_experiment_ochsenwasen.R`  
**Symptom:** Would have produced wrong dates had it been reached.  
**Root cause:** The `mutate()` called `as.Date(..., format = "%y%j")` (2-digit year) on columns that `DSSAT::read_output()` already returns as `POSIXct`.  
**Fix:** Removed the `mutate()` call entirely.

---

## Environment Setup (Linux)

The DSSAT CSM executable was not installed. The following steps were performed:

1. **Compiled DSSAT** from the pre-cloned source at `~/dssat-csm-os/`:
   ```bash
   cd ~/dssat-csm-os/build
   cmake .. -DCMAKE_BUILD_TYPE=RELEASE -DCMAKE_INSTALL_PREFIX=$HOME/dssat
   make -j$(nproc)
   cp bin/dscsm048 ~/dssat/
   ```

2. **Generated `DSSATPRO.L48`** (the Linux runtime configuration file) from its cmake template, which had not been produced because `make install` was never run:
   ```bash
   sed "s|@CMAKE_INSTALL_PREFIX@|$HOME/dssat|g" \
     ~/dssat/DSSATPRO.L48.in > ~/dssat/DSSATPRO.L48
   ```
   Without this file DSSAT exits immediately with `STOP 99 / Configuration file not found`.

---

## Final Status

The script runs end-to-end with exit code 0. DSSAT simulates three fertilisation treatments (TRT 1, 3, 7) and results are printed and plotted successfully.

| TRT | N rate | TOPWT (kg/ha) | HARWT (kg/ha) |
|-----|--------|--------------|--------------|
| 1 | 0 kg N/ha | 4 673 | 1 587 |
| 3 | 147 kg N/ha | 10 882 | 2 233 |
| 7 | 180 kg N/ha | 11 175 | 2 362 |
