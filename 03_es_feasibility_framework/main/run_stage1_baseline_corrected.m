%% run_stage1_baseline_corrected.m
% STAGE 1 — Corrected Feasibility Labels + Baseline Table
%
% Fixes:
%   - Unified 3-field labeling: SolverOK / VoltageFeasible / Feasible
%   - Post-hoc voltage check on all solvers (not just MISOCP)
%   - Consistent C0-C5 comparison
%
% Output:
%   04_results/es_framework/tables/table_case_baseline_corrected.csv
%
% Requirements: MATLAB R2020a+, YALMIP, Gurobi
% Run from: repo root  OR  03_es_feasibility_framework/main/

clear; clc; close all;

%% PATH SETUP
script_dir = fileparts(mfilename('fullpath'));
new_root   = fileparts(script_dir);
repo_root  = fileparts(new_root);

addpath(genpath(fullfile(new_root, 'functions')));
addpath(genpath(fullfile(new_root, 'plotting')));
addpath(genpath(fullfile(new_root, 'data')));
addpath(genpath(fullfile(repo_root, '02_baseline_modules', 'shared')));

out_base = fullfile(repo_root, '04_results', 'es_framework');
out_tabs = fullfile(out_base, 'tables');
if ~exist(out_tabs,'dir'), mkdir(out_tabs); end

fprintf('\n');
fprintf('=========================================================\n');
fprintf('  STAGE 1 — CORRECTED FEASIBILITY BASELINE\n');
fprintf('  IEEE 33-Bus | rho=0.70 | u_min=0.20\n');
fprintf('=========================================================\n\n');

%% LOAD NETWORK
fprintf('Loading IEEE 33-bus network...\n');
[topo, loads] = build_ieee33_network(repo_root, 1.80);

%% RUN CASES C0-C5
fprintf('\nRunning cases C0–C5...\n');
ops = sdpsettings('solver','gurobi','verbose',0);
ops.gurobi.TimeLimit = 300;

T_corrected = compare_final_ieee33_cases(topo, loads, out_tabs, ops);

%% ALSO SAVE TO NAMED FILE (Stage 1 artifact)
fname_corrected = fullfile(out_tabs, 'table_case_baseline_corrected.csv');
writetable(T_corrected, fname_corrected);
fprintf('\nStage 1 artifact: %s\n', fname_corrected);

%% DIAGNOSTIC: Flag any cases where SolverOK=1 but VoltageFeasible=0
bad_mask = (T_corrected.SolverOK == 1) & (T_corrected.VoltageFeasible == 0);
if any(bad_mask)
    fprintf('\n  WARNING: %d case(s) where solver succeeded but voltages violated:\n', sum(bad_mask));
    for i = find(bad_mask)'
        fprintf('    -> %s  Vmin=%.4f  VoltSlack=%.6f\n', ...
            T_corrected.Case{i}, T_corrected.Vmin_pu(i), T_corrected.TotalVoltSlack_pu(i));
    end
else
    fprintf('\n  OK: No cases with SolverOK=1 but VoltageFeasible=0.\n');
end

%% DIAGNOSTIC: Flag any cases with non-zero voltage slack despite Feasible=1
slack_mask = (T_corrected.Feasible == 1) & (T_corrected.TotalVoltSlack_pu > 1e-4);
if any(slack_mask)
    fprintf('\n  WARNING: %d feasible case(s) with non-trivial voltage slack:\n', sum(slack_mask));
    for i = find(slack_mask)'
        fprintf('    -> %s  TotalSlack=%.6f\n', ...
            T_corrected.Case{i}, T_corrected.TotalVoltSlack_pu(i));
    end
end

fprintf('\n=========================================================\n');
fprintf('  STAGE 1 COMPLETE\n');
fprintf('  Output: 04_results/es_framework/tables/\n');
fprintf('=========================================================\n\n');
