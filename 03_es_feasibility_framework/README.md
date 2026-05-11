# ES Feasibility Boundary — IEEE 33-Bus EV Study

**Paper:** *Feasibility Boundary of Electric Spring Deployment for Voltage Recovery in EV-Stressed Radial Distribution Feeders*

---

## What This Folder Is

Isolated research extension sitting inside the existing EV repo.
Does **not** touch any existing `module*.m` files.
Adds new framework on top of existing helpers (`solve_es_socp_opf_case`, `build_distflow_topology_from_branch_csv`, etc.).

```
ES_Feasibility_Boundary_IEEE33/
├── main/          ← ONE entry point — run this
├── data/          ← IEEE 33-bus constants and load profile
├── functions/     ← All new solver + analysis functions
├── plotting/      ← All figure generators
└── results/
    └── es_feasibility_boundary_ieee33/
        ├── tables/      ← CSV result tables (auto-created)
        ├── figures/     ← PNG + FIG plots (auto-created)
        └── raw_outputs/ ← MAT files for large data (auto-created)
```

---

## Requirements

| Tool | Version |
|------|---------|
| MATLAB | R2020a or newer |
| YALMIP | Latest (Jan Löfberg) |
| Gurobi | 9.x or 10.x |
| Gurobi MATLAB interface | must be on MATLAB path |

Verify Gurobi works: `gurobi_read` should not error.
Verify YALMIP works: `yalmip('version')` should print version.

---

## How to Run

### Quickest start (recommended first run)

```matlab
% 1. Open MATLAB
% 2. Navigate to the main folder:
cd 'C:\Users\HP\Downloads\EV Research code\ES_Feasibility_Boundary_IEEE33\main'

% 3. Run the master script:
run_es_feasibility_boundary_ieee33
```

The script auto-adds all needed paths. No manual `addpath` needed.

---

## Section Flags — Control What Runs

Top of `run_es_feasibility_boundary_ieee33.m` has toggle flags:

```matlab
run_A1_topology      = true;   % fast  (~5 sec)
run_A2_load_profile  = true;   % fast  (~2 sec)
run_A3_baseline      = true;   % fast  (~30 sec)
run_A4_stress_sweep  = true;   % fast  (~2 min)
run_A5_qg_reference  = true;   % medium (~5 min)

run_B2_weak_bus      = true;   % medium (~10 min)
run_B3_p1_p5_scan    = true;   % HEAVY  (~60-90 min, 70 cases)

run_C1_vsi           = true;   % medium (~5 min)
run_C2_ranking       = true;   % fast   (~1 min)
run_C3_heuristics    = true;   % medium (~20 min)

run_D1_misocp        = true;   % medium (~5 min, single case)
run_D2_budget_sweep  = true;   % HEAVY  (~4-8 hrs, 264 cases)
run_D3_min_count     = true;   % fast   (post-processing)
run_D4_misocp_vs_h   = true;   % medium (~30 min)
run_D5_infeasibility = true;   % medium (~varies)

run_E1_hybrid        = true;   % medium (~5 min, single case)
run_E2_hybrid_sweep  = true;   % HEAVY  (~3-5 hrs)

run_F1_scenarios     = true;   % fast   (~1 min)
run_F2_robustness    = true;   % medium (~30 min)
run_F3_risk          = true;   % fast   (~1 min)

run_G1_final_compare = true;   % medium (~20 min)
run_G2_summary_figs  = true;   % fast   (~2 min)
```

**First run recommended order** — skip heavy sweeps, get quick results:

```matlab
% Set these to false for first run:
run_B3_p1_p5_scan   = false;  % skip 70-case scan
run_D2_budget_sweep = false;  % skip 264-case MISOCP sweep
run_E2_hybrid_sweep = false;  % skip hybrid sweep
```

This gives full baseline + single MISOCP case + robustness in ~1-2 hours.

---

## Recommended Run Order (Step by Step)

### Step 1: Verify setup (~5 min)

Set only `run_A1_topology = true`, rest `false`.
Confirms BFS topology, 33 buses, 32 branches, all connected.
Output: `tables/table_topology_verification.csv`

### Step 2: Baseline (~30 min)

Set A1–A5 = true, rest false.
Produces no-support DistFlow results and Qg reference benchmark.
Shows how bad voltage is without ES.
Outputs in `tables/` and `figures/`.

