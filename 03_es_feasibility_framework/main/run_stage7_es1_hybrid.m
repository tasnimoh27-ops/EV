%% run_stage7_es1_hybrid.m
% STAGE 7 — ES-1 Substitution Curves vs STATCOM and ESS
%
% Mirrors Stage 4 exactly, but replaces basic ES with ES-1 (Hou reactive model).
% ES-1 adds Q_es_max=0.10 pu/device independent reactive injection.
%
% For each N_e budget in {0,4,8,...,32}, finds:
%   N_s_min(N_e) — minimum STATCOMs for V >= 0.95 with ES-1
%   N_b_min(N_e) — minimum ESS units for V >= 0.95 with ES-1
%
% Stage 4 baselines (basic ES):
%   N_e=0:  N_s_min=7, N_b_min=3
%   N_e=32: N_s_min=2, N_b_min=1
%
% Stage 6 result: ES-1 alone feasible at N_e=4.
% Stage 7 hypothesis: ES-1 reactive injection lowers the N_s/N_b floors
% seen in Stage 4 (STATCOM floor=2 at N_e>=12, ESS floor=1 at N_e>=16).
%
% Output:
%   04_results/es_framework/tables/table_stage7_es1_substitution.csv
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
fprintf('  STAGE 7 — ES-1 SUBSTITUTION CURVES\n');
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

%% SWEEP PARAMETERS
N_e_grid  = [0, 4, 8, 12, 16, 20, 24, 28, 32];
N_s_upper = 8;   % Stage 4 N_e=0 needs N_s=7 with basic ES; ES-1 Q_es may lower this
N_b_upper = 4;   % Stage 4 N_e=0 needs N_b=3 with basic ES

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
p_base.time_limit    = 120;
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

% Stage 4 reference results for comparison
stage4_Ns = [7, 5, 3, 2, 2, 2, 2, 2, 2];
stage4_Nb = [3, 2, 2, 2, 1, 1, 1, 1, 1];

%% MAIN SWEEP
fprintf('%-6s | %-14s %-10s %-10s | %-14s %-10s %-10s | %-8s %-8s\n', ...
    'N_e', 'ES1+STATCOM', 'Vmin', 'Loss', 'ES1+ESS', 'Vmin', 'Loss', 'S4_Ns', 'S4_Nb');
fprintf('%s\n', repmat('-',1,90));

rows = {};

for idx = 1:numel(N_e_grid)
    N_e = N_e_grid(idx);
    fprintf('\n=== N_e = %d (Stage4 ref: N_s=%d, N_b=%d) ===\n', ...
        N_e, stage4_Ns(idx), stage4_Nb(idx));

    % ------------------------------------------------------------------
    %  A) ES-1 + STATCOM: find minimum N_s
    % ------------------------------------------------------------------
    N_s_min = NaN;
    r_s_best = [];
    for N_s = 0:N_s_upper
        p = p_base;
        p.rho                = rho;
        p.u_min              = u_min;
        p.N_e_max            = N_e;
        p.N_s_max            = N_s;
        p.candidate_buses_es = all_non_slack;
        p.candidate_buses_s  = react_cand;

        fprintf('  ES1+S | N_e=%2d N_s=%d ... ', N_e, N_s);
        r = solve_es1_statcom_misocp(topo, loads, p);
        fprintf('\n');

        if r.voltage_ok
            N_s_min  = N_s;
            r_s_best = r;
            break
        end
    end

    % ------------------------------------------------------------------
    %  B) ES-1 + ESS: find minimum N_b
    % ------------------------------------------------------------------
    N_b_min = NaN;
    r_b_best = [];
    for N_b = 0:N_b_upper
        p = p_base;
        p.rho                = rho;
        p.u_min              = u_min;
        p.N_e_max            = N_e;
        p.N_b_max            = N_b;
        p.candidate_buses_es = all_non_slack;
        p.candidate_buses_b  = react_cand;

        fprintf('  ES1+B | N_e=%2d N_b=%d ... ', N_e, N_b);
        r = solve_es1_ess_misocp(topo, loads, p);
        fprintf('\n');

        if r.voltage_ok
            N_b_min  = N_b;
            r_b_best = r;
            break
        end
    end

    % ------------------------------------------------------------------
    %  Record row
    % ------------------------------------------------------------------
    Vm_s = NaN; Lo_s = NaN; Ne_s = NaN; Qes_s = NaN;
    if ~isempty(r_s_best) && r_s_best.solver_ok
        Vm_s  = r_s_best.Vmin_24h;
        Lo_s  = r_s_best.total_loss;
        Ne_s  = r_s_best.n_es;
        Qes_s = r_s_best.total_Qes;
    end
    Vm_b = NaN; Lo_b = NaN; Ne_b = NaN; Qes_b = NaN;
    if ~isempty(r_b_best) && r_b_best.solver_ok
        Vm_b  = r_b_best.Vmin_24h;
        Lo_b  = r_b_best.total_loss;
        Ne_b  = r_b_best.n_es;
        Qes_b = r_b_best.total_Qes;
    end

    rows{end+1} = {N_e, ...
        N_s_min, Ne_s, Qes_s, Vm_s, Lo_s, stage4_Ns(idx), ...
        N_b_min, Ne_b, Qes_b, Vm_b, Lo_b, stage4_Nb(idx)};

    fprintf('%-6d | N_s_min=%-4s Vmin=%-7s Loss=%-7s | N_b_min=%-4s Vmin=%-7s Loss=%-7s | %-8d %-8d\n', ...
        N_e, ...
        fmtval(N_s_min,'%d'), fmtval(Vm_s,'%.4f'), fmtval(Lo_s,'%.5f'), ...
        fmtval(N_b_min,'%d'), fmtval(Vm_b,'%.4f'), fmtval(Lo_b,'%.5f'), ...
        stage4_Ns(idx), stage4_Nb(idx));
