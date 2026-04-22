%% run_socp_opf_24h_yalmip_gurobi_es.m
% MODULE 8 — Electric Spring (ES) equivalent smart-load SOCP OPF
%
% Extends Module 7 (optimization.m) by replacing selected fixed-PQ buses
% with ES-enabled smart-load buses that split their demand into:
%   - Critical Load (CL)   : always fully served, never curtailed
%   - Non-Critical Load (NCL): scaled by a continuous control variable u(j,t)
%
% Decision variables added over Module 7:
%   u(j,t)  — NCL scaling factor (u_min <= u <= 1 at ES buses, fixed 1 elsewhere)
%
% Qg is removed: this first ES implementation does NOT combine reactive
% support with ES demand control.  Add Qg back in Module 9 once ES is validated.
%
% Requirements:  YALMIP + Gurobi
% Depends on:    build_distflow_topology_from_branch_csv.m
%                build_24h_load_profile_from_csv.m

clear; clc; close all;

% =========================================================================
%  SECTION 1 — FILE PATHS
% =========================================================================
caseDir   = './mp_export_case33bw';
loadsCsv  = fullfile(caseDir, 'loads_base.csv');
branchCsv = fullfile(caseDir, 'branch.csv');

assert(exist(loadsCsv,  'file') == 2, "Missing: %s", loadsCsv);
assert(exist(branchCsv, 'file') == 2, "Missing: %s", branchCsv);

% =========================================================================
%  SECTION 2 — ES PARAMETERS  (tune these for your experiments)
% =========================================================================

% Which buses are ES-enabled (1-indexed, must not include slack bus 1)
es_buses = [18, 33];

% Non-critical load fraction per bus.
% rho(j) = fraction of Pd/Qd that is non-critical (controllable).
% Scalar here → same ratio for all ES buses; extend to a vector if needed.
rho_val  = 0.40;          % 40 % of load is non-critical

% Lower bound on NCL scaling (how far the ES can reduce NCL).
% 0.0 = full curtailment allowed; 0.5 = at most 50 % reduction.
u_min_val = 0.20;         % NCL can be reduced to 20 % of its base value

% Penalty weight on load curtailment in the objective.
% Higher lambda_u → optimizer is more reluctant to shed NCL.
% Set to 0 to let the optimizer curtail freely (pure loss minimisation).
lambda_u  = 5.0;

% =========================================================================
%  SECTION 3 — VOLTAGE & SOLVER SETTINGS
% =========================================================================
Vslack = 1.0;
Vmin   = 0.95;
Vmax   = 1.05;

% Time-of-use price profile (same as Module 7 for fair comparison)
T = 24;
price = ones(T,1);
price(1:6)   = 0.6;
price(7:16)  = 1.0;
price(17:21) = 1.8;
price(22:24) = 0.9;

ops = sdpsettings('solver', 'gurobi', 'verbose', 1);

% =========================================================================
%  SECTION 4 — BUILD TOPOLOGY & LOAD PROFILES
% =========================================================================
topo = build_distflow_topology_from_branch_csv(branchCsv, 1);
nb   = topo.nb;
nl   = topo.nl_tree;
root = topo.root;

from = topo.from(:);
to   = topo.to(:);
R    = topo.R(:);
X    = topo.X(:);

loads = build_24h_load_profile_from_csv(loadsCsv, 'system', true, false);
assert(isfield(loads,'P24') && isfield(loads,'Q24'), "loads must contain P24/Q24.");

Pd = loads.P24;   % nb x T  (p.u.)
Qd = loads.Q24;   % nb x T  (p.u.)

% =========================================================================
%  SECTION 5 — LOAD DECOMPOSITION
%
%  For ES bus j:
%    Pncl0(j,t) = rho(j) * Pd(j,t)        <- base NCL
%    Pcl(j,t)   = (1-rho(j)) * Pd(j,t)    <- CL (never curtailed)
%
%  Effective demand:
%    Pd_fixed(j,t)  = Pcl(j,t)             <- replaces old Pd in constraints
%    Pncl0(j,t)                            <- multiplied by u(j,t) inside YALMIP
%
%  At non-ES buses:
%    Pd_fixed(j,t) = Pd(j,t)   (rho=0, so all load is "critical")
%    u is fixed to 1 via bounds, so Pd_eff = Pd_fixed + 1*Pncl0 = Pd
% =========================================================================

% Build rho vector (nb x 1); zero for non-ES buses
rho = zeros(nb, 1);
for b = es_buses
    if b < 1 || b > nb
        error("es_bus %d is out of range [1, %d]", b, nb);
    end
    if b == root
        error("Slack bus %d cannot be an ES bus", root);
    end
    rho(b) = rho_val;
