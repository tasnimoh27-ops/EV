%% run_ess_rating_sensitivity.m
% ESS INSTALLED RATING SENSITIVITY ANALYSIS
%
% Purpose:
%   Analyze how required ESS device count changes when the per-unit ESS rating varies.
%   Tests four ESS sizes with 2-hour storage duration:
%   - Small:  0.5 MVA / 1.0 MWh
%   - Base:   1.0 MVA / 2.0 MWh
%   - Large:  1.5 MVA / 3.0 MWh
%   - XL:     2.0 MVA / 4.0 MWh
%
%   For each rating, sweeps ESS count 1-8 and finds minimum for voltage feasibility.
%   Generates sensitivity tables and comparison figures.
%
% Output:
%   table_ess_rating_sensitivity.csv    — Full sweep results
%   table_ess_rating_minimum_count.csv  — Minimum counts per rating
%   fig_ess_min_count_vs_rating.png     — Device count vs rating
%   fig_ess_total_mva_mwh_vs_rating.png — Total capacity vs rating
%   fig_ess_loss_vs_rating.png          — Loss vs rating
%   fig_ess_vmin_vs_rating.png          — Voltage vs rating
%
% Also returns the base ESS case (1.0 MVA / 2.0 MWh) results for use in device composition.
%
% Requirements: MATLAB R2020a+, YALMIP, Gurobi
% Run from: repo root OR 03_es_feasibility_framework/main/

clear; clc; close all;

%% PATH SETUP
script_dir = fileparts(mfilename('fullpath'));
framework_root = fileparts(script_dir);
repo_root = fileparts(framework_root);

addpath(genpath(fullfile(framework_root, 'functions')));
addpath(genpath(fullfile(framework_root, 'plotting')));
addpath(genpath(fullfile(framework_root, 'data')));
addpath(genpath(fullfile(repo_root, '02_baseline_modules', 'shared')));

out_base = fullfile(repo_root, '04_results', 'es_framework');
out_tabs = fullfile(out_base, 'tables');
out_figs = fullfile(out_base, 'figures');
if ~exist(out_tabs,'dir'), mkdir(out_tabs); end
if ~exist(out_figs,'dir'), mkdir(out_figs); end

fprintf('\n');
fprintf('=========================================================\n');
fprintf('  ESS INSTALLED RATING SENSITIVITY ANALYSIS\n');
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

Sbase_MVA = 10.0;

%% ESS RATING CASES (MVA / MWh with 2-hour duration)
% Conversion: 1 MVA / Sbase = power in pu, Energy (MWh) / Sbase = energy in pu·h
ess_ratings = {
    'Small',  0.5, 1.0;    % 0.05 pu / 0.10 pu·h
    'Base',   1.0, 2.0;    % 0.10 pu / 0.20 pu·h
    'Large',  1.5, 3.0;    % 0.15 pu / 0.30 pu·h
    'XL',     2.0, 4.0     % 0.20 pu / 0.40 pu·h
};

%% ESS SWEEP PARAMETERS
N_ess_sweep = 1:8;

