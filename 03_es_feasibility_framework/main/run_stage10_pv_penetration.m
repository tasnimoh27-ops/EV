%% run_stage10_pv_penetration.m
% STAGE 10 — PV PENETRATION STUDY
%
% Research objective:
%   Investigate how PV generation at selected IEEE 33-bus locations
%   affects voltage profile, losses, and feeder feasibility. Evaluate
%   whether ES-1 reactive support can improve PV hosting capacity.
%
% PV placement (Hou tutorial):
%   Buses: [18, 22, 25, 33]
%   Peak capacities (pu): [0.06, 0.08, 0.07, 0.06] on 10 MVA base
%   Total peak: 0.27 pu = 2.7 MW
%
% PV profile (Hou-style normalized solar):
%   pv(t) = max(0, sin(π*(t - 6)/12))^1.5
%   Zero at night, peak ~noon, zero evening.
%
% PV penetration scale sweep:
%   [0 0.25 0.50 0.75 1.00 1.25 1.50 2.00]
%   Scale 0 = no PV, 1 = reference Hou, 2 = double reference
%
% Net load formulation:
%   P_net(i,t) = P_base(i,t) - pv_scale * pv_peak(i) * pv_profile(t)
%   Q_net(i,t) = Q_base(i,t)  [reactive unchanged]
%   Allow P_net < 0 (local export).
%
% Two-part analysis:
%   Part A: PV without ES-1 (baseline)
%   Part B: PV with ES-1 reactive support (5 ES budget levels)
%   Part C: Hosting capacity summary
%
% ES-1 for PV: bidirectional Q capability to handle overvoltage
%   Q_es in [-0.10, +0.10] pu/device
%   Negative Q = absorption (helps overvoltage)
%   Positive Q = injection (helps undervoltage)
%
% Requirements: MATLAB R2020a+, YALMIP, Gurobi
% Run from: repo root OR 03_es_feasibility_framework/main/

clear; clc; close all;

%% =========================================================================
%  PATHS AND SETUP
%% =========================================================================
script_dir = fileparts(mfilename('fullpath'));
new_root   = fileparts(script_dir);
repo_root  = fileparts(new_root);

addpath(genpath(fullfile(new_root, 'functions')));
addpath(genpath(fullfile(new_root, 'data')));
addpath(genpath(fullfile(new_root, 'plotting')));
addpath(genpath(fullfile(repo_root, '02_baseline_modules', 'shared')));

% Output directories
out_tabs = fullfile(repo_root, '04_results', 'es_framework', 'tables');
out_figs = fullfile(repo_root, '04_results', 'es_framework', 'figures', 'stage10');
if ~exist(out_tabs,'dir'), mkdir(out_tabs); end
if ~exist(out_figs,'dir'), mkdir(out_figs); end

fprintf('\n');
fprintf('==========================================================================\n');
fprintf('  STAGE 10 — PV PENETRATION STUDY\n');
fprintf('  IEEE 33-Bus | EV Scale=1.80 | rho=0.70 | u_min=0.20\n');
fprintf('  PV at buses [18, 22, 25, 33] with peak [0.06, 0.08, 0.07, 0.06] pu\n');
fprintf('==========================================================================\n\n');

%% =========================================================================
%  NETWORK AND LOAD DATA
%% =========================================================================
fprintf('Loading IEEE 33-bus network...\n');
[topo, loads_base] = build_ieee33_network(repo_root, 1.80);
nb = topo.nb;
T = 24;

fprintf('  Network: %d buses, %d lines\n', nb, topo.nl_tree);
fprintf('  Base loads: %d buses, 24-hour profile\n\n', size(loads_base.P24, 1));

%% =========================================================================
%  PV PROFILE AND PARAMETERS
%% =========================================================================
fprintf('Building PV profile and penetration levels...\n');

% Hou-style PV profile
pv_prof = build_stage10_pv_profile();
fprintf('  PV profile: Hou-style sin(π*(t-6)/12)^1.5 normalized\n');

