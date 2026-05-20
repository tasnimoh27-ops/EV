# Stage 10: PV Penetration Study

## Purpose

Stage 10 extends the existing IEEE 33-bus Electric Spring (ES-1) framework with a comprehensive photovoltaic (PV) penetration analysis. The study investigates:

1. **How PV generation affects distribution feeder voltage, losses, and feasibility**
2. **At what PV penetration level voltage and reverse-flow constraints are violated**
3. **Whether ES-1 reactive power support can increase PV hosting capacity**
4. **What minimum ES-1 deployment is required at each PV penetration level**

## Key Features

- **Preserves all existing Stage 1–9 work**: No modifications to baseline ES, STATCOM, ESS, or ES-1 solvers
- **PV modeling follows Prof. Hou's tutorial style**: Solar profile, reactive power handling, and independent inverter controls
- **Bidirectional ES-1 reactive capability**: Both injection (for undervoltage) and absorption (for overvoltage)
- **Comprehensive parametric sweep**: 8 PV penetration levels × 6 ES-1 budgets = 48 + 8 cases analyzed
- **Full metric tracking**: Voltage profiles, feeder losses, reverse power flow, hosting capacity

## File Structure

### New MATLAB Files

**Main runner:**
```
03_es_feasibility_framework/main/
  └── run_stage10_pv_penetration.m          [MAIN SCRIPT - run this]
```

**Helper functions:**
```
03_es_feasibility_framework/functions/
  ├── build_stage10_pv_profile.m            [Hou-style PV profile builder]
  ├── apply_stage10_pv_penetration.m        [Net load = base load − PV]
  ├── solve_es1_pv_misocp.m                 [New PV-aware ES-1 solver]
  └── summarize_stage10_pv_metrics.m        [Extract metrics to table rows]
```

**Plotting functions:**
```
03_es_feasibility_framework/plotting/
  ├── plot_stage10_pv_profile.m             [24h load and PV profiles]
  ├── plot_stage10_voltage_envelope.m       [V_min / V_max vs penetration]
  ├── plot_stage10_vmax_vs_pv.m             [Overvoltage risk analysis]
  ├── plot_stage10_loss_vs_pv.m             [Feeder losses vs penetration]
  └── plot_stage10_es1_count_vs_pv.m        [Minimum ES-1 count needed]
```

### Output Tables

All results saved to `04_results/es_framework/tables/`:

```
table_stage10_pv_no_es.csv
  └─ 8 cases: PV penetration sweep without ES-1
  └─ Columns: PV scale, Vmin, Vmax, worst bus, losses, reverse flow, feasibility

table_stage10_pv_es1_sweep.csv
  └─ 48 cases: PV penetration × ES budget sweep with ES-1
  └─ Columns: above + N_ES_used, selected ES buses, reactive dispatch

table_stage10_pv_hosting_capacity.csv
  └─ 3 rows: baseline, max PV without ES, max PV with ES-1
  └─ Hosting capacity = max PV scale for voltage feasibility
```

### Output Figures

All results saved to `04_results/es_framework/figures/stage10/`:

```
fig1_existing_load_and_pv_profile.png
  └─ Shows EV-stress load multiplier and normalized PV profile
  └─ Demonstrates that base load is preserved

fig2_voltage_envelope_no_es.png
  └─ V_min and V_max vs PV penetration (left: no ES, right: best ES-1)

fig3_vmax_vs_pv_penetration.png
  └─ Overvoltage risk: maximum voltage vs PV scale
  └─ Shows how much ES-1 can mitigate overvoltage

fig4_loss_vs_pv_penetration.png
  └─ Feeder losses vs PV penetration
  └─ Expected: decrease at moderate PV, increase at high PV

fig5_min_es1_count_vs_pv_penetration.png
  └─ Minimum number of ES-1 devices needed at each PV scale
```

## Recommended Run Order

