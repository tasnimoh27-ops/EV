%% run_stage2_statcom.m
% STAGE 2 — STATCOM Reactive Support: Minimum Device Sweep
%
% Motivation (from Stage 1): ES-only approach cannot restore V >= 0.95 pu
% at 1.80x EV penetration even with 32 devices. Reactive injection is the
% key mechanism (C1 Qg-only achieved feasibility at Qs_max=0.10 pu/bus).
%
% Stage 2 investigates:
%   C6: STATCOM-only — sweep N_s to find minimum count for feasibility
%   C7: ES + STATCOM — sweep N_s with full ES budget, quantify ES benefit
%
% Parameters match Stage 1: rho=0.70, u_min=0.20, Vmin=0.95, scale=1.80
%
% Output:
%   04_results/es_framework/tables/table_stage2_statcom_sweep.csv
%   04_results/es_framework/tables/table_stage2_summary.csv
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
fprintf('  STAGE 2 — STATCOM REACTIVE SUPPORT\n');
fprintf('  IEEE 33-Bus | rho=0.70 | u_min=0.20 | scale=1.80\n');
fprintf('=========================================================\n\n');

%% LOAD NETWORK
fprintf('Loading IEEE 33-bus network...\n');
[topo, loads] = build_ieee33_network(repo_root, 1.80);

rho   = 0.70;
u_min = 0.20;
T     = 24;
price = ones(T,1);
price(1:6)=0.6; price(7:16)=1.0; price(17:21)=1.8; price(22:24)=0.9;

% STATCOM per-device capacity — matches C1 Qg_max_pu for fair comparison
Qs_max_pu  = 0.10;
N_s_sweep  = 1:10;   % sweep up to 10 STATCOMs (stop early if feasible)
N_e_fixed  = 32;     % full ES budget for C7

%% BASE PARAMS (shared)
p_base.Vmin          = 0.95;
p_base.Vmax          = 1.05;
p_base.soft_voltage  = true;
p_base.obj_mode      = 'feasibility';
p_base.price         = price;
p_base.time_limit    = 300;
p_base.MIPGap        = 0.01;
p_base.Qs_max_pu     = Qs_max_pu;

%% C6: STATCOM-ONLY SWEEP
fprintf('\n--- C6: STATCOM-only sweep (Qs_max=%.2f pu/device) ---\n', Qs_max_pu);
rows_c6 = {};
N_s_min_c6 = NaN;

for N_s = N_s_sweep
    p6 = p_base;
    p6.N_s_max = N_s;

    fprintf('\n  C6 | N_s_max=%d\n', N_s);
    r = solve_statcom_misocp(topo, loads, p6);

    row = make_row_statcom(sprintf('C6_STATCOM_Ns%d', N_s), ...
        'STATCOM-only', N_s, NaN, r);
    rows_c6{end+1} = row;

    if r.voltage_ok && isnan(N_s_min_c6)
        N_s_min_c6 = N_s;
        fprintf('\n  >>> C6 FEASIBLE at N_s=%d! Stopping sweep.\n', N_s);
        break
    end
end

if isnan(N_s_min_c6)
    fprintf('\n  C6: Not feasible within N_s=1..%d at Qs_max=%.2f pu\n', ...
        max(N_s_sweep), Qs_max_pu);
    fprintf('  Consider increasing Qs_max_pu or N_s_sweep range.\n');
end

%% C7: ES + STATCOM SWEEP
fprintf('\n--- C7: ES+STATCOM sweep (N_e=%d, Qs_max=%.2f pu/device) ---\n', ...
    N_e_fixed, Qs_max_pu);
rows_c7 = {};
N_s_min_c7 = NaN;
N_s_limit  = max(N_s_sweep);
if ~isnan(N_s_min_c6)
    N_s_limit = N_s_min_c6;  % no need to go beyond C6 minimum
end

for N_s = 0:N_s_limit
    p7 = p_base;
    p7.rho    = rho;
    p7.u_min  = u_min;
    p7.N_e_max = N_e_fixed;
    p7.N_s_max = N_s;

    fprintf('\n  C7 | N_e_max=%d N_s_max=%d\n', N_e_fixed, N_s);
    r = solve_es_statcom_misocp(topo, loads, p7);

    row = make_row_statcom(sprintf('C7_ES%d_STATCOM_Ns%d', N_e_fixed, N_s), ...
        'ES+STATCOM', N_s, N_e_fixed, r);
    rows_c7{end+1} = row;

    if r.voltage_ok && isnan(N_s_min_c7)
        N_s_min_c7 = N_s;
        fprintf('\n  >>> C7 FEASIBLE at N_s=%d (with N_e=%d ES)! Stopping sweep.\n', ...
            N_s, N_e_fixed);
        break
    end