end

% Fixed (critical) portion of load
Pd_fixed = (1 - rho) .* Pd;   % nb x T
Qd_fixed = (1 - rho) .* Qd;

% Base NCL (controllable portion baseline)
Pncl0 = rho .* Pd;             % nb x T
Qncl0 = rho .* Qd;

% u bounds (nb x 1)
u_lo = ones(nb, 1);            % default: non-ES bus → u forced to 1
u_hi = ones(nb, 1);
for b = es_buses
    u_lo(b) = u_min_val;       % ES bus: u_min <= u <= 1
end

% =========================================================================
%  SECTION 6 — YALMIP DECISION VARIABLES
% =========================================================================
v   = sdpvar(nb, T, 'full');   % squared voltage  V^2
Pij = sdpvar(nl, T, 'full');   % branch active flow
Qij = sdpvar(nl, T, 'full');   % branch reactive flow
ell = sdpvar(nl, T, 'full');   % squared current  I^2
u   = sdpvar(nb, T, 'full');   % NCL scaling factor

% Auxiliary for load-curtailment penalty: c(j,t) = 1 - u(j,t) >= 0
% Only meaningful at ES buses, but we define it for all for clean indexing.
c_aux = sdpvar(nb, T, 'full');

% =========================================================================
%  SECTION 7 — ADJACENCY MAPS (same as Module 7)
% =========================================================================
outLines       = cell(nb, 1);
line_of_child  = zeros(nb, 1);
for k = 1:nl
    outLines{from(k)}(end+1) = k;
    line_of_child(to(k))     = k;
end

% =========================================================================
%  SECTION 8 — BUILD CONSTRAINTS
% =========================================================================
Constraints = [];

% --- Voltage and current bounds ---
Constraints = [Constraints, v >= Vmin^2, v <= Vmax^2];
Constraints = [Constraints, ell >= 0];
Constraints = [Constraints, v(root, :) == Vslack^2];

% --- u bounds ---
for t = 1:T
    Constraints = [Constraints, u(:, t) >= u_lo, u(:, t) <= u_hi];
end

% --- Curtailment auxiliary: c(j,t) = 1 - u(j,t) ---
Constraints = [Constraints, c_aux == 1 - u];
Constraints = [Constraints, c_aux >= 0];

% --- DistFlow power balance (upgraded with ES effective demand) ---
%
% Effective demand at bus j, hour t:
%   Pd_eff(j,t) = Pd_fixed(j,t) + u(j,t) * Pncl0(j,t)   [bilinear!]
%
% Since u and Pncl0 multiply each other this would be bilinear. To keep
% the problem SOCP (convex), we reformulate using the fact that
% Pncl0(j,t) is a KNOWN DATA constant (not a variable), so
%   u(j,t) * Pncl0(j,t)
% is linear in u(j,t).  This is SOCP-compatible. ✓
%
for t = 1:T
    for j = 1:nb
        if j == root, continue; end

        kpar = line_of_child(j);
        i    = from(kpar);

        % Effective demand (linear in u because Pncl0/Qncl0 are data)
        Pd_eff_jt = Pd_fixed(j,t) + u(j,t) * Pncl0(j,t);
        Qd_eff_jt = Qd_fixed(j,t) + u(j,t) * Qncl0(j,t);

        % Children downstream flows
        childLines = outLines{j};
        if isempty(childLines)
            sumPchild = 0;
            sumQchild = 0;
        else
            sumPchild = sum(Pij(childLines, t));
            sumQchild = sum(Qij(childLines, t));
        end

        % Active power balance
        Constraints = [Constraints, ...
            Pij(kpar,t) == Pd_eff_jt + sumPchild + R(kpar)*ell(kpar,t)];

        % Reactive power balance (no Qg in this module)
        Constraints = [Constraints, ...
            Qij(kpar,t) == Qd_eff_jt + sumQchild + X(kpar)*ell(kpar,t)];

        % Voltage drop
        Constraints = [Constraints, ...
            v(j,t) == v(i,t) ...
                   - 2*(R(kpar)*Pij(kpar,t) + X(kpar)*Qij(kpar,t)) ...
                   + (R(kpar)^2 + X(kpar)^2)*ell(kpar,t)];

        % SOCP relaxation: Pij^2 + Qij^2 <= ell * v_parent
        % Written in YALMIP Lorentz cone form (same as Module 7)
        Constraints = [Constraints, ...
            cone([2*Pij(kpar,t); 2*Qij(kpar,t); ell(kpar,t) - v(i,t)], ...
                  ell(kpar,t) + v(i,t))];
    end