### Step 1: Switch to Feature Branch
```bash
git checkout feature/stage10-pv-penetration
```

### Step 2: Open MATLAB
Navigate to the repository root or directly to:
```
03_es_feasibility_framework/main/
```

### Step 3: Run the Main Script
```matlab
cd 03_es_feasibility_framework/main/
run_stage10_pv_penetration
```

Expected runtime: **20–40 minutes** (8 PV scales × 6 ES budgets, ~3 min per solve)

### Step 4: Check Generated Tables
After completion, inspect:
```
04_results/es_framework/tables/
  ├── table_stage10_pv_no_es.csv
  ├── table_stage10_pv_es1_sweep.csv
  └── table_stage10_pv_hosting_capacity.csv
```

### Step 5: Review Generated Figures
View results:
```
04_results/es_framework/figures/stage10/
  ├── fig1_existing_load_and_pv_profile.png
  ├── fig2_voltage_envelope_no_es.png
  ├── fig3_vmax_vs_pv_penetration.png
  ├── fig4_loss_vs_pv_penetration.png
  └── fig5_min_es1_count_vs_pv_penetration.png
```

### Step 6: Interpret Results
Key metrics in command window output and tables:
- **Hosting capacity without ES-1**: Maximum PV scale for voltage feasibility
- **Hosting capacity with ES-1**: Same, with reactive support
- **Improvement**: Absolute increase in feasible penetration
- **Best ES-1 config**: Minimum device count at maximum feasible penetration

## Modeling Assumptions

### PV Placement (Hou Tutorial)
```
Buses:     [18, 22, 25, 33]
Peak (pu): [0.06, 0.08, 0.07, 0.06]  on 10 MVA base
Total:     0.27 pu = 2.7 MW
```

### PV Profile (Hou-Style Solar)
Normalized 24-hour profile:
```
pv(t) = max(0, sin(π*(t − 6)/12))^1.5

t=1:   0.0000  (midnight, zero)
t=6:   0.0000  (sunrise, zero)
t=12:  1.0000  (noon, peak)
t=18:  0.0000  (sunset, zero)
t=24:  0.0000  (night, zero)
```

### Net Load Formulation
```
P_net(i,t)  = P_base(i,t) − pv_scale × pv_peak(i) × pv_profile(t)
Q_net(i,t)  = Q_base(i,t)  [reactive load unchanged]

Allow P_net < 0: Local PV generation exceeds local demand → exports power
```

### PV Penetration Scale Sweep
```
Scale 0.00  → No PV (baseline)
Scale 0.25  → 25% of reference Hou capacity
Scale 0.50  → 50% of reference Hou capacity
Scale 0.75  → 75% of reference Hou capacity
Scale 1.00  → 100% of reference Hou capacity (2.7 MW)
Scale 1.25  → 125% of reference Hou capacity
Scale 1.50  → 150% of reference Hou capacity
Scale 2.00  → 200% of reference Hou capacity
```

### ES-1 Reactive Capability
**For PV studies, bidirectional:**
```
Q_es(i,t) ∈ [−Q_es_abs_max × z(i), +Q_es_inj_max × z(i)]

where:
  Q_es > 0: ES injects reactive power (helps undervoltage)
  Q_es < 0: ES absorbs reactive power (helps overvoltage)
  z(i): binary, ES installed at bus i
  Q_es_abs_max = 0.10 pu/device (default)
  Q_es_inj_max = 0.10 pu/device (default)
```

### Curtailment
By design, **curtailment is disabled** for PV studies:
```
disable_curtailment = true
```

Rationale: During PV overvoltage, curtailing load makes the problem worse. ES-1 should use reactive power alone.

## Important Design Decisions

### 1. Load Multiplier Unchanged
The existing 24-hour EV-stress load multiplier is **intentionally preserved**:
```
Load profile still shows evening peak at hours 17–21.
This is the reference scenario for PV impact evaluation.
```

