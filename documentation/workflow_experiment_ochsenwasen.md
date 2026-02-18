# Workflow Diagram – Ochsenwäsen Experiment

```mermaid
flowchart TD
    classDef inputCls fill:#dbeafe,stroke:#3b82f6,color:#1e40af
    classDef processCls fill:#dcfce7,stroke:#16a34a,color:#14532d
    classDef fileCls fill:#fef9c3,stroke:#ca8a04,color:#78350f
    classDef outputCls fill:#fce7f3,stroke:#db2777,color:#831843
    classDef coordCls fill:#ede9fe,stroke:#7c3aed,color:#3b0764

    COORDS["📍 Coordinates\nlon=10.645, lat=49.209"]:::coordCls

    subgraph FIELD["① Field Data · ICASA Template"]
        direction TB
        TMPL[/"template_icasa_vba.xlsm"/]:::inputCls
        P1["get_field_data()\nexp_id='HWOC2501'"]:::processCls
        P2["identify_production_season()\nperiod='cultivation_season'"]:::processCls
        TMPL --> P1
        P1 -->|"mngt_obs_icasa"| P2
    end

    subgraph SENSOR["② IoT Sensor Weather · FROST Server"]
        direction TB
        FROST[/"FROST Server\n(OGC SensorThings API)"/]:::inputCls
        P3["get_sensor_data()\nair_temp · solar_rad · precip"]:::processCls
        P4["convert_dataset()\nuser to icasa"]:::processCls
        FROST --> P3
        P3 -->|"tmp_weatherdata_sensor.json"| P4
    end

    subgraph NASASUB["③ NASA POWER Weather · Complementary"]
        direction TB
        NASA[/"NASA POWER API"/]:::inputCls
        P5["get_weather_data()\nsrc='nasa_power'"]:::processCls
        P6["convert_dataset()\nnasa-power to icasa"]:::processCls
        NASA --> P5
        P5 -->|"tmp_weatherdata_nasapower.json"| P6
    end

    subgraph SOILSUB["④ Soil Profile · SoilGrids"]
        direction TB
        SG[/"Dataverse API\n(SoilGrids DSSAT Profiles)"/]:::inputCls
        P8["get_soil_profile()"]:::processCls
        SG --> P8
    end

    subgraph PHENOSUB["⑤ Phenology · Observed Field Data"]
        direction TB
        PHEN[/"wheat_phenology_results.csv"/]:::inputCls
        P9["lookup_gs_dates()\nZadok scale: 10, 65, 87 · median"]:::processCls
        P10["convert_dataset()\nuser to icasa"]:::processCls
        F_GS[("tmp-phenology-icasa.json")]:::fileCls
        PHEN --> P9 --> P10 --> F_GS
    end

    subgraph INTEGR["⑥ Data Integration & Conversion"]
        direction TB
        P7["assemble_dataset()\nWeather: field + NASA POWER"]:::processCls
        F_WTH[("tmp_weatherdata_combined.json")]:::fileCls
        P11["assemble_dataset()\nfield data + soil + combined weather"]:::processCls
        F_ICASA[("tmp_icasa.json")]:::fileCls
        P12["convert_dataset()\nicasa to dssat"]:::processCls
        F_DSSAT[("dataset_dssat.json")]:::fileCls
        P7 --> F_WTH --> P11 --> F_ICASA --> P12 --> F_DSSAT
    end

    subgraph SIMPREP["⑦ Simulation Preparation"]
        direction TB
        P13["normalize_soil_profile()\ndepth_seq: 5–210 cm · linear"]:::processCls
        P14["calculate_initial_layers()\nAW=100% · N=50 kg/ha"]:::processCls
        P15["build_simulation_files()\nmodel=WHAPS · WATER=Y · NITRO=Y · TILL=Y"]:::processCls
        F_IN[("DSSAT Input Files\n.WHX / .SOL / .WTH")]:::fileCls
        P13 -->|"normalized SOIL"| P14
        P14 -->|"ICBL, SH2O, SNH4, SNO3"| P15
        P15 --> F_IN
    end

    subgraph SIMRUN["⑧ Simulation & Visualization"]
        direction TB
        P16["run_simulations()\nHWOC2501.WHX · treatments 1, 3, 7"]:::processCls
        OUT1[/"Sim Results\nplant_growth + SUMMARY"/]:::outputCls
        OUT2[/"Yield vs. Time Plot\nggplot2"/]:::outputCls
        P16 --> OUT1 --> OUT2
    end

    P2 -->|"cseason\n(date range)"| P3
    P2 -->|"cseason\n(date range)"| P5
    COORDS --> P3
    COORDS --> P5
    COORDS --> P8
    P4 -->|"wth_field_icasa"| P7
    P6 -->|"wth_nasa_icasa"| P7
    P1 -->|"mngt_obs_icasa"| P11
    P8 -->|"soil_icasa"| P11
    F_DSSAT -->|"dataset_dssat"| P13
    F_IN --> P16
```

## Legend

| Shape | Meaning |
|---|---|
| 🔵 Parallelogram | External input source or final output |
| 🟢 Rectangle | Processing step (R function call) |
| 🟡 Cylinder | Intermediate file written to `./archive/` |
| 🟣 Rectangle | Fixed coordinates (shared input) |

## Notes

- **⑤ Phenology** (`lookup_gs_dates` → `convert_dataset`) produces `tmp-phenology-icasa.json` but is not yet wired into the main `assemble_dataset` call in step ⑥; it is included here for completeness.
- Steps ② and ③ run in parallel and are both gated on the `cseason` date range derived from step ①.
- Step ④ (soil profile) is independent of the field data timing and can run in parallel with ②–③.
- The final simulation step requires a local installation of DSSATCSM.
