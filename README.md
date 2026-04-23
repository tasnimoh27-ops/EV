# EV Research — Distribution Grid Analysis Toolkit

A MATLAB-based research toolkit for analysing EV integration and smart-load (Electric Spring) control on power distribution networks. Uses the **IEEE 33-bus radial test feeder** as the benchmark system.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Technical Background](#2-technical-background)
   - [IEEE 33-Bus Feeder](#21-ieee-33-bus-feeder)
   - [DistFlow Equations](#22-distflow-equations)
   - [SOCP Relaxation](#23-socp-relaxation)
   - [Electric Spring Model](#24-electric-spring-model)
3. [Module Architecture](#3-module-architecture)
4. [Module 8 — ES Smart-Load SOCP OPF (Deep Dive)](#4-module-8--es-smart-load-socp-opf)
   - [Problem Formulation](#41-problem-formulation)
   - [Scenario Design](#42-scenario-design)
   - [Files](#43-files)
5. [Results and Interpretation](#5-results-and-interpretation)
   - [Module 7 Baseline](#51-module-7-baseline-reactive-power-compensation)
   - [Scenario A — Strict Benchmark](#52-scenario-a--strict-benchmark)
   - [Scenario B — Feasible Hard-Constrained](#53-scenario-b--feasible-hard-constrained)
   - [Scenario C — Soft-Constrained Diagnostic](#54-scenario-c--soft-constrained-diagnostic)
   - [Scenario D — Expanded ES Bus Set](#55-scenario-d--expanded-es-bus-set)
   - [Scenario E — Full Controllability Upper Bound](#56-scenario-e--full-controllability-upper-bound)
   - [Scenario F — Lambda Sensitivity](#57-scenario-f--lambda-sensitivity)
6. [Key Research Finding](#6-key-research-finding)
7. [Output Files Reference](#7-output-files-reference)
8. [How to Run](#8-how-to-run)

---

## 1. Project Overview

This toolkit implements a progressive sequence of power systems analyses:

| Module | Script | What it does |
|--------|--------|--------------|
| 1 | `build_24h_load_profile_from_csv.m` | Generate 24-hour P/Q load profiles for all 33 buses |
| 2 | `Plot_the_graph_from_load_profile.m` | Visualise the load profiles |
| 3 | `build_distflow_topology_from_branch_csv.m` | Build radial BFS topology from branch data |
| 4 | `topology_construction_verification.m` | Validate the constructed topology |
| 5 | `run_distflow_bfs.m` | Core DistFlow power flow solver |
| 6 | `distflow_solver_analysis.m` | 4-stage voltage analysis and stress testing |
| 7 | `optimization.m` | SOCP-OPF with reactive power (Qg) control |
| **8** | `run_socp_opf_24h_yalmip_gurobi_es.m` | **ES smart-load SOCP-OPF (single run)** |
| **8R** | `run_es_scenario_framework.m` | **Multi-scenario ES research framework** |

---

## 2. Technical Background

### 2.1 IEEE 33-Bus Feeder

The **IEEE 33-bus test feeder** is the standard benchmark for radial distribution network research. Key properties:

- **33 buses**, **32 branches** (radial, tree topology)
- Substation (slack bus) at **bus 1**, Vslack = 1.0 pu
- Two long branches cause naturally low voltages at the endpoints:
  - **Main branch**: buses 2 → 3 → … → 18 (17 buses deep)
  - **Lateral branch**: buses 3 → 23 → 24 → … → 33 (then 26 → 27 → … → 33)
- **Weakest buses under full load**: bus 18 (~0.905 pu) and bus 33 (~0.920 pu)
- High **R/X ratio** (resistive-dominant lines), meaning real-power flow drives most of the voltage drop

### 2.2 DistFlow Equations

The **DistFlow model** (Baran & Wu, 1989) is the standard power flow model for radial distribution networks. For each branch *k* connecting parent bus *i* to child bus *j*:

```
Active power balance:
  Pij(k) = Pd_eff(j) + Σ_{children of j} Pij(m) + R(k)·ℓ(k)

Reactive power balance:
  Qij(k) = Qd_eff(j) + Σ_{children of j} Qij(m) + X(k)·ℓ(k)

Voltage drop equation:
  V²(j) = V²(i) - 2·[R(k)·Pij(k) + X(k)·Qij(k)] + [R(k)² + X(k)²]·ℓ(k)

Current-power relationship (Ohm's law):
  Pij(k)² + Qij(k)² = ℓ(k)·V²(i)      ← this is the non-convex constraint
```

where:
- `Pij(k)`, `Qij(k)` = active/reactive power flow on branch k (MW, MVAr)
- `ℓ(k)` = squared current magnitude I²(k) (A²)
- `V²(j)` = squared voltage magnitude at bus j (pu²)
- `R(k)`, `X(k)` = branch resistance/reactance (pu)
- `Pd_eff(j)`, `Qd_eff(j)` = effective demand at bus j (pu)

The **voltage drop equation** is key: voltage at bus j depends on BOTH the R·P and X·Q terms. This means:
- Reducing P (via load curtailment or ES) reduces the `R(k)·Pij(k)` drop
- Injecting Q (reactive power from capacitors or generators) reduces the `X(k)·Qij(k)` drop

### 2.3 SOCP Relaxation

The exact DistFlow equation `Pij² + Qij² = ℓ·V²(i)` is non-convex (quadratic equality). The standard approach is the **SOCP relaxation** (Farivar & Low, 2013):

```
Pij² + Qij² ≤ ℓ·V²(i)    [relaxed to inequality → convex SOCP]
```

In Lorentz cone form (as used in YALMIP):
```
‖ [2·Pij; 2·Qij; ℓ - V²(i)] ‖₂ ≤ ℓ + V²(i)
```

This relaxation is **exact** (tight at optimality) for radial networks under typical operating conditions, meaning the SOCP solution is also the true optimal AC power flow solution. This is a well-established result in the literature and is the foundational justification for using SOCP-OPF here.

**Why SOCP matters**: SOCP problems are convex and solvable to global optimality in polynomial time. Gurobi can solve them reliably and efficiently, unlike non-convex ACOPF which has no global optimality guarantee.

### 2.4 Electric Spring Model

An **Electric Spring (ES)** is a smart-load device (concept proposed by Hui et al., 2012) that sits in series with a non-critical load (NCL) and controls the voltage across it. In the equivalent circuit model used here:

```
Total demand at ES bus j:
  Pd(j,t) = Pcl(j,t) + Pncl(j,t)

where:
  Pcl(j,t)   = (1 - ρ) · Pd(j,t)      ← Critical Load: ALWAYS fully served
  Pncl0(j,t) =       ρ  · Pd(j,t)      ← Non-Critical Load baseline

Effective demand after ES control:
  Pd_eff(j,t) = Pcl(j,t) + u(j,t) · Pncl0(j,t)
              = (1-ρ)·Pd(j,t) + u(j,t)·ρ·Pd(j,t)
```

**Parameters**:
- **ρ (rho)**: NCL fraction — what fraction of total load is controllable. Set per bus.
- **u(j,t)**: NCL scaling factor (decision variable). Bounded as `u_min ≤ u ≤ 1`.
  - `u = 1` → full demand served (no curtailment)
  - `u = u_min` → maximum curtailment; NCL reduced to `u_min·ρ·Pd`
- **Curtailment ratio**: `c(j,t) = 1 - u(j,t)` ∈ [0, 1-u_min]

**Convexity**: Because `Pncl0(j,t)` is **known data** (a constant), the term `u(j,t) · Pncl0(j,t)` is **linear** in the decision variable `u(j,t)`. This keeps the power balance constraints affine, preserving the SOCP structure. There is no bilinear product of two decision variables.

---

## 3. Module Architecture

```
mp_export_case33bw/
  branch.csv          ← Branch R, X, B data for 33-bus feeder
  loads_base.csv      ← Base active/reactive load per bus (MW, MVAr)

out_loads/
  loads_P24.csv       ← 33×24 active load matrix (all buses, all hours)
  loads_Q24.csv       ← 33×24 reactive load matrix

out_socp_opf_gurobi/  ← Module 7 results (reactive power OPF baseline)
  opf_summary_24h_cost.csv
  V_bus_by_hour.csv
  Qg_bus_by_hour.csv

out_socp_opf_gurobi_es/  ← Module 8 results (ES smart-load OPF)
  scenario_A_strict/
  scenario_B_feasible/
  scenario_C_soft_diag/
  scenario_D_expanded/
  scenario_E_full_ctrl/
  scenario_F_lambda0/
  comparison/
    scenario_comparison.csv
```

---

## 4. Module 8 — ES Smart-Load SOCP OPF

### 4.1 Problem Formulation

Module 8 solves the following **SOCP Optimal Power Flow** problem:

**Decision variables** (over 33 buses × 24 hours):
- `v(j,t)` — squared voltage V²(j,t) ∈ [Vmin², Vmax²]
- `Pij(k,t)`, `Qij(k,t)` — branch power flows
- `ℓ(k,t)` — squared branch current ≥ 0
- `u(j,t)` — NCL scaling at ES buses ∈ [u_min, 1]; fixed to 1 at non-ES buses
- `c(j,t) = 1 - u(j,t)` — curtailment auxiliary variable ≥ 0

**Objective** (minimise):
```
min  Σ_t  price(t) · Σ_k  R(k) · ℓ(k,t)        [weighted resistive losses]
   + λ_u · Σ_{j ∈ ES buses} Σ_t  c(j,t)        [NCL curtailment penalty]
```

**Constraints**:
```
DistFlow power balance (for each non-root bus j, each hour t):
  Pij(kpar,t) = [Pd_fixed(j,t) + u(j,t)·Pncl0(j,t)] + Σ_children Pij + R(kpar)·ℓ(kpar,t)
  Qij(kpar,t) = [Qd_fixed(j,t) + u(j,t)·Qncl0(j,t)] + Σ_children Qij + X(kpar)·ℓ(kpar,t)

Voltage drop:
  v(j,t) = v(i,t) - 2[R(kpar)·Pij(kpar,t) + X(kpar)·Qij(kpar,t)] + (R²+X²)·ℓ(kpar,t)

SOCP cone (Lorentz form):
  ‖[2·Pij; 2·Qij; ℓ-v(i)]‖₂ ≤ ℓ + v(i)

Voltage bounds:
  Vmin² ≤ v(j,t) ≤ Vmax²;   v(root,t) = 1.0

ES control bounds:
  u_min ≤ u(j,t) ≤ 1  for j ∈ ES buses
  u(j,t) = 1           for j ∉ ES buses

Curtailment link:
  c(j,t) = 1 - u(j,t) ≥ 0
```

**Key difference from Module 7**: Module 7 adds reactive power generators `Qg(j,t)` at every bus and minimises losses by dispatching them. Module 8 replaces that with ES NCL curtailment — no reactive power injection is added.

**Time-of-use price profile** (same in both modules for fair comparison):
```
Hours 1–6:   price = 0.6   (off-peak overnight)
Hours 7–16:  price = 1.0   (shoulder / daytime)
Hours 17–21: price = 1.8   (evening peak)
Hours 22–24: price = 0.9   (late shoulder)
```

### 4.2 Scenario Design

Six scenarios test different design choices. All use the IEEE 33-bus feeder, Vmin=0.95 pu, Vmax=1.05 pu, λ_u=5.0 (except F), and 24-hour TOU pricing.

| Scenario | ES Buses | ρ (rho) | u_min | Soft V? | Research Question |
|----------|----------|---------|-------|---------|-------------------|
| **A** — Strict Benchmark | 18, 33 | 0.40 | 0.20 | No | Replicates original settings; expected INFEASIBLE |
| **B** — Feasible Hard | 18, 33 | 0.60 | 0.00 | No | Larger NCL + full curtailment; can this fix it? |
| **C** — Soft Diagnostic | 18, 33 | 0.40 | 0.20 | Yes (λ_sv=1000) | Where/when does Scenario A violate Vmin? |
| **D** — Expanded Set | 17,18,32,33 | 0.40 | 0.20 | No | Does adding upstream buses help? |
| **E** — Full Control | 18, 33 | 0.80 | 0.00 | No | Theoretical upper bound for this placement |
| **F** — λ Sensitivity | 18, 33 | 0.60 | 0.00 | No | Remove curtailment cost; does it change feasibility? |

**Scenario A load-floor analysis** (why expected to be infeasible):
```
Minimum effective demand = CL + u_min · NCL
  = (1 - ρ) · Pd + u_min · ρ · Pd
  = (1 - 0.40) · Pd + 0.20 · 0.40 · Pd
  = 0.60 · Pd + 0.08 · Pd
  = 0.68 · Pd

→ Even at maximum curtailment, bus 18 still carries 68% of its original demand.
  The residual R·P drop along the 17-bus main branch is too large to satisfy V ≥ 0.95 pu.
```

**Scenario B load-floor analysis** (why it might seem feasible but isn't):
```
Minimum effective demand = (1 - 0.60) · Pd + 0.0 · 0.60 · Pd = 0.40 · Pd

→ Only 40% of demand remains at bus 18 at maximum curtailment.
  Despite this, the problem is still infeasible because the R·P drop from the
  REMAINING 0.40·Pd and from all intermediate buses 2–17 still accumulates
  to more than 50 mV of drop along the 17-bus branch.
```

### 4.3 Files

| File | Role |
|------|------|
| `run_socp_opf_24h_yalmip_gurobi_es.m` | Single-shot ES OPF run (Module 8, Section 2 parameters) |
| `run_es_scenario_framework.m` | Multi-scenario batch runner (Scenarios A–F) |
| `solve_es_socp_opf_case.m` | Core solver function called by the framework |

---

## 5. Results and Interpretation

### 5.1 Module 7 Baseline: Reactive Power Compensation

Module 7 (`optimization.m`) adds **reactive power generators** (`Qg`) at every bus and optimises their dispatch jointly with feeder losses. Results (from `out_socp_opf_gurobi/`):

| Metric | Value |
|--------|-------|
| Status | **Feasible** ✓ |
| Vmin across all 24h | **0.9500 pu** (exactly at the 0.95 limit) |
| Worst hour | Hour 20 (bus 18) |
| Total 24h loss | ~0.229 pu |
| Total weighted loss-cost | ~0.476 |

**How it achieves feasibility**: By injecting reactive power Q at buses near the weak end of the feeder, it reduces the `X·Qij` term in the voltage drop equation. This directly counteracts the voltage deficit at buses 18 and 33. The optimizer pushes Vmin exactly to 0.95 pu during peak hours (hours 8–21), showing the constraint is active and the reactive support is being used maximally.

The shift of the worst bus from 18 (in Module 7) to 16 (in Module 7 hours 17–22) is because Qg is efficiently dispatched to push bus 18 up to exactly 0.95, and the binding constraint migrates one bus upstream.

---

### 5.2 Scenario A — Strict Benchmark

**Parameters**: ES at buses {18, 33}, ρ=0.40, u_min=0.20, hard Vmin=0.95

**Result: INFEASIBLE** (Gurobi code 12: infeasible or unbounded)

**Interpretation**: The feasibility region defined by the 0.95 pu voltage constraint is **empty** under these parameters. No assignment of `u(18,t)` and `u(33,t)` within [0.20, 1.0] can simultaneously satisfy:
1. Power balance (DistFlow equations) at all buses
2. Voltage ≥ 0.95 pu at buses 6–18 and 26–33

The minimum achievable voltage at bus 18 (from Scenario C results) is ~0.898 pu, which is 52 mV below the 0.95 pu limit. This is a fundamental physics constraint — the 17-bus main branch accumulates too much resistive voltage drop.

---

### 5.3 Scenario B — Feasible Hard-Constrained

**Parameters**: ES at buses {18, 33}, ρ=0.60, u_min=0.00, hard Vmin=0.95

**Result: INFEASIBLE** (Gurobi code 12)

**Interpretation**: Even allowing full curtailment of 60% of load at the terminal buses, the problem remains infeasible. This is a stronger result than expected and reveals a fundamental limitation:

- At maximum curtailment (u=0), bus 18 carries only 40% of its base demand
- But bus 18 sits at the END of a 17-bus branch — the voltage drop accumulates from ALL upstream buses (1→2→3→…→18)
- Reducing load at bus 18 only reduces the incremental branch-18 drop, not the cumulative drop from branches 1–17
- The intermediate buses (3–17) still carry their full demand, generating resistive voltage drops that compound along the feeder

This reveals that **endpoint ES curtailment has limited authority over cumulative upstream voltage drops**.

---

### 5.4 Scenario C — Soft-Constrained Diagnostic

**Parameters**: Same as Scenario A (ρ=0.40, u_min=0.20), but with **soft voltage lower bound** (slack variable with penalty λ_sv=1000)

The soft constraint replaces `V² ≥ Vmin²` with:
```
V² + sv ≥ Vmin²,   sv ≥ 0,   penalty: λ_sv · Σ sv(j,t)  added to objective
```

With λ_sv=1000, the optimizer is strongly incentivised to minimise voltage violations, but can violate Vmin if physically necessary.

**Result: FEASIBLE (Diagnostic)** ✓

| Metric | Value |
|--------|-------|
| Vmin (worst) | **0.8983 pu** at bus 18, hour 20 |
| Worst hour | Hour 20 (evening peak, price=1.8) |
| Total 24h loss | 0.3429 pu |
| Weighted objective | 11,315 |
| Mean NCL curtailment | **63.45%** |
| Max voltage slack V² | **0.0956 pu²** |

**Curtailment profile** (from `curtailment_ratio.csv`):

| Bus | Hours 1–6 | Hours 7–24 |
|-----|-----------|------------|
| 18 | Varies (0–80%) | ~80% (at floor u_min=0.20) |
| 33 | ~0% | ~80% (at floor u_min=0.20) |

This is the most important result: **the optimizer drives curtailment to its maximum bound (c=0.80, u=0.20) during virtually all peak and shoulder hours**. Despite maximum allowed curtailment, the voltage limit is not met.

**Voltage slack analysis** (from `voltage_slack_summary.csv`):

| Bus | Max V² slack | Hours in violation |
|-----|-------------|-------------------|
| 18 | 0.0956 pu² | 21/24 hours |
| 17 | 0.0947 pu² | 20/24 hours |
| 16 | 0.0911 pu² | 18/24 hours |
| 15 | 0.0885 pu² | 18/24 hours |
| 33 | 0.0913 pu² | 18/24 hours |
| 32 | 0.0909 pu² | 18/24 hours |
| 13–14 | ~0.083–0.086 pu² | 18/24 hours |
| 6 | 0.0191 pu² | 4/24 hours |

**Reading the slack values**: `sv = Vmin² - V²` when V < Vmin. The voltage magnitude violation is:
```
ΔV = Vmin - V = 0.95 - sqrt(Vmin² - sv) ≈ sv / (2·Vmin)

Worst case: sv=0.0956 → ΔV ≈ 0.0956/(2×0.95) ≈ 0.050 pu = 50 mV
```

This means bus 18 at hour 20 is 50 mV below the 0.95 pu floor — a significant voltage violation. The violations propagate backwards from bus 18 to bus 6, covering most of the main branch.

**Engineering interpretation**: The voltage problem is **systemic along the entire main branch**, not just localised at the endpoint. ES curtailment at bus 18 (the terminal bus) can only reduce the voltage drop on the final branch segment (17→18). The 16 upstream segments (1→2, 2→3, …, 16→17) still carry their full intermediate loads and generate cumulative drops that ES at bus 18 cannot address.

---

### 5.5 Scenario D — Expanded ES Bus Set

**Parameters**: ES at buses {17, 18, 32, 33}, ρ=0.40, u_min=0.20, hard Vmin=0.95

**Result: INFEASIBLE** (Gurobi code 12)

**Interpretation**: Adding buses 17 and 32 (one hop upstream of the weakest buses) with the same control authority (ρ=0.40, u_min=0.20) does not resolve infeasibility.

Even with 4 ES buses instead of 2, the load floor is:
```
Min effective demand at each ES bus = 0.68 · Pd
```

The cumulative resistive drop along buses 2–16 (which have NO ES control) still forces bus 17 voltage below 0.95 pu — and since bus 17's voltage is the parent for bus 18, bus 18 cannot recover either. This isolates the effect: **placement breadth without increased curtailment headroom does not help**.

---

### 5.6 Scenario E — Full Controllability (Upper Bound)

**Parameters**: ES at buses {18, 33}, ρ=0.80, u_min=0.00, hard Vmin=0.95

**Result: INFEASIBLE** (Gurobi code 12)

This is the **theoretical maximum controllability** for placement at {18, 33}: 80% of demand is NCL and full curtailment is allowed (u can go to zero). The minimum effective demand at bus 18 is just the 20% critical load.

Yet the problem is still infeasible. This is the strongest evidence that **the fundamental bottleneck is the cumulative voltage drop on branches 2→3→…→17**, which is set by the loads at buses 2–17 (all non-ES buses carrying full demand). Even zeroing out load at bus 18 entirely, the voltage arrives at bus 17 already below 0.95 pu during peak hours.

The Scenario C voltage slack analysis confirms this: buses 6 through 17 are in violation even before reaching bus 18.

---

### 5.7 Scenario F — Lambda Sensitivity

**Parameters**: Same as Scenario B (ρ=0.60, u_min=0.00), but λ_u=0 (no curtailment cost)

**Result: INFEASIBLE** (Gurobi code 12)

Removing the curtailment penalty (pure loss minimisation drives ES control) does not affect feasibility — the problem was infeasible in Scenario B due to voltage physics, not objective structure. This confirms the infeasibility is structural, not a consequence of the penalty discouraging curtailment.

---

## 6. Key Research Finding

> **NCL demand curtailment via Electric Springs at terminal buses alone cannot restore voltage to ≥ 0.95 pu on the IEEE 33-bus feeder under full loading conditions.**

### Why This Happens: Physics of Voltage Drop

The DistFlow voltage drop equation:
```
V²(j) = V²(i) - 2[R·Pij + X·Qij] + (R²+X²)·ℓij
```

contains **two independent controllable terms**:
- `R·Pij` — reduced by curtailing active load P (what ES does)
- `X·Qij` — reduced by injecting reactive power Q (what Module 7 does)

The IEEE 33-bus feeder has a **17-bus main branch**. The total voltage drop from bus 1 to bus 18 is the SUM of 17 individual branch drops. ES at bus 18 can only reduce the drop on the LAST segment (branch 17→18). The 16 upstream segments accumulate their own drops from buses 2–17, which have no ES control.

The Scenario C diagnostic reveals that voltage violations begin as early as **bus 6** (4 hours in violation), confirming the problem is distributed across the entire feeder, not localised at the endpoint.

### Contrast with Module 7

Module 7 achieves Vmin=0.95 pu by **reactive power injection** (Qg). This works because:
1. Qg at a bus reduces `X·Qij` on the incoming branch and all downstream branches
2. A strategically placed reactive source near bus 18 can offset the entire cumulative X·Q drop
3. Reactive power flows in both directions along a feeder, providing widespread voltage support

The key insight for research: **reactive power compensation acts "globally" along a branch** because it reduces the reactive flow (and hence the X·Q drop) at every segment upstream of the injection point. **ES demand reduction acts "locally"** — it only directly reduces the P-flow and hence R·P drop on the specific segment(s) between the ES bus and its parent.

### Implications for Future Modules

To achieve voltage regulation using ES:
1. **ES + Qg combined** (Module 9): Add reactive power support back alongside ES control. Expected to be feasible.
2. **Distributed ES placement**: Place ES at every bus along the branch (computationally expensive but physically sound).
3. **Hybrid architecture**: Use ES for demand response and peak shaving; use Qg/capacitors for voltage regulation.
4. **Relaxed voltage limits**: Accept Vmin < 0.95 pu in a soft-constrained formulation (Scenario C approach).

---

## 7. Output Files Reference

### `out_socp_opf_gurobi/` (Module 7 Baseline)

| File | Contents |
|------|----------|
| `opf_summary_24h_cost.csv` | Hour, price, Vmin, VminBus, Loss, LossCost |
| `V_bus_by_hour.csv` | 33×24 voltage magnitude matrix (pu) |
| `Qg_bus_by_hour.csv` | 33×24 reactive generation matrix (pu) |
| `opf_min_voltage_vs_hour.png` | Vmin(t) time series |
| `opf_loss_vs_hour.png` | Loss(t) time series |
| `opf_voltage_profile_worst_h19.png` | Voltage profile at worst hour |

### `out_socp_opf_gurobi_es/scenario_*/` (Module 8, each scenario)

| File | Contents |
|------|----------|
| `scenario_info.txt` | Parameters + result summary (human readable) |
| `summary_24h.csv` | Hour, price, Vmin, VminBus, Loss, LossCost |
| `V_bus_by_hour.csv` | 33×24 voltage matrix |
| `u_bus_by_hour.csv` | 33×24 NCL scaling factor matrix |
| `Pd_eff_by_hour.csv` | 33×24 effective active demand after ES control |
| `Qd_eff_by_hour.csv` | 33×24 effective reactive demand after ES control |
| `curtailment_ratio.csv` | ES-bus × 24h curtailment ratio (1 - u) |
| `voltage_slack_V2.csv` | 33×24 voltage slack matrix (Scenario C only) |
| `voltage_slack_summary.csv` | Per-bus max slack and hours in violation (Scenario C only) |
| `Vmin_vs_hour.png` | Vmin time series with Vmin limit line |
| `loss_vs_hour.png` | Feeder loss time series |
| `voltage_profile_h*.png` | Voltage profile at worst hour |
| `u_vs_hour.png` | ES scaling factor over 24h |
| `curtailment_vs_hour.png` | NCL curtailment % over 24h |
| `voltage_slack_heatmap.png` | Bus × hour heatmap of V² slack (Scenario C only) |

### `out_socp_opf_gurobi_es/comparison/` (Cross-scenario)

| File | Contents |
|------|----------|
| `scenario_comparison.csv` | One row per scenario: status, Vmin, loss, obj, curtailment |
| `compare_Vmin_vs_hour.png` | Vmin(t) overlay for all feasible scenarios |
| `compare_loss_vs_hour.png` | Loss(t) overlay for all feasible scenarios |
| `compare_u_bus18.png` | ES control at bus 18 across scenarios |
| `compare_u_bus33.png` | ES control at bus 33 across scenarios |
| `compare_voltage_profile_h*.png` | Voltage profiles at reference hour |
| `compare_total_loss_bar.png` | Bar chart: total 24h loss by scenario |
| `compare_curtailment_bar.png` | Bar chart: mean curtailment by scenario |

### Summary Comparison Table (from `scenario_comparison.csv`)

| Scenario | Status | MinVmin (pu) | Total Loss (pu) | Mean Curt (%) | Max V-Slack |
|----------|--------|-------------|-----------------|---------------|-------------|
| A — Strict Benchmark | **INFEASIBLE** | — | — | — | — |
| B — Feasible Hard | **INFEASIBLE** | — | — | — | — |
| C — Soft Diagnostic | Diagnostic | 0.8983 | 0.3429 | 63.45% | 0.0956 pu² |
| D — Expanded Set | **INFEASIBLE** | — | — | — | — |
| E — Full Controllability | **INFEASIBLE** | — | — | — | — |
| F — Lambda=0 Sensitivity | **INFEASIBLE** | — | — | — | — |
| Module 7 Baseline | **FEASIBLE** | **0.9500** | **0.229** | N/A (Qg) | 0 |

---

## 8. How to Run

### Requirements

- MATLAB R2018b or later
- [YALMIP](https://yalmip.github.io/) — convex optimisation modelling toolbox
- [Gurobi](https://www.gurobi.com/) — SOCP/LP solver (academic license available free)
- Data folder `./mp_export_case33bw/` with `branch.csv` and `loads_base.csv`

### Step-by-step

**Step 1**: Generate load profiles and verify topology
```matlab
% Build 24h load matrix
loads = build_24h_load_profile_from_csv('./mp_export_case33bw/loads_base.csv', 'system', true, false);

% Build and verify topology
topo = build_distflow_topology_from_branch_csv('./mp_export_case33bw/branch.csv', 1);
run topology_construction_verification
```

**Step 2**: Run Module 7 baseline (reactive power OPF)
```matlab
run optimization
% Outputs → ./out_socp_opf_gurobi/
```

**Step 3**: Run Module 8 single scenario (quick test)
```matlab
run run_socp_opf_24h_yalmip_gurobi_es
% Outputs → ./out_socp_opf_gurobi_es/  (single scenario)
```

**Step 4**: Run Module 8 multi-scenario framework
```matlab
run run_es_scenario_framework
% Outputs → ./out_socp_opf_gurobi_es/  (all 6 scenarios + comparison)
```

### Configuring ES Parameters (Module 8 single run)

Edit Section 2 of `run_socp_opf_24h_yalmip_gurobi_es.m`:
```matlab
es_buses  = [18, 33];   % ES-enabled bus indices (not root bus)
rho_val   = 0.40;       % NCL fraction [0, 1]
u_min_val = 0.20;       % Minimum NCL scaling [0, 1]
lambda_u  = 5.0;        % Curtailment penalty weight (0 = free curtailment)
```

### Extending the Framework (adding new scenarios)

Add a new struct in `run_es_scenario_framework.m` Section 3:
```matlab
scG            = base;
scG.name       = 'scenario_G_new';
scG.label      = 'Scenario G — Description';
scG.es_buses   = [10, 18, 25, 33];   % upstream + downstream
scG.rho_val    = 0.50;
scG.u_min_val  = 0.10;
scG.lambda_u   = 5.0;
scG.out_dir    = fullfile(topDir, scG.name);

scenarios = {scA, scB, scC, scD, scE, scF, scG};  % append to list
```

---

## References

- Baran, M.E. & Wu, F.F. (1989). Optimal capacitor placement on radial distribution systems. *IEEE Trans. Power Delivery*, 4(1), 725–734.
- Farivar, M. & Low, S.H. (2013). Branch flow model: Relaxations and convexification. *IEEE Trans. Power Systems*, 28(3), 2554–2564.
- Hui, S.Y.R., Lee, C.K., & Wu, F.F. (2012). Electric springs — A new smart grid technology. *IEEE Trans. Smart Grid*, 3(3), 1552–1561.
- Lam, A.Y.S., Zhang, B., & Tse, D.N. (2012). Distributed algorithms for optimal power flow problem. *51st IEEE CDC*, 430–437.
