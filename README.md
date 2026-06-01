# EV Research — IEEE 33-Bus Electric Spring Study

**Research Question:** Can Electric Spring (ES) replace traditional reactive power support (STATCOM, ESS) for voltage control in EV-stressed radial distribution feeders?

**Answer:** Standard ES (active-curtailment only) cannot. ES-1 (Hou reactive model, 4 devices) fully replaces both STATCOM (7 devices) and ESS (3 devices).

**Tools:** MATLAB R2020a+, YALMIP, Gurobi
**Network:** IEEE 33-bus radial feeder (Baran & Wu), 10 MVA base
**EV stress:** 1.8× evening load multiplier, voltage limit 0.95 pu

---

## Start Here — Navigation Guide

**For understanding the full research:**
→ Read [`05_analysis/COMPLETE_STUDY_REPORT.md`](05_analysis/COMPLETE_STUDY_REPORT.md)  
Master document: problem explanation, all methods, all 24 modules, all 9 stages, results, terminology. **Start here.**

**For finding specific results:**
→ Use [`05_analysis/INDEX.md`](05_analysis/INDEX.md)  
Quick reference to locate figures, tables, and analysis by phase or stage.

**For running Phase 1 (modules 01–24):**
→ See `02_baseline_modules/MODULE_REFERENCE.txt`  
Central index with descriptions, dependencies, and recommended run order.

**For PV penetration study (Stage 10, feature branch only):**
→ Read [`03_es_feasibility_framework/STAGE10_PV_README.md`](03_es_feasibility_framework/STAGE10_PV_README.md)  
Complete documentation: modeling, assumptions, run instructions, expected results.

---