end

% =========================================================================
%  SECTION 9 — OBJECTIVE FUNCTION
%
%  min  sum_t  price(t) * sum_lines R_k * ell_k(t)    [weighted losses]
%     + lambda_u * sum_{j in ES_buses, t} c_aux(j,t)  [NCL curtailment]
%
%  The curtailment term discourages excessive load shedding while still
%  allowing it when voltage stress is severe.
% =========================================================================
lossCost = 0;
for t = 1:T
    lossCost = lossCost + price(t) * sum(R .* ell(:,t));
end

% Curtailment penalty only over ES buses
curtCost = 0;
for b = es_buses
    curtCost = curtCost + lambda_u * sum(c_aux(b, :));
end

Objective = lossCost + curtCost;

% =========================================================================
%  SECTION 10 — SOLVE
% =========================================================================
fprintf('\n=== Module 8: ES SOCP-OPF (GUROBI) ===\n');
sol = optimize(Constraints, Objective, ops);

if sol.problem ~= 0
    disp(sol.info);
    error("ES OPF failed. YALMIP error code: %d", sol.problem);
end

% =========================================================================
%  SECTION 11 — EXTRACT RESULTS
% =========================================================================
v_val   = value(v);
V_val   = sqrt(max(v_val, 0));
ell_val = value(ell);
u_val   = value(u);

% Per-hour loss and voltage
loss_t     = zeros(T,1);
costloss_t = zeros(T,1);
Vmin_t     = zeros(T,1);
VminBus_t  = zeros(T,1);

for t = 1:T
    loss_t(t)     = sum(R .* ell_val(:,t));
    costloss_t(t) = price(t) * loss_t(t);
    [Vmin_t(t), VminBus_t(t)] = min(V_val(:,t));
end

[~, worstHour] = min(Vmin_t);

% Effective demand served (nb x T)
Pd_eff_val = Pd_fixed + u_val .* Pncl0;
Qd_eff_val = Qd_fixed + u_val .* Qncl0;

% Curtailment ratio at ES buses
curtRatio = 1 - u_val(es_buses, :);   % numel(es_buses) x T

fprintf("\nES OPF solved successfully.\n");
fprintf("Worst hour by Vmin : hour %d  (Vmin=%.4f at bus %d)\n", ...
    worstHour, Vmin_t(worstHour), VminBus_t(worstHour));
fprintf("Total loss over 24h  (sum pu) : %.6f\n", sum(loss_t));
fprintf("Total weighted cost  (sum)    : %.6f\n", sum(costloss_t));
fprintf("Mean NCL curtailment @ ES buses: %.2f%%\n", 100*mean(curtRatio(:)));

% =========================================================================
%  SECTION 12 — SAVE OUTPUTS
% =========================================================================
outDir = './out_socp_opf_gurobi_es';
if ~exist(outDir, 'dir'), mkdir(outDir); end

% --- Summary table ---
summary = table((1:T).', price, Vmin_t, VminBus_t, loss_t, costloss_t, ...
    'VariableNames', {'Hour','Price','Vmin_pu','VminBus','Loss_pu','LossCost'});
writetable(summary, fullfile(outDir, 'es_opf_summary_24h.csv'));

% --- Voltage matrix ---
writetable(array2table(V_val, 'VariableNames', compose('h%02d',1:T)), ...
    fullfile(outDir, 'es_V_bus_by_hour.csv'));

% --- u (scaling factor) matrix ---
writetable(array2table(u_val, 'VariableNames', compose('h%02d',1:T)), ...
    fullfile(outDir, 'es_u_bus_by_hour.csv'));

% --- Effective demand ---
writetable(array2table(Pd_eff_val, 'VariableNames', compose('h%02d',1:T)), ...
    fullfile(outDir, 'es_Pd_eff_by_hour.csv'));
writetable(array2table(Qd_eff_val, 'VariableNames', compose('h%02d',1:T)), ...
    fullfile(outDir, 'es_Qd_eff_by_hour.csv'));

% --- ES bus curtailment detail ---
esLabels = compose('bus%d', es_buses(:));
curtTable = array2table(curtRatio, 'RowNames', esLabels, ...
    'VariableNames', compose('h%02d',1:T));
writetable(curtTable, fullfile(outDir, 'es_curtailment_ratio.csv'), ...
    'WriteRowNames', true);

% =========================================================================
%  SECTION 13 — PLOTS
% =========================================================================

