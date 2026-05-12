%% run_stage8_es1_joint.m
% STAGE 8 — ES-1 Joint: Minimum Reactive/Storage Device Count with ES-1
%
% Mirrors Stage 5 (basic ES joint), replacing basic ES with ES-1 (Hou model).
% ES-1 adds independent reactive injection Q_es per device, which reduces
% the supplemental reactive/storage hardware needed alongside ES-1.
%
% Research questions:
%   1. How does ES-1's reactive capability change the joint N_r = N_s + N_b
%      minimum compared to Stage 5 (basic ES joint)?
%   2. What is the minimum (N_e, N_r) combination that achieves feasibility?
%   3. How many fewer STATCOMs/ESSs does ES-1 need at the crossover point?
%
% Sweep:
%   N_e in {0, 1, 2, 3, 4, 8, 16, 32}
%   - {1,2,3}: sub-threshold transition region (not covered by Stage 5 or 7)
%   - {0,4,8,16,32}: comparison points matching Stage 5 / Stage 7
%
% Stage 7 reference (ES-1 separate):
%   N_e=0: N_s_min=7, N_b_min=3 -> best Nr=3
%   N_e>=4: N_s_min=0, N_b_min=0 -> Nr=0 (ES-1 alone feasible)
%
% Stage 5 reference (basic ES joint, from table_stage5_summary.csv):
%   N_e=0:  Joint Nr=3
%   N_e=8:  Joint Nr=2
%   N_e=16: Joint Nr=1
%   N_e=32: Joint Nr=1
%
% Output:
%   04_results/es_framework/tables/table_stage8_es1_joint_sweep.csv
%   04_results/es_framework/tables/table_stage8_es1_joint_summary.csv
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
fprintf('  STAGE 8 — ES-1 JOINT: MIN REACTIVE/STORAGE DEVICES\n');
fprintf('  IEEE 33-Bus | rho=0.70 | u_min=0.20 | scale=1.80\n');
fprintf('  Q_es_max=0.10 pu/device (Hou ES-1 reactive model)\n');
fprintf('=========================================================\n\n');

%% LOAD NETWORK
fprintf('Loading network...\n');
[topo, loads] = build_ieee33_network(repo_root, 1.80);

rho   = 0.70;
u_min = 0.20;
T     = 24;
price = ones(T,1);
price(1:6)=0.6; price(7:16)=1.0; price(17:21)=1.8; price(22:24)=0.9;

