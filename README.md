# EV Research — Distribution Grid Analysis Toolkit

A MATLAB-based toolkit for analyzing the impact of Electric Vehicle (EV) integration on power distribution networks. Uses the **IEEE 33-bus test system** to study voltage stability, power losses, and optimal reactive power dispatch.

---

## What It Does

- Generates 24-hour load profiles for all buses
- Builds the network topology using a BFS spanning tree
- Runs power flow analysis (DistFlow algorithm)
- Identifies voltage violations and critical buses
- Optimizes reactive power dispatch using SOCP (Second-Order Cone Programming)

---

## Files

| File | Description |
|------|-------------|
| `build_24h_load_profile_from_csv.m` | Generates 24-hour active/reactive load profiles |
| `Plot_the_graph_from_load_profile.m` | Plots the load profile graph |
| `build_distflow_topology_from_branch_csv.m` | Builds radial network topology from branch data |
| `topology_construction_verification.m` | Validates the constructed topology |
| `run_distflow_bfs.m` | Core DistFlow power flow solver (iterative BFS) |
| `distflow_solver_analysis.m` | Main analysis script — runs 4-stage voltage analysis |
| `optimization.m` | Advanced SOCP-OPF optimization for reactive power control |

---

## How to Run

### Requirements
- MATLAB
- [YALMIP](https://yalmip.github.io/) — optimization modeling toolbox
- [GUROBI](https://www.gurobi.com/) — convex optimization solver
- Input data folder: `./mp_export_case33bw/` containing:
  - `loads_base.csv` — base load data per bus
  - `branch.csv` — network branch data

### Steps

1. **Generate load profiles**
   ```matlab
   load_data = build_24h_load_profile_from_csv('./mp_export_case33bw/loads_base.csv', 'system');
   ```

2. **Build network topology**
   ```matlab
   topo = build_distflow_topology_from_branch_csv('./mp_export_case33bw/branch.csv');
   ```

3. **Run main analysis** (voltage profiles, stress tests, VAR support)
   ```matlab
   run distflow_solver_analysis
   ```

4. **Run optimization** (SOCP-OPF for 24-hour reactive power dispatch)
   ```matlab
   run optimization
   ```

---

## Outputs

All results are saved to `./out_distflow/`:

- **CSV files** — voltage profiles, loss summaries, OPF results
- **PNG plots** — voltage envelopes, loss curves, cost analysis

---

## Network

- **Test system**: IEEE 33-bus radial distribution network
- **Voltage limits**: 0.95 – 1.05 pu
- **Time horizon**: 24 hours
- **Pricing**: Time-of-use (off-peak, shoulder, evening peak)
