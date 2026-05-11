%% run_stage3_ess.m
% STAGE 3 — ESS with SOC Dynamics
%
% Motivation: Stage 2 showed 7 STATCOM (reactive-only) or 32 ES + 2 STATCOM
% needed for feasibility. ESS provides BOTH active time-shifting (P_dis)
% AND reactive injection (Q_b from inverter), potentially outperforming
% either ES or STATCOM alone.
%
% Cases:
%   C8: ESS-only — sweep N_b to find minimum for V >= 0.95
%   C9: ES + ESS — sweep N_b with full ES budget; quantify ES benefit
%
% ESS model: 1.0 pu·h capacity, 0.5 pu power, 0.10 pu reactive,
%            eta=0.95, 50% initial SOC, daily cyclic constraint.
%
% Output:
%   04_results/es_framework/tables/table_stage3_ess_sweep.csv
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
fprintf('  STAGE 3 — ESS WITH SOC DYNAMICS\n');
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

N_b_sweep = 1:10;
N_e_fixed = 32;

%% VSI CANDIDATE RESTRICTION (same as Stage 2)
K_cand = 15;
fprintf('Computing VSI for ESS candidate selection...\n');
vsi = calculate_voltage_impact_score(topo, loads, rho);
ess_cand = sort(vsi.rank(1:K_cand)');
ess_cand = ess_cand(ess_cand ~= topo.root);
fprintf('  ESS candidates (top-%d VSI): %s\n\n', K_cand, mat2str(ess_cand));

%% BASE PARAMS
p_base.Vmin          = 0.95;
p_base.Vmax          = 1.05;
p_base.soft_voltage  = false;    % hard voltage for fast infeasibility detection
p_base.obj_mode      = 'planning';
p_base.w_loss        = 1.0;
p_base.w_b           = 0.0;
p_base.w_vio         = 0.0;
p_base.candidate_buses = ess_cand;
p_base.price         = price;
p_base.time_limit    = 120;
p_base.MIPGap        = 0.05;
% ESS parameters
p_base.E_cap_pu      = 1.0;
p_base.P_ch_max_pu   = 0.5;
p_base.P_dis_max_pu  = 0.5;
p_base.Q_b_max_pu    = 0.10;
p_base.eta_ch        = 0.95;
p_base.eta_dis       = 0.95;
p_base.SOC_init      = 0.50;
p_base.SOC_min       = 0.10;

%% C8: ESS-ONLY SWEEP
fprintf('--- C8: ESS-only sweep ---\n');
rows_c8 = {};
N_b_min_c8 = NaN;

for N_b = N_b_sweep
    p8 = p_base;
    p8.N_b_max = N_b;

    fprintf('\n  C8 | N_b_max=%d\n', N_b);
    r = solve_ess_misocp(topo, loads, p8);

    rows_c8{end+1} = make_row(sprintf('C8_ESS_Nb%d',N_b), 'ESS-only', N_b, NaN, r);

    if r.voltage_ok && isnan(N_b_min_c8)
        N_b_min_c8 = N_b;
        fprintf('\n  >>> C8 FEASIBLE at N_b=%d!\n', N_b);
        break
    end
end

if isnan(N_b_min_c8)
    fprintf('\n  C8: Not feasible in N_b=1..%d. Check ESS capacity params.\n', max(N_b_sweep));
end

%% C9: ES + ESS SWEEP
fprintf('\n--- C9: ES+ESS sweep (N_e=%d) ---\n', N_e_fixed);
rows_c9 = {};
N_b_min_c9 = NaN;
N_b_limit  = max(N_b_sweep);
if ~isnan(N_b_min_c8), N_b_limit = N_b_min_c8; end

for N_b = 0:N_b_limit
    p9 = rmfield(p_base, 'candidate_buses');
    p9.rho                = rho;
    p9.u_min              = u_min;
    p9.N_e_max            = N_e_fixed;
    p9.N_b_max            = N_b;
    p9.candidate_buses_es = setdiff(1:topo.nb, topo.root)';
    p9.candidate_buses_b  = ess_cand;
    p9.w_e                = 0.0;
    p9.w_curt             = 0.0;

    fprintf('\n  C9 | N_e_max=%d N_b_max=%d\n', N_e_fixed, N_b);
    r = solve_es_ess_misocp(topo, loads, p9);

    rows_c9{end+1} = make_row(sprintf('C9_ES%d_ESS_Nb%d',N_e_fixed,N_b), ...
        'ES+ESS', N_b, N_e_fixed, r);

    if r.voltage_ok && isnan(N_b_min_c9)
        N_b_min_c9 = N_b;
        fprintf('\n  >>> C9 FEASIBLE at N_b=%d (N_e=%d)!\n', N_b, N_e_fixed);
        break
    end
end

%% BUILD TABLE
all_rows = [rows_c8, rows_c9];
col_names = {'CaseName','CaseType','N_b_max','N_e_max', ...
    'N_b_used','N_e_used', ...
    'SolverOK','VoltageFeasible','Feasible', ...
    'Vmin_pu','WorstBus','WorstHour', ...
    'TotalLoss_pu','TotalQb_pu','NetDis_pu', ...
    'MeanCurt','TotalVoltSlack_pu','SolveTime_s'};

T_out = cell2table(vertcat(all_rows{:}), 'VariableNames', col_names);
fname = fullfile(out_tabs, 'table_stage3_ess_sweep.csv');
writetable(T_out, fname);
fprintf('\n  Saved: %s\n', fname);

%% SUMMARY
fprintf('\n');
fprintf('=========================================================\n');
fprintf('  STAGE 3 SUMMARY\n');
fprintf('  ESS: E_cap=%.1f pu·h | P_max=%.2f pu | Qb_max=%.2f pu\n', ...
    p_base.E_cap_pu, p_base.P_ch_max_pu, p_base.Q_b_max_pu);
fprintf('=========================================================\n');
fprintf('  %-28s %4s %4s %5s %5s %8s %8s\n','Case','Nb','Ne','SolOK','VoltOK','Vmin','Qb');
for i = 1:height(T_out)
    fprintf('  %-28s %4d %4s %5d %5d %8.4f %8.4f\n', ...
        T_out.CaseName{i}, T_out.N_b_max(i), num2str(T_out.N_e_max(i)), ...
        T_out.SolverOK(i), T_out.VoltageFeasible(i), ...
        T_out.Vmin_pu(i), T_out.TotalQb_pu(i));
end
fprintf('=========================================================\n');

if ~isnan(N_b_min_c8)
    fprintf('  Min ESS (C8, no ES):    N_b = %d\n', N_b_min_c8);
end
if ~isnan(N_b_min_c9)
    fprintf('  Min ESS (C9, N_e=%d ES): N_b = %d\n', N_e_fixed, N_b_min_c9);
    if ~isnan(N_b_min_c8)
        fprintf('  ES saves %d ESS device(s).\n', N_b_min_c8 - N_b_min_c9);
    end
end
fprintf('\n  Stage 2 reference: STATCOM-only N_s=7, ES+STATCOM N_s=2\n');

fprintf('\n=========================================================\n');
fprintf('  STAGE 3 COMPLETE\n');
fprintf('  Output: 04_results/es_framework/tables/\n');
fprintf('=========================================================\n\n');

% -------------------------------------------------------------------------
function row = make_row(name, ctype, N_b_max, N_e_max, r)
sol_ok  = double(isfield(r,'solver_ok') && r.solver_ok);
volt_ok = double(isfield(r,'voltage_ok') && r.voltage_ok);
feas    = double(sol_ok && volt_ok);
n_b  = getrf(r,'n_ess',     NaN);
n_e  = getrf(r,'n_es',      NaN);
Vm   = getrf(r,'Vmin_24h',  NaN);
wb   = getrf(r,'worst_bus', NaN);
wh   = getrf(r,'worst_hour',NaN);
Lo   = getrf(r,'total_loss',NaN);
Qb   = getrf(r,'total_Qb',  NaN);
Pd   = getrf(r,'net_dis',   NaN);
Mc   = getrf(r,'mean_curt', NaN);
sv   = getrf(r,'total_sv',  NaN);
ts   = getrf(r,'solve_time',NaN);
row = {name,ctype,N_b_max,N_e_max,n_b,n_e,sol_ok,volt_ok,feas,...
       Vm,wb,wh,Lo,Qb,Pd,Mc,sv,ts};
end

function v = getrf(s, f, default)
if isfield(s,f)
    raw = s.(f);
    if isnumeric(raw) && ~isempty(raw) && ~isnan(raw(1))
        v = raw(1);
    else, v = default; end
else, v = default; end
end