% PV buses and peak capacities (pu, on 10 MVA base)
pv_buses = [18, 22, 25, 33];
pv_peak_pu = [0.06, 0.08, 0.07, 0.06];
pv_total_peak = sum(pv_peak_pu);  % 0.27 pu
fprintf('  PV buses: %s\n', mat2str(pv_buses));
fprintf('  PV peak (pu): %s -> total %.4f pu (%.2f MW)\n', ...
    mat2str(pv_peak_pu), pv_total_peak, pv_total_peak*10);

% PV penetration scale sweep
pv_scale_list = [0, 0.25, 0.50, 0.75, 1.00, 1.25, 1.50, 2.00];
fprintf('  PV scale sweep: %s\n\n', mat2str(pv_scale_list));

% ES-1 budget sweep
N_es1_list = [1, 2, 3, 4, 6, 8];
fprintf('  ES-1 budget sweep: %s devices\n\n', mat2str(N_es1_list));

%% =========================================================================
%  PART A: PV WITHOUT ES-1 (BASELINE)
%% =========================================================================
fprintf('--- PART A: PV WITHOUT ES-1 (BASELINE) ---\n');

% VSI ranking for candidate restriction (for later ES-1 cases)
rho = 0.70;
vsi = calculate_voltage_impact_score(topo, loads_base, rho);
K_cand = 15;
es_cand = sort(vsi.rank(1:K_cand)');
es_cand = es_cand(es_cand ~= topo.root);
fprintf('  ES-1 candidates (VSI top-%d): %s\n\n', K_cand, mat2str(es_cand));

rows_no_es = {};

for s = 1:length(pv_scale_list)
    pv_scale = pv_scale_list(s);

    % Apply PV penetration
    loads_pv = apply_stage10_pv_penetration(loads_base, pv_buses, pv_peak_pu, ...
        pv_prof.profile_24h, pv_scale);

    % Run power flow without ES
    fprintf('  PV scale=%.2f: ', pv_scale);

    % Build params for baseline power flow (no ES)
    p_base = struct();
    p_base.Vmin = 0.95;
    p_base.Vmax = 1.05;
    p_base.soft_voltage = true;
    p_base.obj_mode = 'feasibility';
    p_base.w_loss = 1.0;
    p_base.w_ES = 0.0;
    p_base.w_curt = 0.0;
    p_base.w_vio = 0.0;
    p_base.rho = rho;
    p_base.u_min = 0.20;
    p_base.Q_es_max_pu = 0.0;  % no ES
    p_base.time_limit = 120;
    p_base.MIPGap = 0.05;
    p_base.N_ES_max = 0;  % no ES
    p_base.candidate_buses = [];

    % Use original load data (not PV-adjusted) for baseflow
    % Actually, we want to solve with PV as net load:
    loads_pv_solve = loads_pv;
    loads_pv_solve.P24 = loads_pv.P24_net;
    loads_pv_solve.Q24 = loads_pv.Q24_net;

    r = solve_es1_pv_misocp(topo, loads_pv_solve, p_base);

    % Extract metrics
    case_name = sprintf('A_PV_Scale_%.2f', pv_scale);
    row = summarize_stage10_pv_metrics(case_name, 'PV_no_ES', pv_scale, loads_pv, r);
    rows_no_es{end+1} = row;

    fprintf('Vmin=%.4f, Vmax=%.4f, Loss=%.5f, ReverseFlow=%d, FeasVolt=%d\n', ...
        r.Vmin_24h, r.Vmax_24h, r.total_loss, r.reverse_flow_count, r.voltage_ok);
end

fprintf('\n');

%% =========================================================================
%  PART B: PV WITH ES-1 (REACTIVE SUPPORT)
%% =========================================================================
fprintf('--- PART B: PV WITH ES-1 REACTIVE SUPPORT ---\n');

rows_with_es = {};

for s = 1:length(pv_scale_list)
    pv_scale = pv_scale_list(s);

    % Apply PV penetration
    loads_pv = apply_stage10_pv_penetration(loads_base, pv_buses, pv_peak_pu, ...
        pv_prof.profile_24h, pv_scale);

    loads_pv_solve = loads_pv;
    loads_pv_solve.P24 = loads_pv.P24_net;
    loads_pv_solve.Q24 = loads_pv.Q24_net;

    fprintf('  PV scale=%.2f\n', pv_scale);

    % Sweep ES budgets
    for b = 1:length(N_es1_list)
        N_es = N_es1_list(b);

        % ES-1 params with bidirectional Q
        p_es = struct();
        p_es.Vmin = 0.95;
        p_es.Vmax = 1.05;
        p_es.soft_voltage = true;
        p_es.obj_mode = 'feasibility';
        p_es.w_loss = 1.0;
        p_es.w_ES = 0.0;
        p_es.w_curt = 0.0;
        p_es.w_vio = 0.0;
        p_es.rho = rho;
        p_es.u_min = 0.20;
        p_es.Q_es_inj_max_pu = 0.10;   % injection
        p_es.Q_es_abs_max_pu = 0.10;   % absorption
        p_es.N_ES_max = N_es;
        p_es.candidate_buses = es_cand;
        p_es.time_limit = 120;
        p_es.MIPGap = 0.05;
        p_es.disable_curtailment = true;  % disable curtailment for PV studies

        fprintf('    N_ES=%d: ', N_es);

        % Solve with PV-aware ES-1 solver
        r = solve_es1_pv_misocp(topo, loads_pv_solve, p_es);

        % Extract metrics
        case_name = sprintf('B_PV_Scale_%.2f_NES_%d', pv_scale, N_es);
        row = summarize_stage10_pv_metrics(case_name, 'PV_with_ES1', pv_scale, loads_pv, r);
        rows_with_es{end+1} = row;

        fprintf('\n');
    end
end

fprintf('\n');

%% =========================================================================
%  BUILD OUTPUT TABLES
%% =========================================================================
fprintf('--- BUILDING OUTPUT TABLES ---\n');

% Table 1: No-ES baseline
col_names = {
    'CaseName', 'CaseType', 'pv_scale', 'total_pv_peak_pu', 'total_pv_peak_mw', ...
    'Vmin_24h', 'Vmax_24h', 'worst_low_bus', 'worst_low_hour', ...
    'worst_high_bus', 'worst_high_hour', 'TotalLoss_pu', ...
    'UndervoltageCount', 'OvervoltageCount', 'ReverseFlowCount', 'MaxReversePower', ...
    'VoltageFeasible', 'N_ES_max', 'N_ES_used', 'ES_Buses_str', ...
    'TotalQes_inj_pu', 'TotalQes_abs_pu', 'SolveTime_s', 'SolverOK'
};

T_no_es = cell2table(vertcat(rows_no_es{:}), 'VariableNames', col_names);
fname_no_es = fullfile(out_tabs, 'table_stage10_pv_no_es.csv');
writetable(T_no_es, fname_no_es);
fprintf('  Saved: %s (%d rows)\n', fname_no_es, height(T_no_es));

% Table 2: With-ES results
T_with_es = cell2table(vertcat(rows_with_es{:}), 'VariableNames', col_names);
fname_with_es = fullfile(out_tabs, 'table_stage10_pv_es1_sweep.csv');
writetable(T_with_es, fname_with_es);
fprintf('  Saved: %s (%d rows)\n', fname_with_es, height(T_with_es));

%% =========================================================================
%  PART C: HOSTING CAPACITY SUMMARY
%% =========================================================================
fprintf('\n--- PART C: PV HOSTING CAPACITY ANALYSIS ---\n');

% Hosting capacity = max pv_scale where all voltages stay in [0.95, 1.05]
feasible_scales_no_es = T_no_es.pv_scale(T_no_es.VoltageFeasible == 1);
hosting_no_es = NaN;
if ~isempty(feasible_scales_no_es)
    hosting_no_es = max(feasible_scales_no_es);
end

feasible_scales_with_es = T_with_es.pv_scale(T_with_es.VoltageFeasible == 1);
hosting_with_es = NaN;
if ~isempty(feasible_scales_with_es)
    hosting_with_es = max(feasible_scales_with_es);
end

% Find best ES configuration at highest feasible PV scale
best_n_es = NaN;
best_es_buses = [];
if ~isnan(hosting_with_es)
    idx_best = (T_with_es.pv_scale == hosting_with_es) & (T_with_es.VoltageFeasible == 1);
    if any(idx_best)
        T_best = T_with_es(idx_best, :);
        [~, min_idx] = min(T_best.N_ES_used);
        best_n_es = T_best.N_ES_used(min_idx);
        % Parse ES buses string safely (avoid eval)
        bus_str = T_best.ES_Buses_str{min_idx};
        try
            % Use str2num for safe parsing of "[a b c]" format
            best_es_buses = str2num(bus_str); %#ok<ST2NM>
            if isempty(best_es_buses)
                best_es_buses = [];
            end
        catch
            best_es_buses = [];
        end
    end
end

fprintf('  Hosting capacity without ES-1: %.2f pu\n', hosting_no_es);
fprintf('  Hosting capacity with ES-1:    %.2f pu\n', hosting_with_es);
if ~isnan(best_n_es)
    fprintf('  Best ES-1 config at max penetration: %d devices at buses %s\n', ...
        best_n_es, mat2str(best_es_buses));
end

% Summary table
summary_cases = {
    'Baseline_no_PV', 'No PV, no ES', 0, 0, NaN, NaN;
    'Max_PV_no_ES', 'Max PV feasible without ES', hosting_no_es, 0, NaN, NaN;
    'Max_PV_with_ES', 'Max PV feasible with ES-1', hosting_with_es, best_n_es, NaN, NaN;
};
summary_cols = {'Scenario', 'Description', 'max_pv_scale', 'N_ES_used', 'Notes1', 'Notes2'};
T_summary = cell2table(summary_cases, 'VariableNames', summary_cols);
fname_summary = fullfile(out_tabs, 'table_stage10_pv_hosting_capacity.csv');
writetable(T_summary, fname_summary);
fprintf('  Saved: %s\n\n', fname_summary);

%% =========================================================================
%  GENERATE PLOTS
%% =========================================================================
fprintf('--- GENERATING PLOTS ---\n');

% Plot 1: Load and PV profiles
fig1 = plot_stage10_pv_profile(loads_base, pv_prof, ...
    fullfile(out_figs, 'fig1_existing_load_and_pv_profile.png'));
close(fig1);

% Plot 2: Voltage envelope
fig2 = plot_stage10_voltage_envelope(T_no_es, T_with_es, ...
    fullfile(out_figs, 'fig2_voltage_envelope_no_es.png'));
close(fig2);

% Plot 3: Vmax vs PV
fig3 = plot_stage10_vmax_vs_pv(T_no_es, T_with_es, ...
    fullfile(out_figs, 'fig3_vmax_vs_pv_penetration.png'));
close(fig3);

% Plot 4: Loss vs PV
fig4 = plot_stage10_loss_vs_pv(T_no_es, T_with_es, ...
    fullfile(out_figs, 'fig4_loss_vs_pv_penetration.png'));
close(fig4);

% Plot 5: Min ES count vs PV
fig5 = plot_stage10_es1_count_vs_pv(T_with_es, ...
    fullfile(out_figs, 'fig5_min_es1_count_vs_pv_penetration.png'));
close(fig5);

fprintf('\n');

%% =========================================================================
%  FINAL SUMMARY
%% =========================================================================
fprintf('=========================================================================\n');
fprintf('  STAGE 10 — PV PENETRATION STUDY COMPLETE\n');
fprintf('=========================================================================\n');
fprintf('\n  Output tables:\n');
fprintf('    %s\n', fname_no_es);
fprintf('    %s\n', fname_with_es);
fprintf('    %s\n', fname_summary);
fprintf('\n  Output figures:\n');
fprintf('    %s/fig[1-5]_*\n', out_figs);
fprintf('\n  Key findings:\n');
fprintf('    • Hosting capacity without ES-1:  %.2f pu (%.1f%% penetration)\n', ...
    hosting_no_es, hosting_no_es*100);
fprintf('    • Hosting capacity with ES-1:     %.2f pu (%.1f%% penetration)\n', ...
    hosting_with_es, hosting_with_es*100);
if ~isnan(best_n_es)
    fprintf('    • Improvement with %d ES-1 devices: +%.1f%% penetration\n', ...
        best_n_es, (hosting_with_es - hosting_no_es)*100);
end
fprintf('\n  See STAGE10_PV_README.md for full documentation.\n');
fprintf('=========================================================================\n\n');