end

%% BUILD TABLE
col_names = {'N_e_budget', ...
    'N_s_min','N_e_used_S','Qes_S','Vmin_S','Loss_S','Stage4_Ns', ...
    'N_b_min','N_e_used_B','Qes_B','Vmin_B','Loss_B','Stage4_Nb'};

T_out = cell2table(vertcat(rows{:}), 'VariableNames', col_names);
fname = fullfile(out_tabs, 'table_stage7_es1_substitution.csv');
writetable(T_out, fname);
fprintf('\n  Saved: %s\n', fname);

%% PRINT SUMMARY WITH STAGE 4 COMPARISON
fprintf('\n');
fprintf('=========================================================\n');
fprintf('  STAGE 7 — ES-1 SUBSTITUTION CURVES vs STAGE 4\n');
fprintf('=========================================================\n');
fprintf('  %5s | %8s %8s %8s | %8s %8s %8s\n', ...
    'N_e', 'Ns(ES1)', 'Ns(S4)', 'DeltaNs', 'Nb(ES1)', 'Nb(S4)', 'DeltaNb');
fprintf('  %s\n', repmat('-',1,65));
for i = 1:height(T_out)
    dns = T_out.Stage4_Ns(i) - T_out.N_s_min(i);
    dnb = T_out.Stage4_Nb(i) - T_out.N_b_min(i);
    fprintf('  %5d | %8s %8d %8s | %8s %8d %8s\n', ...
        T_out.N_e_budget(i), ...
        fmtval(T_out.N_s_min(i),'%d'), T_out.Stage4_Ns(i), fmtval(dns,'%+d'), ...
        fmtval(T_out.N_b_min(i),'%d'), T_out.Stage4_Nb(i), fmtval(dnb,'%+d'));
end
fprintf('  %s\n', repmat('-',1,65));

% Substitution rate summary
valid_s = ~isnan(T_out.N_s_min);
valid_b = ~isnan(T_out.N_b_min);
if sum(valid_s) >= 2
    dNe = T_out.N_e_budget(end) - T_out.N_e_budget(1);
    dNs = T_out.N_s_min(find(valid_s,1,'first')) - T_out.N_s_min(find(valid_s,1,'last'));
    fprintf('  ES-1+STATCOM substitution: %d ES-1 replaces %d STATCOM (%.2f ES/STATCOM)\n', ...
        dNe, dNs, dNe/max(dNs,1));
end
if sum(valid_b) >= 2
    dNe = T_out.N_e_budget(end) - T_out.N_e_budget(1);
    dNb = T_out.N_b_min(find(valid_b,1,'first')) - T_out.N_b_min(find(valid_b,1,'last'));
    fprintf('  ES-1+ESS substitution:     %d ES-1 replaces %d ESS (%.2f ES/ESS)\n', ...
        dNe, dNb, dNe/max(dNb,1));
end
fprintf('\n  Stage 4 reference (basic ES):\n');
fprintf('    STATCOM substitution: 32 ES replaces 5 STATCOM (6.40 ES/STATCOM)\n');
fprintf('    ESS substitution:     32 ES replaces 2 ESS   (16.00 ES/ESS)\n');
fprintf('=========================================================\n');
fprintf('  STAGE 7 COMPLETE\n');
fprintf('  Output: 04_results/es_framework/tables/\n');
fprintf('=========================================================\n\n');

% -------------------------------------------------------------------------
function s = fmtval(v, fmt)
if isnan(v), s = '---'; else, s = sprintf(fmt, v); end
end
