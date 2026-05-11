# EV Research — IEEE 33-Bus Electric Spring Study

**Research Question:** Can Electric Spring (ES) replace traditional reactive power support for voltage control in EV-stressed radial distribution feeders?

**Tools:** MATLAB R2020a+, YALMIP, Gurobi

---

## Repository Structure (Sequential)

```
EV Research code/
│
├── 01_data/                        Input data: IEEE 33-bus network CSVs
│                                   (branch topology, base load profiles)
│
├── 02_baseline_modules/            Research pipeline — Modules 01–24
│   ├── module01.m – module24.m     Run in order; each is self-contained
│   ├── module*.txt                 Plain-text explanation for each module
│   ├── main_run_es_research.m      Master runner (runs all modules)
│   ├── MODULE_REFERENCE.txt        Full module index with descriptions
│   └── shared/                     Helper functions used by modules
│
├── 03_es_feasibility_framework/    ES Feasibility Boundary Framework
│   ├── data/                       Framework-specific data files
│   ├── functions/                  Core SOCP/MISOCP solvers + analysis
│   ├── main/                       run_es_feasibility_boundary_ieee33.m
│   └── plotting/                   All figure-generation functions
│
├── 04_results/                     All generated outputs
│   ├── module_outputs/             Raw outputs from Modules 01–24
│   │   ├── out_distflow/           Module 01–02: DistFlow baseline
│   │   ├── out_loads/              Module 03: Load profiles
│   │   ├── out_socp_opf_gurobi/    Module 04: SOCP OPF results
│   │   ├── out_socp_opf_gurobi_es/ Module 07–08: ES scenario results
│   │   └── out_module9/            Modules 09–24: Distributed ES studies
│   └── es_framework/               Outputs from 03_es_feasibility_framework
│       ├── figures/                All generated plots (.fig + .png)
│       ├── tables/                 Result tables (.csv)
│       └── raw_outputs/            MATLAB workspace checkpoints (.mat)
│
└── 05_analysis/                    Curated analysis and publication materials
    ├── RESULTS_ANALYSIS.md         Full plain-language explanation of results
    ├── EV_RESEARCH_RESULTS_ANALYSIS.html  Same, as interactive HTML
    └── result_summaries/           Organized by study stage
        ├── 00_publication_figures/ Ready-to-use publication figures
        ├── 01_baseline_distflow/   Baseline DistFlow results
        ├── 02_qg_opf_baseline/     Qg OPF reference results
        ├── 03_module8_scenarios/   Multi-scenario ES results
        ├── 04_module9A_distributed/ ... to 13_benchmark_comparison/
```

---

## How to Run

### Modules 01–24 (Baseline Pipeline)
```matlab
cd('C:\Users\HP\Downloads\EV Research code')   % repo root — REQUIRED
addpath('02_baseline_modules')
addpath('02_baseline_modules/shared')
module01          % run individually
% or:
main_run_es_research   % run all
```

### ES Feasibility Boundary Framework
```matlab
cd('03_es_feasibility_framework/main')
run_es_feasibility_boundary_ieee33
% Results saved to 04_results/es_framework/
```

---

## Module Sequence Summary

| Stage | Modules | What It Does |
|-------|---------|--------------|
| Network Setup | 01–03 | Build IEEE 33-bus topology, DistFlow baseline, load profile |
| Baseline OPF | 04–06 | SOCP OPF with reactive support (Qg), stress sweep |
| ES Scenarios | 07–09 | ES placement at fixed buses, scenario framework |
| ES Optimization | 10–14 | Distributed ES, hybrid Qg+ES, heterogeneous NCL |
| Advanced ES | 15–18 | 2nd-gen ES, full hybrid, feasibility scan |
| ES Placement | 19–22 | VSI ranking, greedy placement, MISOCP optimization |
| Sensitivity | 23–24 | Budget sensitivity, benchmark comparison |

See `02_baseline_modules/MODULE_REFERENCE.txt` for the full table.

---

## Key Findings
See `05_analysis/RESULTS_ANALYSIS.md` for plain-language results, or open `05_analysis/EV_RESEARCH_RESULTS_ANALYSIS.html` in a browser for the interactive version.