%% VSI CANDIDATE RESTRICTION (same as Stage 2/3)
K_cand = 15;
fprintf('Computing VSI for ESS candidate selection...\n');
vsi = calculate_voltage_impact_score(topo, loads, rho);
ess_cand = sort(vsi.rank(1:K_cand)');
ess_cand = ess_cand(ess_cand ~= topo.root);
fprintf('  ESS candidates (top-%d VSI): %s\n\n', K_cand, mat2str(ess_cand));

%% BASE PARAMS
p_base.Vmin          = 0.95;
p_base.Vmax          = 1.05;
p_base.soft_voltage  = false;
p_base.obj_mode      = 'planning';
p_base.w_loss        = 1.0;
p_base.w_b           = 0.0;
p_base.w_vio         = 0.0;
p_base.candidate_buses = ess_cand;
p_base.price         = price;
p_base.time_limit    = 120;
p_base.MIPGap        = 0.05;
% ESS efficiency and SOC parameters
p_base.eta_ch        = 0.95;
p_base.eta_dis       = 0.95;
p_base.SOC_init      = 0.50;
p_base.SOC_min       = 0.10;
p_base.Q_b_max_pu    = 0.10;

%% SENSITIVITY SWEEP
% Collect all results for table
all_rows_sensitivity = {};

fprintf('--- ESS Rating Sensitivity Sweep ---\n');

for r_idx = 1:size(ess_ratings, 1)
    rating_name = ess_ratings{r_idx, 1};
    ess_mva = ess_ratings{r_idx, 2};
    ess_mwh = ess_ratings{r_idx, 3};

    % Convert to per-unit
    ess_p_pu = ess_mva / Sbase_MVA;      % Power (assuming unity PF)
    ess_e_pu_h = ess_mwh / Sbase_MVA;   % Energy in pu·h

    fprintf('\n--- Rating: %s (%.1f MVA / %.1f MWh, %.2f pu / %.2f pu·h) ---\n', ...
        rating_name, ess_mva, ess_mwh, ess_p_pu, ess_e_pu_h);

    min_ess_count = NaN;
    min_ess_result = [];

    for N_ess = N_ess_sweep
        p = p_base;
        p.N_b_max = N_ess;
        p.E_cap_pu = ess_e_pu_h;
        p.P_ch_max_pu = ess_p_pu;
        p.P_dis_max_pu = ess_p_pu;

        fprintf('  %s | N_ess_max=%d | ', rating_name, N_ess);
        r = solve_ess_misocp(topo, loads, p);

        % Extract results
        sol_ok  = double(r.solver_ok);
        volt_ok = double(r.voltage_ok);
        n_ess_used = r.n_ess;
        vmin = r.Vmin_24h;
        vmax = max(max(r.V_val));
        loss = r.total_loss;
        worst_bus = r.worst_bus;
        worst_hour = r.worst_hour;
        solve_time = r.solve_time;

        % Total installed capacity
        total_ess_mva = n_ess_used * ess_mva;
        total_ess_mwh = n_ess_used * ess_mwh;

        % Build row for full sensitivity table
        row_data = {
            rating_name, ess_mva, ess_mwh, 2.0, ...  % RatingCase, PerESSInverter_MVA, PerESSEnergy_MWh, Duration_h
            N_ess, n_ess_used, ...                      % N_ESS_allowed, N_ESS_used
            volt_ok, vmin, vmax, loss, ...              % VoltageFeasible, Vmin_pu, Vmax_pu, TotalLoss_pu
            total_ess_mva, total_ess_mwh, ...           % TotalESSInverter_MVA, TotalESSEnergy_MWh
            worst_bus, worst_hour, ...                  % WorstBus, WorstHour
            sol_ok, solve_time, ...                     % SolveStatus (1=OK), SolveTime_s
            '' ...                                       % Notes
        };
        all_rows_sensitivity{end+1} = row_data;

        % Track minimum for this rating
        if volt_ok && isnan(min_ess_count)
            min_ess_count = N_ess;
            min_ess_result = row_data;
            fprintf('FEASIBLE at N_ess=%d\n', N_ess);
            break;
        else
            fprintf('N/F\n');
        end
    end

    if isnan(min_ess_count)
        fprintf('  WARNING: %s rating not feasible in N_ess=1..%d\n', rating_name, max(N_ess_sweep));
    end
end

%% BUILD FULL SENSITIVITY TABLE
col_names_sensitivity = {
    'RatingCase', 'PerESSInverter_MVA', 'PerESSEnergy_MWh', 'Duration_h', ...
    'N_ESS_allowed', 'N_ESS_used', ...
    'VoltageFeasible', 'Vmin_pu', 'Vmax_pu', 'TotalLoss_pu', ...
    'TotalESSInverter_MVA', 'TotalESSEnergy_MWh', ...
    'WorstBus', 'WorstHour', ...
    'SolveStatus', 'SolveTime_s', 'Notes'
};

T_sensitivity = cell2table(vertcat(all_rows_sensitivity{:}), 'VariableNames', col_names_sensitivity);

fname_full = fullfile(out_tabs, 'table_ess_rating_sensitivity.csv');
writetable(T_sensitivity, fname_full);
fprintf('\n  Saved: %s\n', fname_full);

%% BUILD MINIMUM-COUNT TABLE
fprintf('\n--- ESS Rating Minimum Count Summary ---\n');
min_count_rows = {};

for r_idx = 1:size(ess_ratings, 1)
    rating_name = ess_ratings{r_idx, 1};
    ess_mva = ess_ratings{r_idx, 2};
    ess_mwh = ess_ratings{r_idx, 3};

    % Find minimum count row for this rating
    mask = strcmp(T_sensitivity.RatingCase, rating_name);
    rating_rows = T_sensitivity(mask, :);

    if height(rating_rows) > 0
        % Find first feasible row
        feasible_rows = rating_rows(rating_rows.VoltageFeasible == 1, :);
        if height(feasible_rows) > 0
            min_row = feasible_rows(1, :);
            min_count_rows{end+1} = {
                rating_name, ess_mva, ess_mwh, 2.0, ...
                min_row.N_ESS_used, min_row.Vmin_pu, min_row.Vmax_pu, min_row.TotalLoss_pu, ...
                min_row.TotalESSInverter_MVA, min_row.TotalESSEnergy_MWh
            };
            fprintf('  %s: N_ess_min=%d | Vmin=%.4f | Loss=%.5f | Total=%d×%.1f MVA / %d×%.1f MWh\n', ...
                rating_name, min_row.N_ESS_used, min_row.Vmin_pu, min_row.TotalLoss_pu, ...
                min_row.N_ESS_used, ess_mva, min_row.N_ESS_used, ess_mwh);
        else
            fprintf('  %s: NO FEASIBLE SOLUTION\n', rating_name);
        end
    end
end

col_names_min = {
    'RatingCase', 'PerESSInverter_MVA', 'PerESSEnergy_MWh', 'Duration_h', ...
    'MinN_ESS', 'Vmin_pu', 'Vmax_pu', 'TotalLoss_pu', ...
    'TotalESSInverter_MVA', 'TotalESSEnergy_MWh'
};

T_min_count = cell2table(vertcat(min_count_rows{:}), 'VariableNames', col_names_min);

fname_min = fullfile(out_tabs, 'table_ess_rating_minimum_count.csv');
writetable(T_min_count, fname_min);
fprintf('\n  Saved: %s\n', fname_min);

%% GENERATE FIGURES

%% Figure 1: Minimum ESS count vs rating
fig1 = figure('Color','w','Position',[100 100 1000 500]);
ratings_names = T_min_count.RatingCase;
min_counts = T_min_count.MinN_ESS;
mvas = T_min_count.PerESSInverter_MVA;

bar_h = bar(1:height(T_min_count), min_counts, 0.5, 'FaceColor', [0.2 0.5 0.8], 'EdgeColor', 'k', 'LineWidth', 1.5);
hold on;
grid on;
set(gca, 'XTick', 1:height(T_min_count), 'XTickLabel', ratings_names);
xlabel('Per-Unit ESS Rating (MVA)', 'FontSize', 11, 'FontWeight', 'bold');
ylabel('Minimum ESS Count Required', 'FontSize', 11, 'FontWeight', 'bold');
title('ESS Device Count vs Installed Rating (2-Hour Duration)', 'FontSize', 12, 'FontWeight', 'bold');
set(gca, 'FontSize', 10);
ylim([0, max(min_counts)+1]);

% Add value labels on bars
for i = 1:height(T_min_count)
    text(i, min_counts(i) + 0.1, sprintf('%d', min_counts(i)), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 10, 'FontWeight', 'bold');
end

saveas(fig1, fullfile(out_figs, 'fig_ess_min_count_vs_rating.png'));
fprintf('\n  Saved: fig_ess_min_count_vs_rating.png\n');

%% Figure 2: Total installed MVA and MWh
fig2 = figure('Color','w','Position',[100 100 1000 500]);
total_mvas = T_min_count.TotalESSInverter_MVA;
total_mwhs = T_min_count.TotalESSEnergy_MWh;

ax1 = gca;
bar_h1 = bar(ax1, 1:height(T_min_count), total_mvas, 0.35, 'FaceColor', [0.2 0.5 0.8], 'EdgeColor', 'k', 'LineWidth', 1.5);
hold on;

ax2 = axes('Position', get(ax1, 'Position'), 'XAxisLocation', 'bottom', 'YAxisLocation', 'right', 'Color', 'none', ...
    'XTick', [], 'XLim', get(ax1, 'XLim'));
line(ax2, 1:height(T_min_count), total_mwhs, 'Color', [0.8 0.2 0.2], 'Marker', 'o', 'MarkerSize', 8, ...
    'LineWidth', 2, 'MarkerFaceColor', [0.8 0.2 0.2]);

set(ax1, 'XTick', 1:height(T_min_count), 'XTickLabel', ratings_names);
set(ax1, 'FontSize', 10);
set(ax2, 'FontSize', 10);
xlabel(ax1, 'Per-Unit ESS Rating (MVA)', 'FontSize', 11, 'FontWeight', 'bold');
ylabel(ax1, 'Total Installed Inverter MVA', 'FontSize', 11, 'FontWeight', 'bold');
ylabel(ax2, 'Total Installed Battery Energy (MWh)', 'FontSize', 11, 'FontWeight', 'bold');
title('Total Installed ESS Capacity vs Rating', 'FontSize', 12, 'FontWeight', 'bold');

ax1.YColor = [0.2 0.5 0.8];
ax2.YColor = [0.8 0.2 0.2];

legend([bar_h1, ax2.Children(1)], {'Inverter MVA', 'Battery MWh'}, 'Location', 'upper left', 'FontSize', 10);

saveas(fig2, fullfile(out_figs, 'fig_ess_total_mva_mwh_vs_rating.png'));
fprintf('  Saved: fig_ess_total_mva_mwh_vs_rating.png\n');

%% Figure 3: Total loss vs rating
fig3 = figure('Color','w','Position',[100 100 1000 500]);
losses = T_min_count.TotalLoss_pu;

plot(1:height(T_min_count), losses, 'Color', [0.2 0.5 0.8], 'Marker', 'o', 'MarkerSize', 10, ...
    'LineWidth', 2, 'MarkerFaceColor', [0.2 0.5 0.8]);
hold on;
grid on;
set(gca, 'XTick', 1:height(T_min_count), 'XTickLabel', ratings_names);
xlabel('Per-Unit ESS Rating (MVA)', 'FontSize', 11, 'FontWeight', 'bold');
ylabel('Total System Loss (pu)', 'FontSize', 11, 'FontWeight', 'bold');
title('System Loss vs ESS Rating (Minimum Feasible Count)', 'FontSize', 12, 'FontWeight', 'bold');
set(gca, 'FontSize', 10);

% Add value labels
for i = 1:height(T_min_count)
    text(i, losses(i) + 0.01, sprintf('%.4f', losses(i)), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 10);
end

saveas(fig3, fullfile(out_figs, 'fig_ess_loss_vs_rating.png'));
fprintf('  Saved: fig_ess_loss_vs_rating.png\n');

%% Figure 4: Vmin vs rating
fig4 = figure('Color','w','Position',[100 100 1000 500]);
vmins = T_min_count.Vmin_pu;

plot(1:height(T_min_count), vmins, 'Color', [0.2 0.5 0.8], 'Marker', 's', 'MarkerSize', 10, ...
    'LineWidth', 2, 'MarkerFaceColor', [0.2 0.5 0.8]);
hold on;
grid on;
yline(0.95, 'k--', 'LineWidth', 2, 'Label', 'Feasibility threshold (0.95 pu)');
set(gca, 'XTick', 1:height(T_min_count), 'XTickLabel', ratings_names);
xlabel('Per-Unit ESS Rating (MVA)', 'FontSize', 11, 'FontWeight', 'bold');
ylabel('Minimum Voltage (pu)', 'FontSize', 11, 'FontWeight', 'bold');
title('Minimum Voltage vs ESS Rating (Minimum Feasible Count)', 'FontSize', 12, 'FontWeight', 'bold');
set(gca, 'FontSize', 10);
ylim([0.9, 1.0]);

% Add value labels
for i = 1:height(T_min_count)
    text(i, vmins(i) + 0.005, sprintf('%.4f', vmins(i)), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 10);
end

saveas(fig4, fullfile(out_figs, 'fig_ess_vmin_vs_rating.png'));
fprintf('  Saved: fig_ess_vmin_vs_rating.png\n');

%% EXTRACT BASE ESS CASE RESULTS FOR DEVICE COMPOSITION UPDATE
fprintf('\n--- Base ESS Case Results for Device Composition ---\n');
base_mask = strcmp(T_min_count.RatingCase, 'Base');
if any(base_mask)
    base_row = T_min_count(base_mask, :);
    ess_base.mva_per_unit = 1.0;
    ess_base.mwh_per_unit = 2.0;
    ess_base.n_min = base_row.MinN_ESS(1);
    ess_base.vmin = base_row.Vmin_pu(1);
    ess_base.vmax = base_row.Vmax_pu(1);
    ess_base.loss = base_row.TotalLoss_pu(1);
    ess_base.total_mva = base_row.TotalESSInverter_MVA(1);
    ess_base.total_mwh = base_row.TotalESSEnergy_MWh(1);

    fprintf('  Base ESS (1.0 MVA / 2.0 MWh):\n');
    fprintf('    Min count: %d units\n', ess_base.n_min);
    fprintf('    Total installed: %.1f MVA / %.1f MWh\n', ess_base.total_mva, ess_base.total_mwh);
    fprintf('    Vmin/Vmax: %.4f / %.4f pu\n', ess_base.vmin, ess_base.vmax);
    fprintf('    Loss: %.5f pu\n', ess_base.loss);

    % Save base results for use by device composition script
    base_results_file = fullfile(out_tabs, 'ess_base_case_results.mat');
    save(base_results_file, 'ess_base');
    fprintf('  Saved base case results: %s\n', base_results_file);
else
    fprintf('  WARNING: Base ESS case not found in results!\n');
end

%% SUMMARY
fprintf('\n');
fprintf('=========================================================\n');
fprintf('  ESS RATING SENSITIVITY COMPLETE\n');
fprintf('  Outputs saved to:\n');
fprintf('    Tables: 04_results/es_framework/tables/\n');
fprintf('    Figures: 04_results/es_framework/figures/\n');
fprintf('=========================================================\n\n');
