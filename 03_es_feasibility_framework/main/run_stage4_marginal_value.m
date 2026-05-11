%% run_stage4_marginal_value.m
% STAGE 4 — ES Marginal Value: Substitution Curves
%
% For each ES budget N_e in {0,4,8,...,32}, finds:
%   N_s_min(N_e) — minimum STATCOMs for V >= 0.95
%   N_b_min(N_e) — minimum ESS units for V >= 0.95
%
% Results form two Pareto substitution curves showing how ES reduces
% the required reactive/storage device count. Core publication figure.
%
% No new solvers — reuses solve_es_statcom_misocp and solve_es_ess_misocp.
%
% Known endpoints (from Stages 2-3, reconfirmed here):
%   N_e=0:  N_s_min=7, N_b_min=3
%   N_e=32: N_s_min=2, N_b_min=1
%
% Output:
%   04_results/es_framework/tables/table_stage4_substitution.csv
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
fprintf('  STAGE 4 — ES MARGINAL VALUE: SUBSTITUTION CURVES\n');
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

%% VSI CANDIDATE RESTRICTION (consistent with Stages 2-3)
K_cand = 15;
vsi = calculate_voltage_impact_score(topo, loads, rho);
react_cand = sort(vsi.rank(1:K_cand)');
react_cand = react_cand(react_cand ~= topo.root);
all_non_slack = setdiff(1:topo.nb, topo.root)';
fprintf('  Reactive/storage candidates (top-%d VSI): %s\n\n', K_cand, mat2str(react_cand));

%% SWEEP PARAMETERS
N_e_grid  = [0, 4, 8, 12, 16, 20, 24, 28, 32];
N_s_upper = 8;   % Stage 2: N_e=0 needs N_s=7; sweep 0..8 to confirm
N_b_upper = 4;   % Stage 3: N_e=0 needs N_b=3; sweep 0..4 to confirm

%% BASE PARAMS (hard voltage, VSI restriction, fast solver settings)
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
p_base.Qs_max_pu     = 0.10;
% ESS capacity (consistent with Stage 3)
p_base.E_cap_pu      = 1.0;
p_base.P_ch_max_pu   = 0.5;
p_base.P_dis_max_pu  = 0.5;
p_base.Q_b_max_pu    = 0.10;
p_base.eta_ch        = 0.95;
p_base.eta_dis       = 0.95;
p_base.SOC_init      = 0.50;
p_base.SOC_min       = 0.10;

%% MAIN SWEEP
fprintf('%-6s | %-12s %-10s %-10s | %-12s %-10s %-10s\n', ...
    'N_e', 'STATCOM', 'Vmin', 'Loss', 'ESS', 'Vmin', 'Loss');
fprintf('%s\n', repmat('-',1,72));

rows = {};

for idx = 1:numel(N_e_grid)
    N_e = N_e_grid(idx);
    fprintf('\n=== N_e = %d ===\n', N_e);

    % ------------------------------------------------------------------
    %  A) ES + STATCOM: find minimum N_s
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

        fprintf('  STATCOM | N_e=%2d N_s=%d ... ', N_e, N_s);
        r = solve_es_statcom_misocp(topo, loads, p);
        fprintf('\n');

        if r.voltage_ok
            N_s_min  = N_s;
            r_s_best = r;
            break
        end
    end

    % ------------------------------------------------------------------
    %  B) ES + ESS: find minimum N_b
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

        fprintf('  ESS     | N_e=%2d N_b=%d ... ', N_e, N_b);
        r = solve_es_ess_misocp(topo, loads, p);
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
    Vm_s = NaN; Lo_s = NaN; Ne_s = NaN;
    if ~isempty(r_s_best) && r_s_best.solver_ok
        Vm_s = r_s_best.Vmin_24h;
        Lo_s = r_s_best.total_loss;
        Ne_s = r_s_best.n_es;
    end
    Vm_b = NaN; Lo_b = NaN; Ne_b = NaN;
    if ~isempty(r_b_best) && r_b_best.solver_ok
        Vm_b = r_b_best.Vmin_24h;
        Lo_b = r_b_best.total_loss;
        Ne_b = r_b_best.n_es;
    end

    rows{end+1} = {N_e, N_s_min, Ne_s, Vm_s, Lo_s, ...
                        N_b_min, Ne_b, Vm_b, Lo_b};

    fprintf('%-6d | N_s_min=%-4s Vmin=%-7s Loss=%-7s | N_b_min=%-4s Vmin=%-7s Loss=%-7s\n', ...
        N_e, ...
        fmtval(N_s_min,'%d'), fmtval(Vm_s,'%.4f'), fmtval(Lo_s,'%.5f'), ...
        fmtval(N_b_min,'%d'), fmtval(Vm_b,'%.4f'), fmtval(Lo_b,'%.5f'));
end

%% BUILD TABLE
col_names = {'N_e_budget', ...
    'N_s_min','N_e_used_STATCOM','Vmin_STATCOM','Loss_STATCOM', ...
    'N_b_min','N_e_used_ESS',    'Vmin_ESS',    'Loss_ESS'};

T_out = cell2table(vertcat(rows{:}), 'VariableNames', col_names);
fname = fullfile(out_tabs, 'table_stage4_substitution.csv');
writetable(T_out, fname);
fprintf('\n  Saved: %s\n', fname);

%% PRINT SUBSTITUTION SUMMARY
fprintf('\n');
fprintf('=========================================================\n');
fprintf('  STAGE 4 — SUBSTITUTION CURVES\n');
fprintf('=========================================================\n');
fprintf('  %5s | %8s %8s | %8s %8s\n', 'N_e', 'N_s_min', 'Loss_S', 'N_b_min', 'Loss_B');
fprintf('  %s\n', repmat('-',1,50));
for i = 1:height(T_out)
    fprintf('  %5d | %8s %8s | %8s %8s\n', ...
        T_out.N_e_budget(i), ...
        fmtval(T_out.N_s_min(i),'%d'), ...
        fmtval(T_out.Loss_STATCOM(i),'%.5f'), ...
        fmtval(T_out.N_b_min(i),'%d'), ...
        fmtval(T_out.Loss_ESS(i),'%.5f'));
end
fprintf('  %s\n', repmat('-',1,50));

% Substitution rate summary
valid_s = ~isnan(T_out.N_s_min);
valid_b = ~isnan(T_out.N_b_min);
if sum(valid_s) >= 2
    dNe = T_out.N_e_budget(end) - T_out.N_e_budget(1);
    dNs = T_out.N_s_min(find(valid_s,1,'first')) - T_out.N_s_min(find(valid_s,1,'last'));
    fprintf('  STATCOM substitution: %d ES replaces %d STATCOM (%.2f ES/STATCOM)\n', ...
        dNe, dNs, dNe/max(dNs,1));
end
if sum(valid_b) >= 2
    dNe = T_out.N_e_budget(end) - T_out.N_e_budget(1);
    dNb = T_out.N_b_min(find(valid_b,1,'first')) - T_out.N_b_min(find(valid_b,1,'last'));
    fprintf('  ESS substitution:     %d ES replaces %d ESS (%.2f ES/ESS)\n', ...
        dNe, dNb, dNe/max(dNb,1));
end
fprintf('=========================================================\n');
fprintf('  STAGE 4 COMPLETE\n');
fprintf('  Output: 04_results/es_framework/tables/\n');
fprintf('=========================================================\n\n');

% -------------------------------------------------------------------------
function s = fmtval(v, fmt)
if isnan(v), s = '---'; else, s = sprintf(fmt, v); end
end