**Folder purposes:**
- **01_data/** — IEEE 33-bus network topology + load profiles (input data, read-only)
- **02_baseline_modules/** — Phase 1 exploratory pipeline (modules 01–24)
- **03_es_feasibility_framework/** — Phase 2 rigorous framework (stages 1–9, stage 10 on feature branch)
- **04_results/** — Generated outputs (figures, tables, MATLAB checkpoints)
- **05_analysis/** — Master documentation + result summaries organized by phase

---

## Repository Structure

```
EV Research code/
│
├── 01_data/                         IEEE 33-bus network + load profiles (input data)
│
├── 02_baseline_modules/             PHASE 1: Exploratory pipeline (modules 01–24)
│   ├── module01.m – module24.m      Run sequentially; each self-contained
│   ├── main_run_es_research.m       Master runner for all modules
│   ├── MODULE_REFERENCE.txt         Module index and descriptions
│   └── shared/                      Helper functions used by all modules
│
├── 03_es_feasibility_framework/     PHASE 2: Rigorous comparative framework (stages 1–9, stage 10 on feature branch)
│   ├── data/                        IEEE 33-bus network data + 24h profile
│   ├── functions/                   Solvers: SOCP/MISOCP for STATCOM, ESS, ES, ES-1, hybrids
│   ├── main/                        Stage runners (run_stage1 → run_stage9, run_stage10)
│   ├── plotting/                    Figure generation functions
│   └── STAGE10_PV_README.md         PV penetration study (feature branch only)
│
├── 04_results/                      ALL OUTPUTS: figures, tables, MATLAB checkpoints
│   ├── module_outputs/              Phase 1 raw outputs (modules 01–24)
│   └── es_framework/                Phase 2 outputs (stages 1–9, stage 10)
│       ├── figures/                 Plots (.png + .fig)
│       │   ├── stage9/              Publication figures (fig1–fig6)
│       │   └── stage10/             PV study figures
│       ├── tables/                  Result tables (.csv) — one per stage
│       └── raw_outputs/             MATLAB checkpoints (.mat)
│
└── 05_analysis/                     DOCUMENTATION & RESULT SUMMARIES
    ├── COMPLETE_STUDY_REPORT.md     ← READ THIS FIRST (master document)
    ├── INDEX.md                     Navigation guide for all results
    └── result_summaries/            Phase 1 outputs organized by module
        ├── 00_publication_figures/  Ready-to-use publication figures
        ├── 01_baseline_distflow/    Network + DistFlow baseline
        ├── 02_qg_opf_baseline/      Qg-only OPF results
        └── 03–13_module_results/    Modules 8–9 detailed breakdowns
```

---

## How to Run

### Phase 1 — Exploratory Modules (01–24)

```matlab
cd('C:\Users\HP\Downloads\EV Research code')   % repo root — REQUIRED
addpath('02_baseline_modules')
addpath('02_baseline_modules/shared')
module01                   % run one module
% or run all:
main_run_es_research
```

### Phase 2 — ES Feasibility Framework (Stages 1–9)

```matlab
cd('03_es_feasibility_framework/main')

run_stage1_baseline_corrected    % baseline: no-support, Qg, standard ES
run_stage2_statcom               % STATCOM minimum count sweep
run_stage3_ess                   % ESS minimum count sweep
run_stage4_marginal_value        % standard ES substitution curves
run_stage5_joint                 % joint ES + STATCOM + ESS optimisation
run_stage6_es1                   % ES-1 (Hou reactive model) standalone
run_stage7_es1_hybrid            % ES-1 substitution curves
run_stage8_es1_joint             % ES-1 joint solver
run_stage9_publication_figures   % generate all publication figures

% Post-processing analysis:
% Integrated ESS sensitivity and device composition analysis (recommended):
run_ess_and_device_composition_analysis  % Master runner: ESS rating sensitivity + device composition

% or run individually:
run_ess_rating_sensitivity               % ESS installed-rating sensitivity analysis
run_device_composition_analysis          % Device composition and installed capacity analysis

% Results saved to 04_results/es_framework/
```

### Phase 2 — Stage 10 (Feature Branch)

**Stage 10: PV Penetration Study** is available on a dedicated feature branch:

```bash
git checkout feature/stage10-pv-penetration
```

Then in MATLAB:
```matlab
cd('03_es_feasibility_framework/main')
run_stage10_pv_penetration       % PV penetration with ES-1 reactive support
```

See `03_es_feasibility_framework/STAGE10_PV_README.md` for full documentation.

---

## Phase 1 — Module Sequence

| Stage | Modules | What It Does |
|---|---|---|
| Network setup | 01–03 | IEEE 33-bus topology, DistFlow baseline, 24h load profile |
| Baseline OPF | 04–06 | SOCP OPF with Qg reactive support, EV stress sweep |
| ES scenarios | 07–09 | Fixed-bus ES placement, multi-scenario exploration |
| ES optimisation | 10–14 | Distributed ES, hybrid Qg+ES, heterogeneous NCL |
| Advanced ES | 15–18 | 2nd-gen reactive ES inverters, full hybrid, feasibility scan |
| ES placement | 19–22 | VSI bus ranking, greedy placement, MISOCP optimisation |
| Sensitivity | 23–24 | Budget sensitivity, benchmark comparison |

**Detailed module reference:** See `02_baseline_modules/MODULE_REFERENCE.txt` for full index, descriptions, and run order.

---

## Phase 2 — Stage Sequence

| Stage | Runner | Question answered |
|---|---|---|
| 1 | `run_stage1_baseline_corrected` | What does the network do without support, with Qg, with standard ES? |
| 2 | `run_stage2_statcom` | How many STATCOM devices are needed? |
| 3 | `run_stage3_ess` | How many ESS devices are needed? |
| 4 | `run_stage4_marginal_value` | How much can standard ES reduce the STATCOM/ESS requirement? |
| 5 | `run_stage5_joint` | Does joint ES+STATCOM+ESS optimisation improve on Stage 4? |
| 6 | `run_stage6_es1` | Can ES-1 (Hou reactive model) achieve voltage recovery standalone? |
| 7 | `run_stage7_es1_hybrid` | Can ES-1 fully substitute STATCOM and ESS? |
| 8 | `run_stage8_es1_joint` | What is the device trade-off curve for ES-1 + supplemental hardware? |
| 9 | `run_stage9_publication_figures` | Generate all 6 publication figures |
| **10*** | **`run_stage10_pv_penetration`** | **How does PV penetration affect feeder voltage, and can ES-1 improve hosting capacity?** |
| Post-proc | `run_device_composition_analysis` | Compare all device compositions with installed rating information |

*Stage 10 is on `feature/stage10-pv-penetration` branch. All other stages on `main`.

---

## Key Results

| Technology | Min devices | V_min (pu) | Loss (pu) | Replaces STATCOM? | Replaces ESS? |
|---|---|---|---|---|---|
| No support | — | 0.8308 | 0.671 | — | — |
| STATCOM only | 7 | 0.9500 | 0.537 | Baseline | No |
| ESS only | 3 | 0.9500 | 0.434 | No | Baseline |
| Standard ES (all 32 buses) | 32 | 0.9324 | 0.118 | No | No |
| Std ES + STATCOM (floor) | 32 ES + 2 STATCOM | 0.9500 | 0.079 | Partial | — |
| Std ES + ESS (floor) | 32 ES + 1 ESS | 0.9544 | 0.083 | — | Partial |
| **ES-1 only (Hou model)** | **4** | **0.9500** | **0.381** | **Yes** | **Yes** |
| ES-1 Joint (4 devices) | 4 ES-1 | 0.9500 | — | Yes | Yes |

**Standard ES substitution floors:** STATCOM floor = 2, ESS floor = 1 (cannot be broken at any ES budget).
**ES-1 at N=4:** Fully substitutes both. No supplemental hardware needed.

---

## Documentation

**Key documents** (see "Start Here" for guidance):

| Document | Location | Content |
|----------|----------|---------|
| **COMPLETE_STUDY_REPORT.md** | `05_analysis/` | Full explanation of problem, all modules, all stages, results — **read this for deep understanding** |
| **INDEX.md** | `05_analysis/` | Navigation guide to find results by phase, stage, or topic — **read this to locate specific outputs** |
| **MODULE_REFERENCE.txt** | `02_baseline_modules/` | All 24 modules indexed with descriptions, dependencies, run order — **read this to run Phase 1** |
| **STAGE10_PV_README.md** | `03_es_feasibility_framework/` | PV penetration study (feature branch only) — modeling, assumptions, run steps — **read this for Stage 10** |

**Output locations:**

| What | Where |
|-----|-------|
| Publication figures | `04_results/es_framework/figures/stage9/` (fig1–fig6) + `stage10/` (fig1–fig5) |
| Result tables (CSV) | `04_results/es_framework/tables/` — one per stage (stages 1–10) |
| Phase 1 analysis | `05_analysis/result_summaries/` — organized by module type (modules 8–9 detailed) |
