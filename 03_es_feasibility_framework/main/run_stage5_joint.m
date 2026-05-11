%% run_stage5_joint.m
% STAGE 5 — Joint ES + STATCOM + ESS: Minimum Reactive/Storage Device Count
%
% Research question: can joint deployment of all three resource types achieve
% voltage feasibility with fewer total reactive+storage devices than the
% best single-resource-pair approach (Stages 2-4)?
%
% Stage 4 baselines (N_r = N_s + N_b):
%   N_e=0:  N_s_min=7, N_b_min=3 -> best separate N_r=3
%   N_e=8:  N_s_min=3, N_b_min=2 -> best separate N_r=2
%   N_e=16: N_s_min=2, N_b_min=1 -> best separate N_r=1
%   N_e=32: N_s_min=2, N_b_min=1 -> best separate N_r=1
%
% Stage 5 sweeps (N_s, N_b) pairs by total budget N_r=N_s+N_b, for each N_e,
% to find minimum N_r achievable with joint resource allocation.
%
% Key: ESS provides P time-shifting + Q injection; STATCOM provides additional
% Q at reactive-limited hours. Joint allocation may beat either path alone.
%
% Output:
%   04_results/es_framework/tables/table_stage5_joint_sweep.csv
%   04_results/es_framework/tables/table_stage5_summary.csv
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
fprintf('  STAGE 5 — JOINT ES + STATCOM + ESS\n');
fprintf('  IEEE 33-Bus | rho=0.70 | u_min=0.20 | scale=1.80\n');
fprintf('=========================================================\n\n');

%% LOAD NETWORK
fprintf('Loading network...\n');
[topo, loads] = build_ieee33_network(repo_root, 1.80);

rho   = 0.70;
u_min = 0.20;
T     = 24;
price = ones(T,1);
price(1:6)=0.6; price(7:16)=1.0; price(17:21)=1.8; price(22:24)=0.9;

%% VSI CANDIDATE RESTRICTION (consistent with Stages 2-4)
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
p_base.time_limit    = 180;    % slightly longer: 3 resources, harder BnB
p_base.MIPGap        = 0.05;
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
% Stage 4 baselines: [N_e, N_s_min(stage4), N_b_min(stage4)]
% For joint sweep: test N_e points where Stage 4 had N_r >= 2
% (N_e=16,32 already achieve N_b_min=1; joint cannot improve further)
N_e_grid = [0, 8, 16, 32];

% Stage 4 reference N_r_min = min(N_s_min, N_b_min) for each N_e
stage4_Ns = [7, 3, 2, 2];   % N_s_min at N_e = 0, 8, 16, 32
stage4_Nb = [3, 2, 1, 1];   % N_b_min at N_e = 0, 8, 16, 32
stage4_Nr = min(stage4_Ns, stage4_Nb);  % best separate N_r

% For each N_e, sweep (N_s, N_b) pairs from N_total=0 upward
N_r_upper = 5;   % max N_r to try

fprintf('Stage 4 baselines (min reactive+storage devices):\n');
fprintf('  N_e=%2d: N_s_min=%d  N_b_min=%d  best_Nr=%d\n', ...
    [N_e_grid; stage4_Ns; stage4_Nb; stage4_Nr]);
fprintf('\n');

%% MAIN SWEEP
fprintf('%-6s | %-6s %-6s | %-7s %-7s %-7s | %-8s %-8s\n', ...
    'N_e', 'N_s', 'N_b', 'VoltOK', 'Vmin', 'Loss', 'Stage4_Nr', 'Joint_Nr');
fprintf('%s\n', repmat('-',1,72));

rows = {};
summary_rows = {};

for idx = 1:numel(N_e_grid)
    N_e = N_e_grid(idx);
    Nr_ref = stage4_Nr(idx);
    fprintf('\n=== N_e = %d (Stage 4 best N_r = %d) ===\n', N_e, Nr_ref);

    joint_Nr_min = NaN;
    r_best = [];
    N_s_best = NaN;
    N_b_best = NaN;

    found = false;
    for N_total = 0:N_r_upper
        if found, break; end

        % Try all (N_s, N_b) splits for this total — ESS-heavy first
        % (ESS provides both P and Q; try more ESS before STATCOM)
        for N_b = min(N_total, stage4_Nb(idx)) : -1 : 0
            N_s = N_total - N_b;
            if N_s > stage4_Ns(idx), continue; end  % beyond Stage 4 max

            p = p_base;
            p.N_e_max = N_e;
            p.N_s_max = N_s;
            p.N_b_max = N_b;

            fprintf('  N_e=%2d N_s=%d N_b=%d ... ', N_e, N_s, N_b);
            r = solve_es_statcom_ess_misocp(topo, loads, p);

            rows{end+1} = make_row(N_e, N_s, N_b, Nr_ref, r);

            if r.voltage_ok
                joint_Nr_min = N_total;
                r_best  = r;
                N_s_best = r.n_statcom;
                N_b_best = r.n_ess;
                found = true;
                break;
            end
        end
    end

    % Report
    if ~isnan(joint_Nr_min)
        saving = Nr_ref - joint_Nr_min;
        fprintf('\n  >>> Joint feasible at N_r=%d (N_s=%d, N_b=%d) | Stage4 needed N_r=%d | Saving=%d\n', ...
            joint_Nr_min, N_s_best, N_b_best, Nr_ref, saving);
    else
        fprintf('\n  >>> Joint not feasible within N_r=0..%d\n', N_r_upper);
    end

    Vm = NaN; Lo = NaN;
    if ~isempty(r_best) && r_best.solver_ok
        Vm = r_best.Vmin_24h;
        Lo = r_best.total_loss;
    end
    summary_rows{end+1} = {N_e, Nr_ref, joint_Nr_min, N_s_best, N_b_best, ...
        Vm, Lo, Nr_ref - joint_Nr_min};

    fprintf('%-6d | %-6s %-6s | %-7s %-7s %-7s | %-8d %-8s\n', ...
        N_e, fmtval(N_s_best,'%d'), fmtval(N_b_best,'%d'), ...
        fmtval(double(~isnan(joint_Nr_min)),'%d'), ...
        fmtval(Vm,'%.4f'), fmtval(Lo,'%.5f'), ...
        Nr_ref, fmtval(joint_Nr_min,'%d'));
