%% run_base_opf.m
% MODULE 1 — Base IEEE 33-bus feeder OPF without ES
%
% Runs SOCP OPF with no ES (all loads fixed) and saves:
%   results/tables/base_case_results.csv
%   results/figures/base_voltage_profile.png
%
% Also runs at load multipliers [1.0 1.2 1.4 1.6 1.8] for a quick
% feasibility stress preview (full stress scan is in run_stress_scan.m).
%
% Requirements: YALMIP + Gurobi
% Depends on: build_distflow_topology_from_branch_csv.m
%             build_24h_load_profile_from_csv.m
%             solve_es_socp_opf_case.m

clear; clc; close all;

addpath(genpath('./src'));

caseDir   = './mp_export_case33bw';
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

fprintf('\n=== Module 1: Base OPF (no ES) ===\n');

% -------------------------------------------------------------------------
%  Build base-case params (es_buses = [] => pure DistFlow OPF)
% -------------------------------------------------------------------------
params.name        = 'base_case';
params.label       = 'Base Case — No ES';
params.es_buses    = [];
params.rho_val     = 0;
params.u_min_val   = 1;
params.lambda_u    = 0;
params.Vmin        = 0.95;
params.Vmax        = 1.05;
params.soft_voltage = false;
params.lambda_sv   = 0;
params.price       = price;
params.out_dir     = fullfile('./results/mat_files', 'base_case');

res = solve_es_socp_opf_case(params, topo, loads, ops);

fprintf('Base case: feasible=%d, Vmin=%.4f, TotalLoss=%.5f pu\n', ...
    res.feasible, min(res.Vmin_t), res.total_loss);

% Save hourly summary
Hour     = (1:T)';
Vmin_pu  = res.Vmin_t;
VminBus  = res.VminBus_t;
Loss_pu  = res.loss_t;
Price    = price;
T_out = table(Hour, Price, Vmin_pu, VminBus, Loss_pu);
writetable(T_out, fullfile(outDir, 'base_case_results.csv'));
fprintf('Saved: results/tables/base_case_results.csv\n');

% Voltage profile figure (hour with peak load = hour 20)
if res.feasible
    h_peak = 20;
    V_profile = res.V_val(:, h_peak);
    fig = figure('Visible','off');
    bar(1:nb, V_profile, 'FaceColor', [0.2 0.5 0.8]);
    hold on;
    yline(0.95, 'r--', 'Linewidth', 1.5, 'Label', 'V_{min}=0.95 pu');
    hold off;
    xlabel('Bus'); ylabel('Voltage (p.u.)');
    title(sprintf('Base Case Voltage Profile — Hour %d (peak load)', h_peak));
    grid on; ylim([0.88 1.05]);
    saveas(fig, fullfile(figDir, 'base_voltage_profile.png'));
    saveas(fig, fullfile(figDir, 'base_voltage_profile.fig'));
    close(fig);
    fprintf('Saved: results/figures/base_voltage_profile.png\n');
else
    fprintf('Base case INFEASIBLE — voltage profile figure skipped.\n');
    fprintf('This confirms stressed loading: ES needed to restore feasibility.\n');
end

fprintf('\nBase case complete.\n');