% 1) Minimum voltage vs hour
figure; plot(1:T, Vmin_t, '-o'); grid on;
xlabel('Hour'); ylabel('Minimum Voltage (p.u.)');
title('ES SOCP-OPF: Minimum Voltage vs Hour');
saveas(gcf, fullfile(outDir, 'es_min_voltage_vs_hour.png'));

% 2) Loss vs hour
figure; plot(1:T, loss_t, '-o'); grid on;
xlabel('Hour'); ylabel('Total Loss (p.u.)');
title('ES SOCP-OPF: Loss vs Hour');
saveas(gcf, fullfile(outDir, 'es_loss_vs_hour.png'));

% 3) Voltage profile at worst hour
figure; plot(1:nb, V_val(:,worstHour), '-o'); grid on;
xlabel('Bus'); ylabel('Voltage (p.u.)');
title(sprintf('ES SOCP-OPF: Voltage Profile at Worst Hour %d', worstHour));
saveas(gcf, fullfile(outDir, sprintf('es_voltage_profile_worst_h%02d.png', worstHour)));

% 4) u(j,t) at ES buses over 24 hours
figure; hold on; grid on;
colors = lines(numel(es_buses));
for k = 1:numel(es_buses)
    plot(1:T, u_val(es_buses(k),:), '-o', 'Color', colors(k,:), ...
        'DisplayName', sprintf('Bus %d', es_buses(k)));
end
xlabel('Hour'); ylabel('NCL scaling u(j,t)');
title('ES Control: NCL Scaling Factor at ES Buses');
legend('Location','best');
hold off;
saveas(gcf, fullfile(outDir, 'es_u_vs_hour.png'));

% 5) Curtailment ratio at ES buses
figure; hold on; grid on;
for k = 1:numel(es_buses)
    plot(1:T, curtRatio(k,:)*100, '-o', 'Color', colors(k,:), ...
        'DisplayName', sprintf('Bus %d', es_buses(k)));
end
xlabel('Hour'); ylabel('NCL Curtailment (%)');
title('ES Control: Load Curtailment at ES Buses');
legend('Location','best');
hold off;
saveas(gcf, fullfile(outDir, 'es_curtailment_vs_hour.png'));

fprintf("Saved all outputs to: %s\n", outDir);

% =========================================================================
%  SECTION 14 — BASELINE COMPARISON (load Module 7 results if available)
%
%  Run this block AFTER running Module 7 (optimization.m) to produce
%  side-by-side comparison figures.
% =========================================================================
baseDir = './out_socp_opf_gurobi';
baseFile = fullfile(baseDir, 'opf_summary_24h_cost.csv');

if exist(baseFile, 'file') == 2
    base = readtable(baseFile);

    figure; hold on; grid on;
    plot(1:T, base.Vmin_pu,  '-s', 'DisplayName', 'Baseline (Module 7)');
    plot(1:T, Vmin_t,        '-o', 'DisplayName', 'ES OPF (Module 8)');
    xlabel('Hour'); ylabel('Minimum Voltage (p.u.)');
    title('Comparison: Baseline vs ES — Minimum Voltage');
    legend('Location','best');
    hold off;
    saveas(gcf, fullfile(outDir, 'compare_min_voltage.png'));

    figure; hold on; grid on;
    plot(1:T, base.Loss_pu,  '-s', 'DisplayName', 'Baseline (Module 7)');
    plot(1:T, loss_t,        '-o', 'DisplayName', 'ES OPF (Module 8)');
    xlabel('Hour'); ylabel('Total Loss (p.u.)');
    title('Comparison: Baseline vs ES — Feeder Losses');
    legend('Location','best');
    hold off;
    saveas(gcf, fullfile(outDir, 'compare_losses.png'));

    fprintf('\n--- Baseline vs ES comparison ---\n');
    fprintf('Metric                    Baseline     ES OPF\n');
    fprintf('Min Vmin over 24h         %.4f       %.4f\n', min(base.Vmin_pu), min(Vmin_t));
    fprintf('Total loss (sum pu)       %.6f     %.6f\n', sum(base.Loss_pu), sum(loss_t));
    fprintf('Total loss-cost (sum)     %.6f     %.6f\n', sum(base.LossCost), sum(costloss_t));
    fprintf('Mean curtailment @ ES     —            %.2f%%\n', 100*mean(curtRatio(:)));
else
    fprintf('\n[INFO] Baseline file not found at %s\n', baseFile);
    fprintf('Run Module 7 (optimization.m) first for comparison figures.\n');
end