end

%% BUILD SWEEP TABLE
col_sweep = {'N_e', 'N_s_max', 'N_b_max', 'Stage4_Nr_ref', ...
    'N_e_used','N_s_used','N_b_used', ...
    'SolverOK','VoltageFeasible', ...
    'Vmin_pu','WorstBus','WorstHour', ...
    'TotalLoss_pu','TotalQs_pu','TotalQb_pu','MeanCurt','SolveTime_s'};

T_sweep = cell2table(vertcat(rows{:}), 'VariableNames', col_sweep);
fname_sweep = fullfile(out_tabs, 'table_stage5_joint_sweep.csv');
writetable(T_sweep, fname_sweep);
fprintf('\n  Saved sweep: %s\n', fname_sweep);

%% BUILD SUMMARY TABLE
col_sum = {'N_e', 'Stage4_Nr_min', 'Joint_Nr_min', 'Joint_Ns', 'Joint_Nb', ...
    'Vmin_pu', 'Loss_pu', 'Nr_Saving'};
T_sum = cell2table(vertcat(summary_rows{:}), 'VariableNames', col_sum);
fname_sum = fullfile(out_tabs, 'table_stage5_summary.csv');
writetable(T_sum, fname_sum);
fprintf('  Saved summary: %s\n', fname_sum);

%% PRINT SUMMARY
fprintf('\n');
fprintf('=========================================================\n');
fprintf('  STAGE 5 — JOINT RESOURCE ALLOCATION SUMMARY\n');
fprintf('=========================================================\n');
fprintf('  %-6s | %-12s %-12s %-8s %-8s | %-8s %-8s\n', ...
    'N_e', 'Stage4_Nr', 'Joint_Nr', 'N_s', 'N_b', 'Vmin', 'Loss');
fprintf('  %s\n', repmat('-',1,68));
for i = 1:height(T_sum)
    fprintf('  %-6d | %-12s %-12s %-8s %-8s | %-8s %-8s\n', ...
        T_sum.N_e(i), ...
        fmtval(T_sum.Stage4_Nr_min(i),'%d'), ...
        fmtval(T_sum.Joint_Nr_min(i),'%d'), ...
        fmtval(T_sum.Joint_Ns(i),'%d'), ...
        fmtval(T_sum.Joint_Nb(i),'%d'), ...
        fmtval(T_sum.Vmin_pu(i),'%.4f'), ...
        fmtval(T_sum.Loss_pu(i),'%.5f'));
end
fprintf('  %s\n', repmat('-',1,68));

valid = ~isnan(T_sum.Nr_Saving);
if any(valid)
    total_saving = sum(T_sum.Nr_Saving(valid));
    fprintf('  Total N_r savings vs Stage 4 best: %d device(s) across %d N_e points\n', ...
        total_saving, sum(valid));
end
fprintf('=========================================================\n');
fprintf('  STAGE 5 COMPLETE\n');
fprintf('  Output: 04_results/es_framework/tables/\n');
fprintf('=========================================================\n\n');

% -------------------------------------------------------------------------
function row = make_row(N_e, N_s_max, N_b_max, Nr_ref, r)
sol_ok  = double(isfield(r,'solver_ok') && r.solver_ok);
volt_ok = double(isfield(r,'voltage_ok') && r.voltage_ok);
ne  = getrf(r,'n_es',      NaN);
ns  = getrf(r,'n_statcom', NaN);
nb_ = getrf(r,'n_ess',     NaN);
Vm  = getrf(r,'Vmin_24h',  NaN);
wb  = getrf(r,'worst_bus', NaN);
wh  = getrf(r,'worst_hour',NaN);
Lo  = getrf(r,'total_loss',NaN);
Qs  = getrf(r,'total_Qs',  NaN);
Qb  = getrf(r,'total_Qb',  NaN);
Mc  = getrf(r,'mean_curt', NaN);
ts  = getrf(r,'solve_time',NaN);
row = {N_e, N_s_max, N_b_max, Nr_ref, ne, ns, nb_, sol_ok, volt_ok, ...
       Vm, wb, wh, Lo, Qs, Qb, Mc, ts};
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
