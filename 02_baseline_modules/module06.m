%% run_stress_scan.m
% MODULE 2 — Stressed loading scenarios
%
% Sweeps load multiplier [1.00, 1.20, 1.40, 1.60, 1.80] and records
% feasibility, Vmin, buses below 0.95 pu, and total loss — all without ES.
%
% Uses soft-voltage constraints so the solver always converges;
% voltage slack reveals how far the feeder is from the 0.95 limit.
%
% Output:
%   results/tables/stress_scan_results.csv
%   results/figures/min_voltage_vs_load_multiplier.png
%   results/figures/voltage_profiles_stress_levels.png
%
% Requirements: YALMIP + Gurobi

clear; clc; close all;
addpath(genpath('./02_baseline_modules/shared'));

caseDir   = './01_data';
branchCsv = fullfile(caseDir, 'branch.csv');
loadsCsv  = fullfile(caseDir, 'loads_base.csv');
assert(exist(branchCsv,'file')==2, 'Missing: %s', branchCsv);
assert(exist(loadsCsv, 'file')==2, 'Missing: %s', loadsCsv);

topo  = build_distflow_topology_from_branch_csv(branchCsv, 1);
loads = build_24h_load_profile_from_csv(loadsCsv, 'system', true, false);
nb    = topo.nb;
T     = 24;

price = ones(T,1);
price(1:6)=0.6; price(7:16)=1.0; price(17:21)=1.8; price(22:24)=0.9;

ops = sdpsettings('solver','gurobi','verbose',0);

outDir = './results/tables';
figDir = './results/figures';
if ~exist(outDir,'dir'), mkdir(outDir); end
if ~exist(figDir,'dir'), mkdir(figDir); end

fprintf('\n=== Module 2: Stress Scan ===\n');

lambda_vals = [1.00, 1.20, 1.40, 1.60, 1.80];
nL = numel(lambda_vals);

rows_Multiplier  = zeros(nL,1);
rows_Feasible    = false(nL,1);
rows_Vmin        = NaN(nL,1);
rows_VminBus     = NaN(nL,1);
rows_Loss        = NaN(nL,1);
rows_NviolBuses  = NaN(nL,1);
rows_MaxViolMag  = NaN(nL,1);
V_profiles_peak  = NaN(nb, nL);  % for figure

for ii = 1:nL
    lam = lambda_vals(ii);
    fprintf('  Loading multiplier %.2f ...\n', lam);

    % Scale loads
    loads_stressed      = loads;
    loads_stressed.P24  = lam * loads.P24;
    loads_stressed.Q24  = lam * loads.Q24;

    params.name         = sprintf('stress_lam%d', round(lam*100));
    params.label        = sprintf('Stress x%.2f', lam);
    params.es_buses     = [];
    params.rho_val      = 0;
    params.u_min_val    = 1;
    params.lambda_u     = 0;
    params.Vmin         = 0.95;
    params.Vmax         = 1.05;
    params.soft_voltage = true;    % soft so solver always converges
    params.lambda_sv    = 1000;    % large penalty to push toward feasibility
    params.price        = price;
    params.out_dir      = '';

    res = solve_es_socp_opf_case(params, topo, loads_stressed, ops);

    rows_Multiplier(ii) = lam;

    if res.feasible || res.sol_code == 0
        V_hr20 = res.V_val(:, 20);  % peak hour
        vmin   = min(V_hr20);
        vmin_b = find(V_hr20 == vmin, 1);
        n_viol = sum(V_hr20 < 0.95);
        max_viol = max(0, 0.95 - vmin);

        rows_Feasible(ii)   = (res.max_sv < 1e-6);
        rows_Vmin(ii)       = vmin;
        rows_VminBus(ii)    = vmin_b;
        rows_Loss(ii)       = res.total_loss;
        rows_NviolBuses(ii) = n_viol;
        rows_MaxViolMag(ii) = max_viol;
        V_profiles_peak(:, ii) = V_hr20;
    end

    fprintf('    Vmin=%.4f, NviolBuses=%d, Feasible=%d\n', ...
        rows_Vmin(ii), rows_NviolBuses(ii), rows_Feasible(ii));
end

% Save table
T_out = table(rows_Multiplier, rows_Feasible, rows_Vmin, rows_VminBus, ...
              rows_Loss, rows_NviolBuses, rows_MaxViolMag, ...
    'VariableNames', {'LoadMultiplier','Feasible','Vmin_pu','VminBus', ...
                      'TotalLoss_pu','N_Viol_Buses','MaxViolMag_pu'});
writetable(T_out, fullfile(outDir, 'stress_scan_results.csv'));
fprintf('Saved: results/tables/stress_scan_results.csv\n');

% Figure 1: Vmin vs load multiplier
fig1 = figure('Visible','off');
plot(lambda_vals, rows_Vmin, '-o', 'LineWidth', 1.5, 'MarkerSize', 7);
hold on;
yline(0.95, 'r--', 'LineWidth', 1.5, 'Label', 'V_{min} = 0.95 pu');
hold off;
xlabel('Load Multiplier'); ylabel('Minimum Voltage (p.u.)');
title('Minimum Voltage vs Load Multiplier (No ES)');
grid on;
saveas(fig1, fullfile(figDir, 'min_voltage_vs_load_multiplier.png'));
saveas(fig1, fullfile(figDir, 'min_voltage_vs_load_multiplier.fig'));
close(fig1);

% Figure 2: Voltage profiles per stress level (peak hour)
fig2 = figure('Visible','off');
hold on;
colors = lines(nL);
for ii = 1:nL
    if ~any(isnan(V_profiles_peak(:,ii)))
        plot(1:nb, V_profiles_peak(:,ii), '-o', 'Color', colors(ii,:), ...
            'LineWidth', 1.2, 'DisplayName', sprintf('x%.2f', lambda_vals(ii)));
    end
end
yline(0.95, 'k--', 'LineWidth', 1.5);
hold off;
xlabel('Bus Index'); ylabel('Voltage (p.u.)');
title('Voltage Profiles at Peak Hour — Multiple Stress Levels (No ES)');
legend('Location','southwest'); grid on; ylim([0.80 1.05]);
saveas(fig2, fullfile(figDir, 'voltage_profiles_stress_levels.png'));
saveas(fig2, fullfile(figDir, 'voltage_profiles_stress_levels.fig'));
close(fig2);

fprintf('\nStress scan complete.\n');
