# Debugging Summary – `cli/run_workflow.sh` + `cli/csmtools_cli.R`

**Date:** 2026-03-02  
**Scripts:** `cli/run_workflow.sh`, `cli/csmtools_cli.R`

---

## Overview

This document summarises the bugs identified and fixes applied while running the full 15-step CLI workflow (`run_workflow.sh`) end-to-end on Linux. All issues were in the `build-simulation-files` handler of `csmtools_cli.R` or in how the generated DSSAT files were consumed by `dscsm048`.

---

## Bugs Fixed

### 1. "More than 19 layers in the soil profile" — DSSAT hard limit

**Command:** Step 13 (`build-simulation-files`) → Step 14 (`run-simulations`)  
**Symptom:**
```
More than 19 layers in the soil profile. Correct input file.
File: DE.SOL   Line: 0   Error key: IPSOIL
```
**Root cause:** Raw SoilGrids profiles contain more than 19 soil layers. DSSAT enforces a hard maximum of 19 layers and refuses to run if exceeded. The CLI was writing the un-normalised soil directly — the normalisation step (Steps 11–12) computed and saved output files but never merged the result back into `dataset` before `build_simulation_files()` was called.

**Fix:** Added in-memory soil normalisation and initial-layer calculation inside the `build-simulation-files` handler, before `build_simulation_files()` is called. The `--depth-seq`, `--method`, `--paw`, and `--total-n` CLI flags control the process:

```r
depth_seq <- as.numeric(strsplit(args$depth_seq, ",")[[1]])
soil_norm <- normalize_soil_profile(
  data = dataset$SOIL,
  depth_seq = depth_seq,
  method = args$method
)
dataset$SOIL <- soil_norm$SOIL
dataset$SOIL$SRGF <- 1

init_layers <- calculate_initial_layers(
  soil_profile = dataset$SOIL,
  percent_available_water = args$paw,
  total_n_kgha = args$total_n
)
dataset$MANAGEMENT$INITIAL_CONDITIONS$ICBL <- list(init_layers$INITIAL_CONDITIONS$ICBL)
dataset$MANAGEMENT$INITIAL_CONDITIONS$SH2O <- list(init_layers$INITIAL_CONDITIONS$SH2O)
dataset$MANAGEMENT$INITIAL_CONDITIONS$SNH4 <- list(init_layers$INITIAL_CONDITIONS$SNH4)
dataset$MANAGEMENT$INITIAL_CONDITIONS$SNO3 <- list(init_layers$INITIAL_CONDITIONS$SNO3)
```

**`run_workflow.sh` Step 13 command after fix:**
```bash
Rscript $CLI_SCRIPT build-simulation-files \
  --input $WORKDIR/dssat.json \
  --depth-seq "5,10,20,30,40,50,60,70,90,110,130,150,170,190,210" \
  --method linear --paw 100 --total-n 50 --write-dssat-dir
```

---

### 2. `attr(dataset$SOIL, "file_name")` stripped by `normalize_soil_profile()`

**Command:** Step 13 (`build-simulation-files`)  
**Symptom:** Silent — downstream DSSAT could not find the expected SOL file.  
**Root cause:** `normalize_soil_profile()` returned a tibble without the `file_name` attribute that csmTools uses to determine the output SOL filename. The attribute was set earlier by the data pipeline but not preserved across the normalisation call.

**Fix:** Capture the attribute before normalisation and restore it afterwards:

```r
# Capture before normalisation
.written_sol_name <- attr(dataset$SOIL, "file_name")  # e.g. "LL.SOL"

soil_norm <- normalize_soil_profile(...)
dataset$SOIL <- soil_norm$SOIL
dataset$SOIL$SRGF <- 1

# Restore after normalisation
if (!is.null(.written_sol_name))
  attr(dataset$SOIL, "file_name") <- .written_sol_name
```

---

### 3. SOL filename mismatch: `LL.SOL` written, `DE.SOL` expected by DSSAT

**Command:** Step 13 (`build-simulation-files`) → Step 14 (`run-simulations`)  
**Symptom:** Same IPSOIL error as bug #1, but persisting after the layer-count fix.  
**Root cause:** csmTools names the SOL file from the institution abbreviation (`strict_abbreviate(INST_NAME, 2)`). For `INST_NAME = "Landwirtschaftliche Lehranstalten"` this gives `"LL"` → `"LL.SOL"`. However, DSSAT derives the soil file to look up from the first two characters of `ID_SOIL` in the WHX file (`"DE02114767"` → `"DE.SOL"`). The two names differ.

**Fix:** After `build_simulation_files()`, copy the written SOL file to the name DSSAT expects:

```r
.id_soil <- dataset$MANAGEMENT$FIELDS$ID_SOIL[1]  # captured before normalisation

# … after build_simulation_files() …
dssat_soil_dir <- file.path(dirname(Sys.getenv("DSSAT_CSM")), "Soil")
expected_sol_name <- paste0(toupper(substr(trimws(.id_soil), 1, 2)), ".SOL")
if (!identical(expected_sol_name, .written_sol_name)) {
  written_sol_path  <- file.path(dssat_soil_dir, .written_sol_name)
  expected_sol_path <- file.path(dssat_soil_dir, expected_sol_name)
  if (file.exists(written_sol_path)) {
    file.copy(written_sol_path, expected_sol_path, overwrite = TRUE)
    message("Copied soil file: ", .written_sol_name, " → ", expected_sol_name)
  }
}
```

---

### 4. Wrong crop model — `SMODEL` defaulted to `"WHCER"` instead of `"WHAPS"`