### Step 3: Reproduce P1–P5 scan (~60-90 min)

Set B2, B3 = true.
Reproduces the 70-scenario feasibility boundary from prior work.
Confirms which placements are feasible/infeasible.
Output: `tables/table_p1_p5_feasibility.csv`, feasibility heatmap figures.

### Step 4: Voltage sensitivity + heuristics (~30 min)

Set C1, C2, C3 = true.
Computes perturbation-based VSI, ranks all 32 buses by voltage impact,
compares 5 placement methods at k = 2,4,7,11,16,20,24,32.

### Step 5: MISOCP single case (~5-10 min)

Set D1 = true, D2 = false.
Runs budget-constrained MISOCP at rho=0.70, u_min=0.20, N_ES=32.
Shows optimal binary ES placement for the best known operating point.

### Step 6: Full budget sweep (overnight / long run)

Set D2 = true.
Runs 11 × 6 × 4 = 264 MISOCP cases across N_ES, rho, u_min.
Saves partial results every (rho, u_min) pair — crash-safe.
Output: `tables/table_budget_misocp_sweep.csv`

### Step 7: Minimum ES count analysis (post D2)

Set D3, D4, D5 = true after D2 completes.
Extracts minimum feasible N_ES for each (rho, u_min).
Compares MISOCP vs heuristics at matched budget.
Diagnoses infeasible cases with voltage slack magnitude.

### Step 8: Hybrid ES + Qg sweep (overnight)

Set E2 = true.
Tests whether limited reactive support reduces ES count or curtailment.
5 × 2 × 8 × 5 = 400 cases.
Output: `tables/table_hybrid_es_qg_sweep.csv`

### Step 9: EV stress robustness (~30 min)

Set F1, F2, F3 = true.
Generates 4 deterministic EV stress scenarios (mult = 1.4, 1.6, 1.8, 2.0).
Tests C0–C3 solutions across all scenarios.
Computes CVaR_95, VaR_95, feasibility probability.

### Step 10: Final comparison and figures (~20 min)

Set G1, G2 = true.
Runs C0–C5 full comparison at rho=0.70, u_min=0.20.
Generates all publication-ready comparison figures.

---

## Output Files Reference

| File | What it contains |
|------|-----------------|
| `table_topology_verification.csv` | Pass/fail checks for IEEE 33-bus topology |
| `table_load_profile.csv` | 24h multiplier with EV evening peak |
| `table_no_support_baseline.csv` | Hour-by-hour Vmin, loss, violation count |
| `table_load_multiplier_sweep.csv` | Vmin vs load multiplier 1.0–1.8 |
| `table_qg_reference.csv` | Qg-only SOCP 24h results |
| `table_weak_bus_es_results.csv` | ES at {18,33} and {17,18,32,33} |
| `table_p1_p5_feasibility.csv` | 70-case P1–P5 scan results |
| `table_voltage_sensitivity.csv` | VSI per bus (raw + normalised) |
| `table_candidate_rankings.csv` | 5 ranking methods per bus |
| `table_heuristic_placement_comparison.csv` | 5 methods × 8 k values |
| `table_budget_misocp_sweep.csv` | 264-case MISOCP sweep |
| `table_minimum_es_count.csv` | Min N_ES per (rho, u_min) |
| `table_infeasibility_diagnostics.csv` | Voltage slack for infeasible cases |
| `table_misocp_vs_heuristics.csv` | MISOCP vs 5 heuristics at 4 parameter sets |
| `table_hybrid_es_qg_sweep.csv` | Hybrid sweep across Qg_frac |
| `table_min_es_under_qg_limits.csv` | Min ES at each Qg support level |
| `table_ev_stress_scenarios.csv` | EV stress scenario definitions |
| `table_ev_stress_robustness.csv` | Solution performance across scenarios |
| `table_voltage_risk_metrics.csv` | CVaR_95, VaR_95, feasibility probability |
| `table_final_case_comparison.csv` | C0–C5 full comparison |

---

## What Each New File Does

### data/

**`ieee33_bus_data.m`**
Returns IEEE 33-bus system constants: base voltage (12.66 kV), base power (1 MVA), per-unit bus loads (P, Q), Vmin/Vmax limits.
Used as reference — actual optimisation uses the existing CSV data files.

**`ieee33_line_data.m`**
Returns branch R and X in per-unit (Zbase = 12.66²/1 = 160.27 ohm).
Source: Baran & Wu (1989). All 32 branch impedances.