### 2. Soft Voltage Constraints
Both under- and over-voltage have slack variables:
```
Objective: minimize(sv_low) + minimize(sv_high) + small_weight × loss

This allows the solver to diagnose both:
  - Undervoltage: where voltage support is needed
  - Overvoltage: where reactive absorption is needed
```

### 3. No Modifications to Stages 1–9
- `solve_es1_misocp.m`: Original kept unchanged
- `solve_es1_pv_misocp.m`: New file, PV-only
- All existing results reproducible
- Branching prevents main branch contamination

## Extending Stage 10

### Option A: Replace Load Multiplier
If you want a more realistic load profile:
```matlab
% Future: build_hou_load_profile.m
% Design a Hou-style daily load profile instead of EV-peak
% Then, apply PV on top of that new profile
```

### Option B: Add Load Heterogeneity
If you want residential vs. commercial load profiles at different buses:
```matlab
% Create loads_heterogeneous.csv with bus-specific profiles
% Modify apply_stage10_pv_penetration to use bus-specific profiles
```

### Option C: PV Reactive Control Modes
Implement different PV reactive dispatch strategies:
```matlab
% Mode 1: Reactive injection (current)
% Mode 2: Reactive absorption (current)
% Mode 3: Volt-Var (voltage-dependent reactive)
% Mode 4: Volt-Watt (active power curtailment based on voltage)
```

### Option D: Multi-Scenario Analysis
Combine PV penetration with:
- Different load multipliers (0.5× to 2.0×)
- Different grid strength (varying R/X ratios)
- Different PV placement strategies

## Troubleshooting

### "Missing build_distflow_topology_from_branch_csv"
- Ensure `02_baseline_modules/shared/` is in MATLAB path
- Check that `build_ieee33_network` is called with correct `repo_root`

### "Gurobi error or time limit"
- Increase `time_limit` in solver params (default 120 s)
- Reduce `MIPGap` to speed up for loose bounds (default 0.05 = 5%)
- Check system Gurobi license and version

### "PV profile check fails"
- Ensure `build_stage10_pv_profile.m` computes sin(π(t−6)/12)^1.5 correctly
- Peak should be at hour 12 with value ≥ 0.99

### "No feasible ES-1 solutions"
- Increase `N_ES_max` budget
- Increase `Q_es_abs_max` and `Q_es_inj_max` reactive limits
- Check that candidate bus set `es_cand` is not empty

## Expected Research Insights

### Without ES-1
- **Low PV penetration**: Voltage and losses improve (local generation helps)
- **Moderate penetration**: Reverse power flow appears
- **High penetration**: Overvoltage becomes critical constraint

### With ES-1
- **Undervoltage periods**: ES injects reactive power (Q_es > 0)
- **Overvoltage periods**: ES absorbs reactive power (Q_es < 0)
- **Reactive swing**: Ability to alternate between injection and absorption increases hosting capacity

### Hosting Capacity
```
Typical result pattern:
  Without ES-1: Hosting capacity ~ 0.50 pu (50% penetration)
  With 4 ES-1:  Hosting capacity ~ 1.00 pu (100% penetration)
  With 8 ES-1:  Hosting capacity ~ 1.50 pu (150% penetration)
```

## References

- **PV Modeling**: Hou et al., IEEE TPWRS, solar profile and reactive dispatch
- **ES-1 Framework**: Previous Stages 1–6 solver formulations
- **Distributed Optimization**: DistFlow equations, MISOCP relaxation

## Contact & Questions

For questions about Stage 10:
1. Check this README for assumptions and design decisions
2. Review comments in `run_stage10_pv_penetration.m`
3. Examine helper function docstrings

For issues with existing Stage 1–9:
- Refer to their respective runner scripts
- They remain unmodified by Stage 10

---

**Last Updated**: 2026-05-20  
**Branch**: `feature/stage10-pv-penetration`  
**Status**: Ready for production