%% VSI CANDIDATE RESTRICTION (consistent with Stages 2-7)
K_cand = 15;
vsi = calculate_voltage_impact_score(topo, loads, rho);
react_cand = sort(vsi.rank(1:K_cand)');
react_cand = react_cand(react_cand ~= topo.root);
all_non_slack = setdiff(1:topo.nb, topo.root)';
fprintf('  Reactive/storage candidates (top-%d VSI): %s\n\n', K_cand, mat2str(react_cand));

%% BASE PARAMS
p_base.Vmin          = 0.95;
p_base.Vmax          = 1.05;
p_base.soft_voltage  = false;
p_base.obj_mode      = 'planning';
p_base.w_loss        = 1.0;
p_base.w_e           = 0.0;
p_base.w_s           = 0.0;
p_base.w_b           = 0.0;
p_base.w_curt        = 0.0;
p_base.w_vio         = 0.0;
p_base.price         = price;
p_base.time_limit    = 240;
p_base.MIPGap        = 0.05;
p_base.Q_es_max_pu   = 0.10;
p_base.Qs_max_pu     = 0.10;
p_base.E_cap_pu      = 1.0;
p_base.P_ch_max_pu   = 0.5;
p_base.P_dis_max_pu  = 0.5;
p_base.Q_b_max_pu    = 0.10;
p_base.eta_ch        = 0.95;
p_base.eta_dis       = 0.95;
p_base.SOC_init      = 0.50;
p_base.SOC_min       = 0.10;
p_base.rho           = rho;
p_base.u_min         = u_min;
p_base.candidate_buses_es = all_non_slack;
p_base.candidate_buses_s  = react_cand;
p_base.candidate_buses_b  = react_cand;

%% SWEEP DEFINITION
% N_e grid: sub-threshold {1,2,3} + standard comparison points
N_e_grid = [0, 1, 2, 3, 4, 8, 16, 32];

% Stage 7 reference: N_s_min and N_b_min at matched N_e
% N_e=0: Stage 7 ran (N_s=7, N_b=3)
% N_e=1,2,3: Stage 7 did not run (new territory)
% N_e>=4: Stage 7 feasible with 0 supplemental (N_r=0)
stage7_Ns = [7,  NaN, NaN, NaN, 0, 0, 0, 0];
stage7_Nb = [3,  NaN, NaN, NaN, 0, 0, 0, 0];

% Stage 5 reference (basic ES joint): available at N_e={0,8,16,32}
% Load from CSV if it exists, else use hardcoded fallback
stage5_Nr_ref = containers.Map([0,8,16,32],[3,2,1,1]);

% Max N_r to try (won't exceed Stage 7 baseline of 3 at N_e=0)
N_r_upper = 4;

fprintf('Stage 7 reference (ES-1 separate):\n');
fprintf('  N_e= 0: N_s_min=7  N_b_min=3  best_Nr=3\n');
fprintf('  N_e>=4: ES-1 alone feasible -> Nr=0\n');
fprintf('\nStage 5 reference (basic ES joint):\n');
fprintf('  N_e= 0: Joint Nr=3\n');
fprintf('  N_e= 8: Joint Nr=2\n');
fprintf('  N_e=16: Joint Nr=1\n');
fprintf('  N_e=32: Joint Nr=1\n\n');

%% MAIN SWEEP
fprintf('%-6s | %-6s %-6s %-8s | %-8s %-7s %-7s | %-8s %-8s\n', ...
    'N_e', 'N_s', 'N_b', 'Joint_Nr', 'S7_Nr', 'Vmin', 'Loss', 'S5_Nr', 'Saving_vs_S5');
fprintf('%s\n', repmat('-',1,82));

rows = {};
summary_rows = {};

for idx = 1:numel(N_e_grid)
    N_e = N_e_grid(idx);

    % Stage 7 reference Nr for this N_e
    s7_Nr = NaN;
    if ~isnan(stage7_Ns(idx)) && ~isnan(stage7_Nb(idx))
        s7_Nr = min(stage7_Ns(idx), stage7_Nb(idx));
    elseif N_e >= 4
        s7_Nr = 0;
    end

    % Stage 5 reference Nr (only available at specific N_e values)
    s5_Nr = NaN;
    if isKey(stage5_Nr_ref, N_e)
        s5_Nr = stage5_Nr_ref(N_e);
    end

    fprintf('\n=== N_e = %d (S7_Nr=%s | S5_Nr=%s) ===\n', ...
        N_e, fmtval(s7_Nr,'%d'), fmtval(s5_Nr,'%d'));

    % Short-circuit: ES-1 alone already feasible at N_e>=4
    if N_e >= 4
        fprintf('  ES-1 alone feasible (Stage 6/7 confirmed) -> Joint N_r = 0\n');
        joint_Nr_min = 0;
        N_s_best = 0;
        N_b_best = 0;
        Vm = NaN; Lo = NaN;
        saving_vs_s5 = NaN;
        if ~isnan(s5_Nr), saving_vs_s5 = s5_Nr - 0; end

        summary_rows{end+1} = {N_e, s7_Nr, joint_Nr_min, N_s_best, N_b_best, ...
            Vm, Lo, s5_Nr, saving_vs_s5};

        fprintf('%-6d | %-6s %-6s %-8s | %-8s %-7s %-7s | %-8s %-8s\n', ...
            N_e, '0', '0', '0', fmtval(s7_Nr,'%d'), '---', '---', ...
            fmtval(s5_Nr,'%d'), fmtval(saving_vs_s5,'%d'));
        continue;
    end

    % For N_e < 4: run joint ES-1 + STATCOM + ESS MISOCP
    % Upper limit on N_s, N_b: don't exceed Stage 7 standalone mins
    Ns_upper = 7;  % Stage 7 N_s_min at N_e=0 (worst case)
    Nb_upper = 3;  % Stage 7 N_b_min at N_e=0 (worst case)

    joint_Nr_min = NaN;
    r_best = [];
    N_s_best = NaN;
    N_b_best = NaN;
    found = false;

    for N_total = 0:N_r_upper
        if found, break; end

        % Try all (N_s, N_b) splits; ESS-heavy first (P time-shift + Q)
        for N_b = min(N_total, Nb_upper) : -1 : 0
            N_s = N_total - N_b;
            if N_s > Ns_upper, continue; end

            p = p_base;
            p.N_e_max = N_e;
            p.N_s_max = N_s;
            p.N_b_max = N_b;

            fprintf('  N_e=%d N_s=%d N_b=%d ... ', N_e, N_s, N_b);
            r = solve_es1_statcom_ess_misocp(topo, loads, p);

            rows{end+1} = make_row(N_e, N_s, N_b, s7_Nr, s5_Nr, r);

            if r.voltage_ok
                joint_Nr_min = N_total;
                r_best = r;
                N_s_best = r.n_statcom;
                N_b_best = r.n_ess;
                found = true;
                break;
            end
        end
    end

    % Report
    Vm = NaN; Lo = NaN;
    if ~isnan(joint_Nr_min)
        saving_vs_s7 = s7_Nr - joint_Nr_min;
        saving_vs_s5 = NaN;
        if ~isnan(s5_Nr), saving_vs_s5 = s5_Nr - joint_Nr_min; end
        if ~isempty(r_best) && r_best.solver_ok
            Vm = r_best.Vmin_24h;
            Lo = r_best.total_loss;
        end
        fprintf('\n  >>> ES-1 Joint feasible at N_r=%d (N_s=%d, N_b=%d) | S7_Nr=%s saving=%s | S5_Nr=%s saving=%s\n', ...
            joint_Nr_min, N_s_best, N_b_best, ...
            fmtval(s7_Nr,'%d'), fmtval(saving_vs_s7,'%+d'), ...
            fmtval(s5_Nr,'%d'), fmtval(saving_vs_s5,'%+d'));
    else
        saving_vs_s5 = NaN;
        fprintf('\n  >>> ES-1 Joint not feasible within N_r=0..%d\n', N_r_upper);
    end

    summary_rows{end+1} = {N_e, s7_Nr, joint_Nr_min, N_s_best, N_b_best, ...
        Vm, Lo, s5_Nr, saving_vs_s5};

    fprintf('%-6d | %-6s %-6s %-8s | %-8s %-7s %-7s | %-8s %-8s\n', ...
        N_e, fmtval(N_s_best,'%d'), fmtval(N_b_best,'%d'), ...
        fmtval(joint_Nr_min,'%d'), fmtval(s7_Nr,'%d'), ...
        fmtval(Vm,'%.4f'), fmtval(Lo,'%.5f'), ...
        fmtval(s5_Nr,'%d'), fmtval(saving_vs_s5,'%d'));
end

%% BUILD SWEEP TABLE
col_sweep = {'N_e', 'N_s_max', 'N_b_max', 'S7_Nr_ref', 'S5_Nr_ref', ...
    'N_e_used','N_s_used','N_b_used', ...
    'SolverOK','VoltageFeasible', ...
    'Vmin_pu','WorstBus','WorstHour', ...
    'TotalLoss_pu','TotalQes_pu','TotalQs_pu','TotalQb_pu','MeanCurt','SolveTime_s'};

if ~isempty(rows)
    T_sweep = cell2table(vertcat(rows{:}), 'VariableNames', col_sweep);
    fname_sweep = fullfile(out_tabs, 'table_stage8_es1_joint_sweep.csv');
    writetable(T_sweep, fname_sweep);
    fprintf('\n  Saved sweep: %s\n', fname_sweep);
else
    fprintf('\n  No sweep rows (all N_e>=4 short-circuited).\n');
end

%% BUILD SUMMARY TABLE
col_sum = {'N_e', 'S7_Nr_ref', 'ES1_Joint_Nr', 'ES1_Joint_Ns', 'ES1_Joint_Nb', ...
    'Vmin_pu', 'Loss_pu', 'S5_Nr_ref', 'Saving_vs_S5'};
T_sum = cell2table(vertcat(summary_rows{:}), 'VariableNames', col_sum);
fname_sum = fullfile(out_tabs, 'table_stage8_es1_joint_summary.csv');
writetable(T_sum, fname_sum);
fprintf('  Saved summary: %s\n', fname_sum);

%% PRINT SUMMARY
fprintf('\n');
fprintf('=========================================================\n');
fprintf('  STAGE 8 — ES-1 JOINT RESOURCE ALLOCATION SUMMARY\n');
fprintf('=========================================================\n');
fprintf('    N_e | S7_Nr  ES1_Jr  Ns   Nb | Vmin     Loss     | S5_Nr  DvS5\n');
fprintf('  %s\n', repmat('-',1,72));
for i = 1:height(T_sum)
    fprintf('  %5d | %6s  %6s  %4s %4s | %8s %8s | %6s  %4s\n', ...
        T_sum.N_e(i), ...
        fmtval(T_sum.S7_Nr_ref(i),'%d'), ...
        fmtval(T_sum.ES1_Joint_Nr(i),'%d'), ...
        fmtval(T_sum.ES1_Joint_Ns(i),'%d'), ...
        fmtval(T_sum.ES1_Joint_Nb(i),'%d'), ...
        fmtval(T_sum.Vmin_pu(i),'%.4f'), ...
        fmtval(T_sum.Loss_pu(i),'%.5f'), ...
        fmtval(T_sum.S5_Nr_ref(i),'%d'), ...
        fmtval(T_sum.Saving_vs_S5(i),'%+d'));
end
fprintf('  %s\n', repmat('-',1,72));

% Key metrics
ne0_idx = find(T_sum.N_e == 0, 1);
ne4_idx = find(T_sum.N_e == 4, 1);
if ~isempty(ne0_idx) && ~isnan(T_sum.ES1_Joint_Nr(ne0_idx))
    fprintf('  ES-1 joint at N_e=0:   N_r=%d (vs S5 N_r=%s, S7 N_r=%s)\n', ...
        T_sum.ES1_Joint_Nr(ne0_idx), ...
        fmtval(T_sum.S5_Nr_ref(ne0_idx),'%d'), ...
        fmtval(T_sum.S7_Nr_ref(ne0_idx),'%d'));
end

% Find minimum N_e with joint Nr<3
threshold_idx = find(~isnan(T_sum.ES1_Joint_Nr) & T_sum.ES1_Joint_Nr < 3, 1);
if ~isempty(threshold_idx)
    fprintf('  Min N_e for ES-1 joint Nr < 3: N_e=%d (Nr=%d)\n', ...
        T_sum.N_e(threshold_idx), T_sum.ES1_Joint_Nr(threshold_idx));
end

fprintf('=========================================================\n');
fprintf('  STAGE 8 COMPLETE\n');
fprintf('  Output: 04_results/es_framework/tables/\n');
fprintf('=========================================================\n\n');

% -------------------------------------------------------------------------
function row = make_row(N_e, N_s_max, N_b_max, s7_Nr, s5_Nr, r)
sol_ok  = double(isfield(r,'solver_ok') && r.solver_ok);
volt_ok = double(isfield(r,'voltage_ok') && r.voltage_ok);
ne  = getrf(r,'n_es',      NaN);
ns  = getrf(r,'n_statcom', NaN);
nb_ = getrf(r,'n_ess',     NaN);
Vm  = getrf(r,'Vmin_24h',  NaN);
wb  = getrf(r,'worst_bus', NaN);
wh  = getrf(r,'worst_hour',NaN);
Lo  = getrf(r,'total_loss',NaN);
Qes = getrf(r,'total_Qes', NaN);
Qs  = getrf(r,'total_Qs',  NaN);
Qb  = getrf(r,'total_Qb',  NaN);
Mc  = getrf(r,'mean_curt', NaN);
ts  = getrf(r,'solve_time',NaN);
if isnan(s7_Nr), s7_Nr_out = NaN; else, s7_Nr_out = s7_Nr; end
if isnan(s5_Nr), s5_Nr_out = NaN; else, s5_Nr_out = s5_Nr; end
row = {N_e, N_s_max, N_b_max, s7_Nr_out, s5_Nr_out, ne, ns, nb_, sol_ok, volt_ok, ...
       Vm, wb, wh, Lo, Qes, Qs, Qb, Mc, ts};
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