**`load_profile_24h.m`**
Returns 24×1 multiplier vector.
Off-peak 0.6×, daytime 1.0×, EV evening 1.8× (configurable), late 0.9×.
Used by `build_ieee33_network` to scale hourly loads.

---

### functions/

**`build_ieee33_network.m`**
Loads IEEE 33-bus topology and loads from existing CSV files.
Applies custom `ev_multiplier` to evening hours 17–21.
Returns `topo` and `loads` structs compatible with all solvers.
*Calls:* `build_distflow_topology_from_branch_csv`, `build_24h_load_profile_from_csv`

**`build_load_profile_24h.m`**
Applies 24h EV-stress profile to a flat base loads struct.
Thin wrapper — used when you already have base loads and want to rescale.

**`verify_radial_topology.m`**
BFS traversal from bus 1. Checks: 33 buses, 32 branches, tree structure (n_branch = n_bus - 1), all buses reachable, no self-loops. Returns pass/fail per check.

**`run_distflow_baseline.m`**
Runs no-ES, no-Qg DistFlow for all 24 hours.
Calls existing `run_distflow_bfs` iteratively.
Returns: V_all (33×24), Vmin_t, VminBus_t, loss_t, n_viol_t, violating bus list at peak hour.

**`solve_socp_opf_qg.m`**
Reactive-only SOCP OPF benchmark (no ES, no load curtailment).
Adds continuous Qg variables at each bus up to `Qg_max_pu` limit.
Minimises price-weighted losses subject to voltage constraints.
*Calls:* YALMIP + Gurobi

**`solve_es_fixed_placement.m`**
Thin wrapper around existing `solve_es_socp_opf_case`.
Accepts (es_buses, rho, u_min) directly, builds params struct internally.
Used by P1–P5 scan, heuristic comparison, robustness evaluation.

**`run_p1_p5_feasibility_scan.m`**
Runs all 70 combinations: 5 placements × 7 rho × 2 u_min.
Uses hard Vmin=0.95. Records feasible/infeasible for each case.
Matches the existing research findings from modules 8–15.
Saves `table_p1_p5_feasibility.csv`.

**`compute_voltage_sensitivity_index.m`**
Perturbation-based VSI (different from existing analytical VIS).
For each bus i: reduce load by 5%, re-run DistFlow, measure ΔVmin.
`VSI_i = ΔVmin / ΔP_curtail_i`
Higher VSI = curtailing load at bus i improves system voltage more.
Saves normalised scores and ranking.

**`rank_es_candidates.m`**
Generates 5 bus rankings:
1. Weakest voltage (lowest Vmin at peak hour)
2. End-feeder (largest sum of path R+X from root)
3. Highest load (largest mean P)
4. VSI (from `compute_voltage_sensitivity_index`)
5. Combined score = 0.6×VSI + 0.2×Load + 0.2×ElecDist

**`compare_candidate_placement_sets.m`**
Tests all 5 ranking methods at k = [2,4,7,11,16,20,24,32] ES buses.
Uses 3 reference parameter sets: (rho=0.50,umin=0), (0.60,0), (0.70,0.20).
Shows which heuristic needs fewest ES to reach feasibility.

**`solve_es_budget_misocp.m`** ← **MAIN NOVEL CONTRIBUTION**
Budget-constrained Mixed-Integer SOCP for ES placement.

Decision variables:
- `z(i)` ∈ {0,1} — binary ES installation at bus i
- `c(i,t)` ∈ [0, (1−u_min)×z(i)] — NCL curtailment fraction
- `v(i,t)`, `Pij`, `Qij`, `ell` — standard DistFlow variables
- `sv(i,t)` ≥ 0 — voltage slack (soft mode)

Key linking constraint (linear, not bilinear):
```
c(i,t) <= (1 - u_min) * z(i)
```
When z(i)=0: c(i,t)=0 (no ES action allowed).
When z(i)=1: c(i,t) can reach up to (1−u_min).

Power balance (linear in c — P_NCL is constant data):
```
P_eff(i,t) = P_load(i,t) - c(i,t) * P_NCL(i,t)
```

Budget: `sum(z) <= N_ES_max`

Two objective modes:
- `feasibility`: minimise total voltage slack → find feasibility boundary
- `planning`: weighted sum of loss + ES count + curtailment + slack