**Command:** Step 14 (`run-simulations`)  
**Symptom:**
```
Error in Cultivar entry.  Fix cultivar input file.
File: WHCER048.CUL   Line: *****   Error key: IPVAR
```
**Root cause:** The `control_config` list in the `build-simulation-files` handler was missing `SMODEL`. DSSAT defaulted to the CERES wheat model (`WHCER`), but the cultivar `LL0001` is defined for the APSIM wheat model (`WHAPS`).

**Fix:** Added `SMODEL = "WHAPS"` to the `control_config` list:

```r
control_config = list(
  RSEED  = 1243,
  SMODEL = "WHAPS",   # ← APSIM wheat (cultivar LL0001 lives in WHAPS048.CUL)
  WATER  = "Y",
  NITRO  = "Y",
  TILL   = "Y",
  PHOTO  = "C",
  MESEV  = "S",
  FERTI  = "R",
  HARVS  = "M",
  GROUT  = "Y",
  VBOSE  = "Y"
)
```

---

### 5. Cultivar `LL0001` missing from `~/dssat/Genotype/WHAPS048.CUL`

**Command:** Step 14 (`run-simulations`)  
**Symptom:**
```
Error in Cultivar entry.  Fix cultivar input file.
File: WHAPS048.CUL   Line: *****   Error key: IPVAR
```
**Root cause:** The cultivar `LL0001 SU Mangold` is referenced in `HWOC2501.WHX` but its genetic coefficients were not present in the installed DSSAT genotype file. The coefficients are not stored in the csmTools JSON dataset — they only existed in the bundled example file `inst/examples/sciwin/DSSAT48.INP`.

**Fix:** Added automatic cultivar injection in the `build-simulation-files` handler. After `build_simulation_files()` runs, the handler:

1. Reads `~/dssat/Genotype/WHAPS048.CUL` via `DSSAT::read_cul()`.
2. Checks whether the dataset cultivar (`INGENO`) is already present.
3. If absent, parses the `*CULTIVAR` section of the bundled `inst/examples/sciwin/DSSAT48.INP` (accessible via `system.file()`) to extract the coefficient line.
4. Calls `add_cultivar()` to append the entry, then writes back with `DSSAT::write_cul()`.

```r
cul_file   <- file.path(dssat_dir, "Genotype", "WHAPS048.CUL")
cul_ingeno <- dataset$MANAGEMENT$CULTIVARS$INGENO[1]
cul_tbl    <- DSSAT::read_cul(cul_file)

if (!cul_ingeno %in% cul_tbl$`VAR#`) {
  inp_path  <- system.file("examples/sciwin/DSSAT48.INP", package = "csmTools")
  inp_lines <- readLines(inp_path, warn = FALSE)
  cv_sec    <- which(trimws(inp_lines) == "*CULTIVAR")
  cv_block  <- inp_lines[(cv_sec[1] + 1):length(inp_lines)]
  cv_block  <- cv_block[nchar(trimws(cv_block)) > 0]
  cv_match  <- cv_block[grepl(paste0("^\\s*", cul_ingeno, "\\b"), cv_block)]

  parts    <- strsplit(trimws(cv_match[1]), "\\s+")[[1]]
  n        <- length(parts)
  cv_gpars <- as.numeric(parts[(n - 3):n])
  cv_ppars <- as.numeric(parts[(n - 8):(n - 4)])
  cv_ecode <- parts[n - 9]
  cv_name  <- paste(parts[2:(n - 10)], collapse = " ")

  cul_tbl_new <- add_cultivar(cul_tbl, cul_ingeno, cv_name, cv_ecode, cv_ppars, cv_gpars)
  DSSAT::write_cul(cul_tbl_new, file_name = cul_file)
  message("Added cultivar ", cul_ingeno, " (", cv_name, ") to ", basename(cul_file))
}
```

**Cultivar parameters for `LL0001`** (from `DSSAT48.INP`):

| VSEN | PPSEN | P1    | P5    | PHINT | GRNO | MXFIL | STMMX | SLAP1 | ECO#   |
|------|-------|-------|-------|-------|------|-------|-------|-------|--------|
| 4.00 | 2.50  | 400.0 | 650.0 | 120.0 | 24.0 | 1.90  | 3.00  | 280.0 | IB0001 |

---

## Final Status

All 15 workflow steps pass with exit code 0.

```
Step 1:  ✓ Field data extracted
Step 2:  ✓ Production season identified
Step 3:  — Sensor step skipped (FROST_CLIENT_ID not set)
Step 4:  ✓ NASA POWER weather downloaded
Step 5:  ✓ Weather converted to ICASA
Step 6:  ✓ Combined weather assembled
Step 7:  ✓ Soil profile extracted
Step 8:  ✓ Growth stage dates looked up
Step 8b: ✓ Phenology converted to ICASA
Step 9:  ✓ Full ICASA dataset assembled
Step 10: ✓ Dataset converted to DSSAT
Step 11: ✓ Soil profile normalised (15 layers)
Step 12: ✓ Initial soil layers calculated
Step 13: ✓ DSSAT input files built
            └─ Soil file copied: LL.SOL → DE.SOL
            └─ Cultivar LL0001 already present in WHAPS048.CUL
Step 14: ✓ DSSAT simulation complete (TRT 1, 3, 7)
Step 15: ✓ Growth plot saved to simulations/growth_plot.png
```

**DSSAT simulation results:**

| TRT | N rate (kg/ha) | TOPWT (kg/ha) | HARWT (kg/ha) |
|-----|----------------|--------------|--------------|
| 1   | 0              | 9 134        | 4 535        |
| 3   | 147            | 19 294       | 8 129        |
| 7   | 180            | 20 342       | 8 305        |
