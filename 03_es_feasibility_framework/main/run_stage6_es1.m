%% run_stage6_es1.m
% STAGE 6 — ES-1 (Hou) Reactive Model
%
% Motivation: Stages 1-5 showed basic ES (curtailment-only) cannot restore
% V >= 0.95 alone (N_e=32 gives Vmin=0.9324). Reactive injection is the
% bottleneck. The Hou ES-1 model equips each ES device with independent
% reactive injection Q_es from its inverter — converting ES from a purely
% active resource to an active+reactive resource.
%
% Research question: does ES-1 reactive capability allow ES alone to achieve
% voltage feasibility, and at what minimum device count?
%
% Cases:
%   C14: ES-1 only — sweep N_e to find minimum for V >= 0.95
%   C15: ES-1 vs basic ES — matched N_e comparison (Vmin, Loss, Qes)
%   C16: ES-1 vs STATCOM, ESS — minimum device count comparison
%
% Stage 1 reference (basic ES):
%   N_e=32 -> Vmin=0.9324 (infeasible, reactive bottleneck)
%
% Stage 2/3 references:
%   STATCOM-only: N_s_min = 7
%   ESS-only:     N_b_min = 3
%
% Output:
%   04_results/es_framework/tables/table_stage6_es1_sweep.csv
%   04_results/es_framework/tables/table_stage6_comparison.csv
%
% Requirements: MATLAB R2020a+, YALMIP, Gurobi
% Run from: repo root  OR  03_es_feasibility_framework/main/

clear; clc; close all;

%% PATH SETUP
script_dir = fileparts(mfilename('fullpath'));
new_root   = fileparts(script_dir);
repo_root  = fileparts(new_root);

addpath(genpath(fullfile(new_root, 'functions')));
addpath(genpath(fullfile(new_root, 'data')));
addpath(genpath(fullfile(repo_root, '02_baseline_modules', 'shared')));

out_tabs = fullfile(repo_root, '04_results', 'es_framework', 'tables');
if ~exist(out_tabs,'dir'), mkdir(out_tabs); end

fprintf('\n');
fprintf('=========================================================\n');
fprintf('  STAGE 6 — ES-1 (HOU) REACTIVE MODEL\n');
fprintf('  IEEE 33-Bus | rho=0.70 | u_min=0.20 | scale=1.80\n');
fprintf('  Q_es_max = 0.10 pu/device\n');
fprintf('=========================================================\n\n');

%% LOAD NETWORK
fprintf('Loading network...\n');
[topo, loads] = build_ieee33_network(repo_root, 1.80);

rho   = 0.70;
u_min = 0.20;
T     = 24;
price = ones(T,1);
price(1:6)=0.6; price(7:16)=1.0; price(17:21)=1.8; price(22:24)=0.9;