Solver: YALMIP + Gurobi (MISOCP). Outputs selected buses, Vmin, losses, curtailment, solve time, MIP gap.

**`run_es_budget_sweep.m`**
Outer loop over N_ES_max=[2,4,6,8,10,12,16,20,24,28,32], rho, u_min.
For each combo: solve feasibility-mode MISOCP, mark feasible if voltage slack ≤ 1e-6.
Saves partial results after each (rho, u_min) pair — crash protection.
264 total cases.

**`extract_es_misocp_solution.m`**
Organises raw MISOCP result struct into clean publication-ready format.
Adds: V_profile at worst hour, V_min per bus, n_viol_24h, per-ES curtailment.

**`identify_minimum_es_count.m`**
Post-processes budget sweep table.
For each (rho, u_min): finds smallest N_ES_max achieving voltage feasibility.
Records associated V_min, loss, curtailment, selected ES buses.
Generates `table_minimum_es_count.csv`.

**`diagnose_voltage_infeasibility.m`**
For infeasible cases: re-solves with soft voltage to quantify the voltage deficit.
Reports: total slack, max deficit bus, estimated extra rho needed.
Helps answer: "how close to feasibility is each infeasible case?"

**`compare_misocp_with_heuristics.m`**
At 4 selected (rho, u_min) sets: runs MISOCP, then runs each heuristic at the same N_ES budget.
Fair comparison — same device count, different placement strategy.
Answers: "does MISOCP actually beat heuristics or is it the same?"

**`solve_hybrid_es_qg_misocp.m`**
Extends `solve_es_budget_misocp` with continuous reactive support variables Qg(i,t).
Qg capacity = `Qg_limit_frac × 5%_of_peak_load` per bus.
ES binary decisions and Qg are optimised jointly.
Research question: can 25–50% reactive support reduce required ES count?

**`run_hybrid_es_qg_sweep.m`**
Sweeps rho × u_min × N_ES_max × Qg_frac (5 values: 0, 0.25, 0.50, 0.75, 1.00).
~400 cases. Tests cases H0 (ES only) through H6 (ES + full Qg).

**`generate_aggregate_ev_stress_scenarios.m`**
Creates deterministic EV scenarios by varying evening multiplier:
- S1: 1.4× (low EV)
- S2: 1.6× (medium EV)
- S3: 1.8× (base case)
- S4: 2.0× (extreme EV)
Optional stochastic: Normal(1.8, 0.1) clipped to [1.4, 2.1].
No individual EV constraints — pure aggregate load stress.

**`evaluate_solution_under_ev_stress.m`**
Tests selected solutions (C0–C4) across all EV scenarios.
For each (solution, scenario): solve and record feasibility, Vmin, loss, curtailment.
Builds robustness table used by risk metric computation.

**`compute_voltage_risk_metrics.m`**
Computes from robustness table:
- Feasibility probability = fraction of feasible scenarios
- Expected voltage violation = mean of max(0, 0.95 − Vmin)
- VaR_95 = 95th percentile scenario violation
- CVaR_95 = mean of worst 5% scenario violations

Lower CVaR_95 = more robust solution.

**`compare_final_ieee33_cases.m`**
Runs the 6 final cases at rho=0.70, u_min=0.20:
- C0: No support
- C1: Qg only
- C2: Weak-bus ES {18,33}
- C3: VSI top-7
- C4: MISOCP ES-only
- C5: Hybrid ES + 50% Qg
Returns comparison table with all metrics.

**`save_result_table.m`**
Utility: saves table to CSV (+ optional MAT), creates directory if missing.

---

### plotting/

All plot functions: `Visible=off`, save PNG + FIG, no display (runs headless).

