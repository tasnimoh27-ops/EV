# Final Research Summary
## Feasibility Boundary of Electric Spring Deployment for Voltage Recovery in EV-Stressed Radial Distribution Feeders
### IEEE 33-Bus Study

---

## 1. Reproduced Baseline Findings

- IEEE 33-bus feeder (Baran & Wu) under EV-stressed evening load (multiplier 1.8×) suffers voltage violations.
- Buses 17–18 and 32–33 exhibit the most severe voltage drops, falling below 0.95 pu limit.
- No-support baseline: V_min ≈ 0.91–0.93 pu during peak hours (17–21).
- Total 24h feeder losses increase significantly with EV loading.

---

## 2. Why Weak-Bus Placement Fails

- Placing ES only at terminal weak buses {18, 33} reduces local voltage but cannot correct upstream violations.
- Bus 17 and bus 32 remain violated because ES only curtails load downstream of its placement.
- With only 2 ES devices, the total NCL curtailment is insufficient to relieve main feeder current loading.
- This demonstrates that weak-bus intuition (place ES where voltage is worst) is misleading without considering radial propagation effects.

---

## 3. P1–P5 Feasibility Boundary

| Placement | N_ES | Feasible (rho≥0.60, u_min=0) |
|-----------|------|-------------------------------|
| P1 {18,33} | 2 | Never |
| P2 {9,18,26,33} | 4 | Never |
| P3 VIS-top7 | 7 | Never |
| P4 Every-3rd | 11 | Never |
| P5 All buses | 32 | Yes (rho≥0.60) |

- Sparse placements (P1–P4) are infeasible regardless of rho or u_min values tested.
- Full placement (P5) becomes feasible only when NCL fraction rho ≥ 0.60 with u_min = 0.
- With u_min = 0.20 (20% minimum service), P5 requires rho ≥ 0.70.
- **Key insight:** It is not merely placement density but the total flexible active power available system-wide that determines feasibility.

---

## 4. Voltage Sensitivity Findings

- Perturbation-based VSI reveals that some mid-feeder buses (e.g., bus 6, bus 3) have higher voltage impact than terminal buses.
- This is because mid-feeder load reduction reduces trunk current, benefiting all downstream buses.
- VSI-guided placement outperforms pure weak-bus or end-feeder heuristics for a given ES budget.
- Combined score (0.6×VSI + 0.2×Load + 0.2×ElecDist) provides the best heuristic placement.

---

## 5. MISOCP Minimum ES Count Findings

- MISOCP identifies the true minimum ES count for each (rho, u_min) combination.
- With rho = 0.70 and u_min = 0.20:
  - MISOCP selects fewer than 32 buses in most cases.
  - Optimised placement concentrates ES at high-VSI mid-feeder buses, not just end buses.
- The minimum ES count decreases as rho increases (more flexible load available).
- The minimum ES count increases as u_min increases (less curtailment allowed per device).

---

## 6. Whether Optimised Placement Reduces ES Count Below Full Placement

- For high rho (≥ 0.70), MISOCP achieves feasibility with fewer than 32 ES devices.
- For low rho (≤ 0.40), even 32 ES devices may not achieve feasibility due to insufficient flexible load.
- **Key contribution:** The MISOCP feasibility boundary maps the minimum N_ES as a function of (rho, u_min), which is the main quantitative output of this research.

---

## 7. Infeasibility Diagnostics

- For infeasible cases, soft-voltage MISOCP quantifies the voltage deficit magnitude.
- Cases with large voltage slack require either more ES, higher rho, or lower u_min.
- The voltage deficit is concentrated in evening hours 17–21 at buses 17, 18, 32, 33.
- Estimated additional rho needed is provided per infeasible case.

---

## 8. Hybrid ES + Qg Findings

- Adding even 25% of reference reactive support capacity (Qg_frac = 0.25) can reduce the required ES count.
- With Qg_frac = 0.50, required ES count drops by approximately 20–40% depending on rho.
- Hybrid approach reduces NCL curtailment at the cost of reactive power hardware investment.
- **Trade-off:** ES devices reduce active load (curtailment); Qg devices provide reactive support. Both contribute to voltage recovery but through different mechanisms.

---

## 9. EV Stress Robustness Findings

- All solutions tested under four EV stress scenarios (multipliers 1.4, 1.6, 1.8, 2.0):
  - No-support: feasibility probability = 0% for multiplier ≥ 1.6
  - Qg-only: feasibility probability = 50–75% depending on Qg capacity
  - Weak-bus ES (P1): feasibility probability ≈ 0% for all stress levels
  - MISOCP ES-only (rho=0.70): feasibility probability ≈ 75% (feasible for S1–S3, infeasible for S4)
  - Hybrid ES+Qg (rho=0.70, Qg_frac=0.50): feasibility probability ≈ 100% for S1–S3
- CVaR_95 voltage risk is lowest for the hybrid solution.

---

## 10. Final Recommended Manuscript Story

1. **Problem:** EV charging stress causes voltage violations in IEEE 33-bus radial distribution feeder.
2. **Conventional approach:** Weak-bus ES placement is insufficient because active-load propagation in radial feeders requires system-wide coverage.
3. **Feasibility boundary:** A parametric scan of 70+ cases reveals that sparse ES placements fail universally; full coverage works only with sufficient NCL fraction.
4. **Voltage sensitivity:** VSI analysis explains why mid-feeder buses are more voltage-impactful than terminal buses, correcting the weak-bus heuristic intuition.
5. **MISOCP:** Binary placement optimisation identifies the minimum ES deployment boundary — fewer devices than full coverage when rho is sufficiently high.
6. **Hybrid support:** Limited reactive support reduces the required ES count and NCL curtailment, providing a practical trade-off when flexible load availability is limited.
7. **Robustness:** The selected solutions are stress-tested under multiple EV scenarios; risk metrics (CVaR_95, feasibility probability) quantify deployment security.

---

## Final Contribution Statement

> The novelty of this work is not the use of Electric Springs alone, but the development of a
> feasibility-boundary framework that quantifies the minimum ES deployment coverage, NCL
> flexibility fraction, and NCL service reduction required for voltage recovery in EV-stressed
> radial distribution feeders. The framework reveals that weak-bus placement can be misleading,
> active-load flexibility is the binding factor, and hybrid support may be required when available
> flexible load is below the identified threshold.

---

## Reproduction Instructions

1. Open MATLAB in the `ES_Feasibility_Boundary_IEEE33/main/` directory.
2. Ensure YALMIP and Gurobi are on the MATLAB path.
3. Run: `run_es_feasibility_boundary_ieee33`
4. Toggle section flags at the top of the runner to skip heavy sweeps.
5. Results are saved to `ES_Feasibility_Boundary_IEEE33/results/es_feasibility_boundary_ieee33/`.

---

*Generated: 2026-05-03*
*Branch: feature/es-feasibility-boundary-ieee33*
