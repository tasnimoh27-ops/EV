# EV Research — IEEE 33-Bus Electric Spring Study

**Research Question:** Can Electric Spring (ES) replace traditional reactive power support (STATCOM, ESS) for voltage control in EV-stressed radial distribution feeders?

**Answer:** Standard ES (active-curtailment only) cannot. ES-1 (Hou reactive model, 4 devices) fully replaces both STATCOM (7 devices) and ESS (3 devices).

**Tools:** MATLAB R2020a+, YALMIP, Gurobi
**Network:** IEEE 33-bus radial feeder (Baran & Wu), 10 MVA base
**EV stress:** 1.8× evening load multiplier, voltage limit 0.95 pu

---

## Repository Structure

```
EV Research code/
│
├── 01_data/                         Input data: IEEE 33-bus network CSVs
│                                    (branch topology, base load profiles)
│
├── 02_baseline_modules/             Phase 1 — Exploratory pipeline (Modules 01–24)
│   ├── module01.m – module24.m      Run in order; each is self-contained
│   ├── main_run_es_research.m       Master runner (runs all modules)
│   ├── MODULE_REFERENCE.txt         Full module index with descriptions
│   └── shared/                      Helper functions used across modules
│
├── 03_es_feasibility_framework/     Phase 2 — Rigorous comparative study (Stages 1–9)
│   ├── data/                        IEEE 33-bus network + 24h load profile
│   ├── functions/                   SOCP/MISOCP solvers for all technologies
│   │   ├── solve_statcom_misocp.m
│   │   ├── solve_ess_misocp.m
│   │   ├── solve_es1_misocp.m          ← ES-1 Hou reactive model
│   │   ├── solve_es1_statcom_misocp.m
│   │   ├── solve_es1_ess_misocp.m
│   │   └── solve_es1_statcom_ess_misocp.m
│   ├── main/                        Stage runner scripts (run_stage1 → run_stage9)
│   └── plotting/                    Figure generation functions
│
├── 04_results/                      All generated outputs
│   ├── module_outputs/              Raw outputs from Modules 01–24
│   │   ├── out_distflow/            Modules 01–02: DistFlow baseline
│   │   ├── out_loads/               Module 03: Load profiles
│   │   ├── out_socp_opf_gurobi/     Module 04: SOCP OPF with Qg
│   │   ├── out_socp_opf_gurobi_es/  Modules 07–08: ES scenario results
│   │   └── out_module9/             Modules 09–24: All distributed ES studies
│   └── es_framework/                Outputs from Phase 2 (Stages 1–9)
│       ├── figures/                 Exploratory plots (.fig + .png)
│       │   └── stage9/              Publication figures (fig1–fig6)
│       ├── tables/                  Result tables (.csv) — one per stage
│       └── raw_outputs/             MATLAB workspace checkpoints (.mat)
│
└── 05_analysis/
    ├── COMPLETE_STUDY_REPORT.md     ← Single master document — read this first
    └── result_summaries/            Raw outputs organised by study stage
        ├── 00_publication_figures/  Ready-to-use publication figures (Phase 1)
        ├── 01_baseline_distflow/    Baseline DistFlow results
        ├── 02_qg_opf_baseline/      Qg OPF reference results
        ├── 03_module8_scenarios/    Module 8 multi-scenario results
        └── 04_module9A/ … 13_/      Module 9 submodule outputs
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

% Results saved to 04_results/es_framework/
```

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

**`05_analysis/COMPLETE_STUDY_REPORT.md`** — Single master document covering everything: problem setup, network description, all 24 modules explained with results, all 9 stages explained with results, complete figure and table index, final synthesis. Read this to understand the full research.

**`04_results/es_framework/figures/stage9/`** — Six publication-ready figures (fig1–fig6).

**`04_results/es_framework/tables/`** — One CSV result table per stage.