| Function | What it plots |
|----------|--------------|
| `plot_ieee33_topology` | Schematic 33-bus feeder with optional highlighted buses |
| `plot_voltage_profile_peak` | V vs bus at peak hour, multiple cases overlaid |
| `plot_min_voltage_24h` | Vmin vs hour for multiple cases |
| `plot_load_multiplier_sweep` | Vmin and loss vs load multiplier |
| `plot_feasibility_heatmap` | 2D colour map: feasible (green) / infeasible (red) |
| `plot_voltage_sensitivity_bar` | VSI score per bus, top-10 highlighted |
| `plot_candidate_bus_topology` | Topology coloured by combined ranking score |
| `plot_placement_comparison_curve` | Metric vs k (ES count) per placement method |
| `plot_p1_p5_feasibility` | P1–P5 × rho feasibility map at given u_min |
| `plot_minimum_es_count_vs_rho` | Min N_ES vs rho for each u_min |
| `plot_minimum_es_count_vs_umin` | Min N_ES vs u_min for each rho |
| `plot_voltage_slack_vs_es_budget` | Log-scale slack vs N_ES — shows feasibility transition |
| `plot_selected_es_buses_topology` | Topology with MISOCP-selected buses marked |
| `plot_misocp_voltage_profile` | Bar chart V per bus at worst hour, ES buses marked |
| `plot_misocp_vs_heuristics` | Side-by-side Vmin and loss for MISOCP vs heuristics |
| `plot_min_es_count_vs_qg_limit` | Min ES count vs Qg_frac for each rho |
| `plot_curtailment_reduction_hybrid` | NCL curtailment reduction as Qg increases |
| `plot_hybrid_voltage_profiles` | Voltage profiles for H0–H6 hybrid cases |
| `plot_hybrid_cost_tradeoff` | Scatter: ES count vs curtailment for each Qg level |
| `plot_feasibility_probability_vs_rho` | Feasibility prob vs EV stress multiplier |
| `plot_cvar_voltage_risk_vs_es_count` | CVaR_95 and feasibility prob ranked by solution |
| `plot_final_case_comparison` | 4-panel bar chart: Vmin, loss, curtailment, ES count for C0–C5 |

---

## Research Contribution Summary

| Research question | Where answered |
|-------------------|----------------|
| Minimum rho for feasibility? | `table_budget_misocp_sweep.csv`, `fig_minimum_es_count_vs_rho` |
| Minimum u_min? | `table_minimum_es_count.csv`, `fig_minimum_es_count_vs_umin` |
| Minimum N_ES? | `table_minimum_es_count.csv` |
| Where to place ES? | `table_misocp_vs_heuristics.csv`, `fig_selected_misocp_buses` |
| Why weak-bus fails? | `table_weak_bus_es_results.csv` + VSI analysis |
| Does VSI beat weak-bus? | `table_heuristic_placement_comparison.csv` |
| Can Qg reduce ES count? | `table_hybrid_es_qg_sweep.csv`, `fig_min_es_count_vs_qg_limit` |
| Robustness under EV stress? | `table_voltage_risk_metrics.csv`, CVaR figures |

---

## How the New Code Connects to Existing Code

```
run_es_feasibility_boundary_ieee33.m  (new master runner)
  │
  ├── build_ieee33_network.m  (new)
  │     └── build_distflow_topology_from_branch_csv.m  [EXISTING]
  │     └── build_24h_load_profile_from_csv.m          [EXISTING]
  │
  ├── solve_es_fixed_placement.m  (new thin wrapper)
  │     └── solve_es_socp_opf_case.m                   [EXISTING]
  │
  ├── compute_voltage_sensitivity_index.m  (new)
  │     └── run_distflow_bfs.m                         [EXISTING]
  │
  ├── calculate_voltage_impact_score.m                 [EXISTING, called directly]
  │
  ├── solve_es_budget_misocp.m  (new — YALMIP/Gurobi MISOCP)
  ├── solve_hybrid_es_qg_misocp.m  (new — YALMIP/Gurobi MISOCP)
  └── solve_socp_opf_qg.m  (new — YALMIP/Gurobi SOCP)
```

---

## Troubleshooting

**"Missing branch.csv"** — Run from the `main/` folder, or from repo root. The script finds paths automatically via `mfilename('fullpath')`.

**Gurobi TimeLimit reached** — Increase `time_limit` in sweep options, or reduce sweep size. Partial results are saved so you can resume.

**YALMIP "No solver found"** — Add Gurobi to MATLAB path: `addpath('C:\gurobi\win64\matlab')`.

**Results look NaN** — Check if DistFlow converged (`run_distflow_bfs` needs flat-start converged network). Very high EV multipliers (>2.2) may cause divergence.

**Figures blank** — All figures set `Visible=off`. They are saved to `results/.../figures/` as PNG and FIG. Open the FIG files in MATLAB to inspect interactively.

---

*Branch: `feature/es-feasibility-boundary-ieee33`*  
*Do not merge to main until all results verified.*