%% VSI CANDIDATE RESTRICTION (consistent with Stages 1-5)
K_cand = 15;
vsi = calculate_voltage_impact_score(topo, loads, rho);
es_cand = sort(vsi.rank(1:K_cand)');
es_cand = es_cand(es_cand ~= topo.root);
fprintf('  ES-1 candidates (top-%d VSI): %s\n\n', K_cand, mat2str(es_cand));

%% BASE PARAMS
p_base.Vmin           = 0.95;
p_base.Vmax           = 1.05;
p_base.soft_voltage   = false;
p_base.obj_mode       = 'planning';
p_base.w_loss         = 1.0;
p_base.w_ES           = 0.0;
p_base.w_curt         = 0.0;
p_base.w_vio          = 0.0;
p_base.rho            = rho;
p_base.u_min          = u_min;
p_base.Q_es_max_pu    = 0.10;
p_base.price          = price;
p_base.time_limit     = 120;
p_base.MIPGap         = 0.05;
p_base.candidate_buses = es_cand;

%% C14: ES-1 ONLY SWEEP — find minimum N_e for V >= 0.95
fprintf('--- C14: ES-1 sweep (Q_es_max=%.2f pu/device) ---\n', p_base.Q_es_max_pu);
N_e_min_es1 = NaN;
rows_c14 = {};

for N_e = 1:32
    p = p_base;
    p.N_ES_max = N_e;

    fprintf('\n  C14 | N_e_max=%d\n', N_e);
    r = solve_es1_misocp(topo, loads, p);

    rows_c14{end+1} = make_row(sprintf('C14_ES1_Ne%d',N_e), 'ES1-only', N_e, r);

    if r.voltage_ok && isnan(N_e_min_es1)
        N_e_min_es1 = N_e;
        fprintf('\n  >>> C14 FEASIBLE at N_e=%d!\n', N_e);
        break
    end
end

if isnan(N_e_min_es1)
    fprintf('\n  C14: ES-1 not feasible in N_e=1..32. Increase Q_es_max_pu.\n');
end

%% C15: ES-1 vs BASIC ES — matched N_e comparison
% Run at N_e = {8, 16, 24, 32} for both models, compare Vmin and reactive usage
fprintf('\n--- C15: ES-1 vs Basic ES at matched N_e ---\n');
Ne_compare = [8, 16, 24, 32];
rows_c15 = {};

for N_e = Ne_compare
    p = p_base;
    p.N_ES_max = N_e;

    fprintf('\n  C15 | ES-1 N_e=%d\n', N_e);
    r = solve_es1_misocp(topo, loads, p);
    rows_c15{end+1} = make_row(sprintf('C15_ES1_Ne%d',N_e), 'ES1-compare', N_e, r);
end

%% BUILD TABLE
all_rows = [rows_c14, rows_c15];
col_names = {'CaseName','CaseType','N_e_max', ...
    'N_e_used','SolverOK','VoltageFeasible', ...
    'Vmin_pu','WorstBus','WorstHour', ...
    'TotalLoss_pu','TotalQes_pu','MeanCurt_frac','SolveTime_s'};

T_out = cell2table(vertcat(all_rows{:}), 'VariableNames', col_names);
fname = fullfile(out_tabs, 'table_stage6_es1_sweep.csv');
writetable(T_out, fname);
fprintf('\n  Saved: %s\n', fname);

%% C16: CROSS-STAGE COMPARISON TABLE
% Compare minimum-device configurations across all stages
fprintf('\n--- C16: Cross-stage minimum device comparison ---\n');

% Reference results from prior stages (confirmed)
comp_cases = {
    'C_basic_ES_N32',  'Basic ES',      32, 0,   0,  NaN,    0.9324, 0.51234; % Stage 1
    'C_STATCOM_N7',    'STATCOM-only',   0, 7,   0,  NaN,    0.9500, 0.53246; % Stage 2
    'C_ESS_N3',        'ESS-only',       0, 0,   3,  NaN,    0.9500, 0.43613; % Stage 3
    'C_ES_STATCOM_N2', 'ES+STATCOM',    32, 2,   0,  NaN,    0.9500, 0.07859; % Stage 2 C7
    'C_ES_ESS_N1',     'ES+ESS',        32, 0,   1,  NaN,    0.9543, 0.08262; % Stage 3 C9
};

comp_col = {'CaseName','Model','N_e','N_s','N_b','N_e1','Vmin_pu','Loss_pu'};

% Fill in ES-1 result from C14
Ne1_min = NaN; Vm1 = NaN; Lo1 = NaN;
if ~isnan(N_e_min_es1)
    row14 = rows_c14{end};  % last C14 row = first feasible
    Ne1_min = N_e_min_es1;
    Vm1 = row14{7};  % Vmin_pu
    Lo1 = row14{10}; % TotalLoss_pu
end

% Add ES-1 row
comp_cases(end+1,:) = {'C14_ES1_min', 'ES-1 only', 0, 0, 0, Ne1_min, Vm1, Lo1};

T_comp = cell2table(comp_cases, 'VariableNames', comp_col);
fname_comp = fullfile(out_tabs, 'table_stage6_comparison.csv');
writetable(T_comp, fname_comp);
fprintf('  Saved: %s\n', fname_comp);

%% PRINT SUMMARY
fprintf('\n');
fprintf('=========================================================\n');
fprintf('  STAGE 6 — ES-1 REACTIVE MODEL SUMMARY\n');
fprintf('  Basic ES reference: N_e=32 -> Vmin=0.9324 (infeasible)\n');
fprintf('=========================================================\n');
fprintf('  %-28s %4s %4s %4s %4s %8s %8s\n', ...
    'Model','N_e','N_s','N_b','N_e1','Vmin','Loss');
fprintf('  %s\n', repmat('-',1,70));
for i = 1:height(T_comp)
    fprintf('  %-28s %4s %4s %4s %4s %8s %8s\n', ...
        T_comp.CaseName{i}, ...
        fmtval(T_comp.N_e(i),'%d'), ...
        fmtval(T_comp.N_s(i),'%d'), ...
        fmtval(T_comp.N_b(i),'%d'), ...
        fmtval(T_comp.N_e1(i),'%d'), ...
        fmtval(T_comp.Vmin_pu(i),'%.4f'), ...
        fmtval(T_comp.Loss_pu(i),'%.5f'));
end
fprintf('  %s\n', repmat('-',1,70));

fprintf('\n  ES-1 minimum device summary:\n');
fprintf('    Basic ES alone:    N_e=32 -> INFEASIBLE (Vmin=0.9324)\n');
if ~isnan(N_e_min_es1)
    fprintf('    ES-1 alone:        N_e=%d  -> FEASIBLE  (Vmin=%.4f)\n', ...
        N_e_min_es1, Vm1);
    fprintf('    STATCOM-only:      N_s=7   -> FEASIBLE  (Vmin=0.9500)\n');
    fprintf('    ESS-only:          N_b=3   -> FEASIBLE  (Vmin=0.9500)\n');
    fprintf('\n    ES-1 reactive injection: %.0f devices vs 7 STATCOM or 3 ESS\n', ...
        N_e_min_es1);
else
    fprintf('    ES-1 alone:        not feasible in N_e=1..32\n');
end

fprintf('\n  C15 — ES-1 vs Basic ES (matched N_e):\n');
fprintf('  %-8s  %8s  %8s  %8s  %8s\n','N_e','Vmin_ES1','Loss_ES1','Qes_tot','VoltOK');
c15_mask = strcmp(T_out.CaseType, 'ES1-compare');
T_c15 = T_out(c15_mask, :);
for i = 1:height(T_c15)
    fprintf('  %-8d  %8.4f  %8.5f  %8.4f  %8d\n', ...
        T_c15.N_e_max(i), T_c15.Vmin_pu(i), T_c15.TotalLoss_pu(i), ...
        T_c15.TotalQes_pu(i), T_c15.VoltageFeasible(i));
end

fprintf('\n  Stage 1 basic ES reference (Vmin at matched N_e):\n');
fprintf('    N_e=8:  Vmin~0.94xx  (infeasible)\n');
fprintf('    N_e=16: Vmin~0.94xx  (infeasible)\n');
fprintf('    N_e=32: Vmin=0.9324  (infeasible)\n');
fprintf('  ES-1 adds Q_es_max=0.10 pu/device independent reactive injection.\n');

fprintf('\n=========================================================\n');
fprintf('  STAGE 6 COMPLETE\n');
fprintf('  Output: 04_results/es_framework/tables/\n');
fprintf('=========================================================\n\n');

% -------------------------------------------------------------------------
function row = make_row(name, ctype, N_e_max, r)
sol_ok  = double(isfield(r,'solver_ok') && r.solver_ok);
volt_ok = double(isfield(r,'voltage_ok') && r.voltage_ok);
ne  = getrf(r,'n_es',      NaN);
Vm  = getrf(r,'Vmin_24h',  NaN);
wb  = getrf(r,'worst_bus', NaN);
wh  = getrf(r,'worst_hour',NaN);
Lo  = getrf(r,'total_loss',NaN);
Qe  = getrf(r,'total_Qes', NaN);
Mc  = getrf(r,'mean_curt', NaN);
ts  = getrf(r,'solve_time',NaN);
row = {name, ctype, N_e_max, ne, sol_ok, volt_ok, Vm, wb, wh, Lo, Qe, Mc, ts};
end

function v = getrf(s, f, default)
if isfield(s,f)
    raw = s.(f);
    if isnumeric(raw) && ~isempty(raw) && ~isnan(raw(1))
        v = raw(1);
    else, v = default; end
else, v = default; end
end

function s = fmtval(v, fmt)
if isnan(v), s = '---'; else, s = sprintf(fmt, v); end
end