end

%% BUILD SWEEP TABLE
all_rows = [rows_c6, rows_c7];
col_names = {'CaseName','CaseType','N_s_max','N_e_max', ...
    'N_s_used','N_e_used','Qs_max_pu', ...
    'SolverOK','VoltageFeasible','Feasible', ...
    'Vmin_pu','WorstBus','WorstHour', ...
    'TotalLoss_pu','TotalQs_pu','MeanQs_pu', ...
    'MeanCurt','TotalVoltSlack_pu','SolveTime_s'};

sweep_table = cell2table(vertcat(all_rows{:}), 'VariableNames', col_names);
fname_sweep = fullfile(out_tabs, 'table_stage2_statcom_sweep.csv');
writetable(sweep_table, fname_sweep);
fprintf('\n  Saved sweep: %s\n', fname_sweep);

%% SUMMARY TABLE
fprintf('\n');
fprintf('=========================================================\n');
fprintf('  STAGE 2 SUMMARY\n');
fprintf('  Qs_max_pu=%.2f | rho=%.2f | u_min=%.2f\n', Qs_max_pu, rho, u_min);
fprintf('=========================================================\n');
fprintf('  %-28s %4s %4s %5s %5s %8s %8s\n', ...
    'Case','Ns','Ne','SolOK','VoltOK','Vmin','TotQs');
for i = 1:height(sweep_table)
    T_ = sweep_table;
    fprintf('  %-28s %4d %4s %5d %5d %8.4f %8.4f\n', ...
        T_.CaseName{i}, T_.N_s_max(i), ...
        num2str(T_.N_e_max(i)), ...
        T_.SolverOK(i), T_.VoltageFeasible(i), ...
        T_.Vmin_pu(i), T_.TotalQs_pu(i));
end
fprintf('=========================================================\n');

if ~isnan(N_s_min_c6)
    fprintf('  Min STATCOM (C6, no ES):   N_s = %d\n', N_s_min_c6);
end
if ~isnan(N_s_min_c7)
    fprintf('  Min STATCOM (C7, N_e=%d ES): N_s = %d\n', N_e_fixed, N_s_min_c7);
    if ~isnan(N_s_min_c6)
        fprintf('  ES saves %d STATCOM device(s).\n', N_s_min_c6 - N_s_min_c7);
    end
end

fprintf('\n=========================================================\n');
fprintf('  STAGE 2 COMPLETE\n');
fprintf('  Output: 04_results/es_framework/tables/\n');
fprintf('=========================================================\n\n');

% -------------------------------------------------------------------------
function row = make_row_statcom(name, ctype, N_s_max, N_e_max, r)
sol_ok  = double(isfield(r,'solver_ok') && r.solver_ok);
volt_ok = double(isfield(r,'voltage_ok') && r.voltage_ok);
feas    = double(sol_ok && volt_ok);

n_s  = getrf(r, 'n_statcom',  NaN);
n_e  = getrf(r, 'n_es',       NaN);
Vm   = getrf(r, 'Vmin_24h',   NaN);
wb   = getrf(r, 'worst_bus',  NaN);
wh   = getrf(r, 'worst_hour', NaN);
Lo   = getrf(r, 'total_loss', NaN);
Qs   = getrf(r, 'total_Qs',   NaN);
mQs  = getrf(r, 'mean_Qs',    NaN);
Mc   = getrf(r, 'mean_curt',  NaN);
sv   = getrf(r, 'total_sv',   NaN);
ts   = getrf(r, 'solve_time', NaN);
Qmax = getrf(r, 'Qs_max_pu',  NaN);

row = {name, ctype, N_s_max, N_e_max, ...
       n_s, n_e, Qmax, ...
       sol_ok, volt_ok, feas, ...
       Vm, wb, wh, Lo, Qs, mQs, Mc, sv, ts};
end

function v = getrf(s, f, default)
if isfield(s,f)
    raw = s.(f);
    if isnumeric(raw) && ~isempty(raw) && ~isnan(raw(1))
        v = raw(1);
    else
        v = default;
    end
else
    v = default;
end
end
