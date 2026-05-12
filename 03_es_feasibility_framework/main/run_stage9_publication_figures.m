%% run_stage9_publication_figures.m
% STAGE 9 — Publication Figures
%
% Generates all publication-ready figures comparing Stages 1-8:
%
% Figure 1: Pareto substitution curves — Stage 4 (basic ES) vs Stage 7 (ES-1)
%   - Required STATCOMs vs N_e budget
%   - Required ESSs vs N_e budget
%   - Key annotation: ES-1 drops to 0 at N_e=4; basic ES floors at 2/1
%
% Figure 2: Loss reduction vs N_e
%   - Basic ES+STATCOM (Stage 4) vs ES-1+STATCOM (Stage 7)
%   - Basic ES+ESS (Stage 4) vs ES-1+ESS (Stage 7)
%   - Reference lines: no-support, Qg-only baselines
%
% Figure 3: ES-1 standalone performance
%   - Vmin vs N_e (Stage 6 sweep): marks feasibility threshold at N_e=4
%   - Loss vs N_e for ES-1 alone
%
% Figure 4: Device count savings (bar chart)
%   - Minimum total devices for each configuration
%   - Stacked: ES (active) + reactive/storage supplement
%
% Figure 5: Joint comparison Stage 5 vs Stage 8 (ES-1 joint)
%   - Loads from table_stage8_es1_joint_summary.csv if available
%   - Skips gracefully if Stage 8 not yet run
%
% Output: 04_results/es_framework/figures/stage9/
% Requirements: MATLAB R2020a+
% Run from: repo root  OR  03_es_feasibility_framework/main/

clear; clc; close all;

%% PATH SETUP
script_dir = fileparts(mfilename('fullpath'));
new_root   = fileparts(script_dir);
repo_root  = fileparts(new_root);

out_figs = fullfile(repo_root, '04_results', 'es_framework', 'figures', 'stage9');
if ~exist(out_figs,'dir'), mkdir(out_figs); end
tabs_dir = fullfile(repo_root, '04_results', 'es_framework', 'tables');

fprintf('\n');
fprintf('=========================================================\n');
fprintf('  STAGE 9 — PUBLICATION FIGURES\n');
fprintf('  IEEE 33-Bus | rho=0.70 | u_min=0.20 | scale=1.80\n');
fprintf('=========================================================\n\n');

%% LOAD DATA
fprintf('Loading result tables...\n');

% Stage 4: basic ES substitution
T4 = readtable(fullfile(tabs_dir, 'table_stage4_substitution.csv'));
% Stage 5: basic ES joint summary
T5 = readtable(fullfile(tabs_dir, 'table_stage5_summary.csv'));
% Stage 6: ES-1 standalone sweep
T6 = readtable(fullfile(tabs_dir, 'table_stage6_es1_sweep.csv'));
% Stage 7: ES-1 substitution
T7 = readtable(fullfile(tabs_dir, 'table_stage7_es1_substitution.csv'));
% Stage 6 comparison cases
T6c = readtable(fullfile(tabs_dir, 'table_stage6_comparison.csv'));
% Baseline
Tbase = readtable(fullfile(tabs_dir, 'table_case_baseline_corrected.csv'));

% Stage 8: ES-1 joint (optional — skip if not yet run)
f8 = fullfile(tabs_dir, 'table_stage8_es1_joint_summary.csv');
has_stage8 = isfile(f8);
if has_stage8
    T8 = readtable(f8);
    fprintf('  Stage 8 data found — will generate Figure 5.\n');
else
    fprintf('  Stage 8 data not found — Figure 5 will be skipped.\n');
end

%% EXTRACT KEY SCALARS
% No-support baseline
idx_ns = strcmp(Tbase.Case, 'C0_NoSupport');
loss_nosupport = Tbase.TotalLoss_pu(idx_ns);
vmin_nosupport = Tbase.Vmin_pu(idx_ns);

% Qg-only baseline
idx_qg = strcmp(Tbase.Case, 'C1_QgOnly');
loss_qgonly = Tbase.TotalLoss_pu(idx_qg);

% Stage 6: ES-1 min feasible N_e = 4
es1_min_ne = 4;

fprintf('  No-support loss = %.4f pu, Vmin = %.4f pu\n', loss_nosupport, vmin_nosupport);
fprintf('  Qg-only loss    = %.4f pu\n', loss_qgonly);
fprintf('  ES-1 threshold  = N_e = %d\n\n', es1_min_ne);

%% COLORS AND STYLES
c_blue   = [0.12 0.47 0.71];
c_red    = [0.84 0.15 0.16];
c_green  = [0.17 0.63 0.17];
c_orange = [1.00 0.50 0.05];
c_gray   = [0.50 0.50 0.50];
c_purple = [0.58 0.40 0.74];

lw = 1.8;
ms = 7;

% =========================================================================
%  FIGURE 1: PARETO SUBSTITUTION CURVES
%  Stage 4 (basic ES) vs Stage 7 (ES-1) — STATCOM and ESS paths
% =========================================================================
fprintf('Generating Figure 1: Pareto substitution curves...\n');

ne4 = T4.N_e_budget;
ne7 = T7.N_e_budget;

fig1 = figure('Visible','off','Position',[100 100 900 380]);

% --- Subplot 1: STATCOMs ---
ax1 = subplot(1,2,1);
hold on; grid on; box on;

plot(ne4, T4.N_s_min, '-o', 'Color',c_blue, 'LineWidth',lw, 'MarkerSize',ms, ...
    'MarkerFaceColor',c_blue, 'DisplayName','Basic ES + STATCOM (Stage 4)');
plot(ne7, T7.N_s_min, '--s', 'Color',c_red, 'LineWidth',lw, 'MarkerSize',ms, ...
    'MarkerFaceColor',c_red, 'DisplayName','ES-1 + STATCOM (Stage 7)');

% Annotation: ES-1 threshold at N_e=4
xline(es1_min_ne, ':', 'Color',c_gray, 'LineWidth',1.2, ...
    'Label','ES-1 feasible (N_e=4)', 'LabelOrientation','horizontal', ...
    'LabelVerticalAlignment','bottom', 'FontSize',8);

xlabel('N_e  (ES budget)', 'FontSize',11);
ylabel('N_s^{min}  (STATCOMs required)', 'FontSize',11);
title('STATCOM Substitution', 'FontSize',12, 'FontWeight','bold');
legend('Location','northeast', 'FontSize',9);
ylim([-0.3, 8]);
xlim([-1, 34]);
set(ax1, 'XTick', [0 4 8 12 16 20 24 28 32]);

% Annotate final values
text(32.5, T4.N_s_min(end)+0.15, sprintf('%d',T4.N_s_min(end)), ...
    'Color',c_blue, 'FontSize',9, 'FontWeight','bold');
text(32.5, T7.N_s_min(end)-0.4, sprintf('%d',T7.N_s_min(end)), ...
    'Color',c_red, 'FontSize',9, 'FontWeight','bold');

% Ratio annotation
s4_ratio = 32 / (T4.N_s_min(1) - T4.N_s_min(end));
s7_ratio = 32 / T7.N_s_min(1);
text(2, 1.2, sprintf('ES-1: %.1f ES/STATCOM', 32/T7.N_s_min(1)), ...
    'Color',c_red, 'FontSize',8, 'HorizontalAlignment','left');
text(2, 0.5, sprintf('Basic ES: %.1f ES/STATCOM', s4_ratio), ...
    'Color',c_blue, 'FontSize',8, 'HorizontalAlignment','left');

% --- Subplot 2: ESSs ---
ax2 = subplot(1,2,2);
hold on; grid on; box on;

plot(ne4, T4.N_b_min, '-o', 'Color',c_blue, 'LineWidth',lw, 'MarkerSize',ms, ...
    'MarkerFaceColor',c_blue, 'DisplayName','Basic ES + ESS (Stage 4)');
plot(ne7, T7.N_b_min, '--s', 'Color',c_red, 'LineWidth',lw, 'MarkerSize',ms, ...
    'MarkerFaceColor',c_red, 'DisplayName','ES-1 + ESS (Stage 7)');

xline(es1_min_ne, ':', 'Color',c_gray, 'LineWidth',1.2, ...
    'Label','ES-1 feasible (N_e=4)', 'LabelOrientation','horizontal', ...
    'LabelVerticalAlignment','bottom', 'FontSize',8);

xlabel('N_e  (ES budget)', 'FontSize',11);
ylabel('N_b^{min}  (ESS units required)', 'FontSize',11);
title('ESS Substitution', 'FontSize',12, 'FontWeight','bold');
legend('Location','northeast', 'FontSize',9);
ylim([-0.3, 4]);
xlim([-1, 34]);
set(ax2, 'XTick', [0 4 8 12 16 20 24 28 32]);

text(32.5, T4.N_b_min(end)+0.1, sprintf('%d',T4.N_b_min(end)), ...
    'Color',c_blue, 'FontSize',9, 'FontWeight','bold');
text(32.5, T7.N_b_min(end)-0.25, sprintf('%d',T7.N_b_min(end)), ...
    'Color',c_red, 'FontSize',9, 'FontWeight','bold');

s4_ess_ratio = 32 / (T4.N_b_min(1) - T4.N_b_min(end));
text(2, 0.55, sprintf('ES-1: %.1f ES/ESS', 32/T7.N_b_min(1)), ...
    'Color',c_red, 'FontSize',8);
text(2, 0.2, sprintf('Basic ES: %.1f ES/ESS', s4_ess_ratio), ...
    'Color',c_blue, 'FontSize',8);

sgtitle('Pareto Substitution Curves: Basic ES vs ES-1 (Hou Reactive Model)', ...
    'FontSize',13, 'FontWeight','bold');

saveas(fig1, fullfile(out_figs, 'fig1_pareto_substitution.png'));
saveas(fig1, fullfile(out_figs, 'fig1_pareto_substitution.fig'));
fprintf('  Saved: fig1_pareto_substitution\n');

% =========================================================================
%  FIGURE 2: LOSS REDUCTION vs N_e
%  Stage 4 vs Stage 7 loss curves + baselines
% =========================================================================
fprintf('Generating Figure 2: Loss reduction curves...\n');

fig2 = figure('Visible','off','Position',[100 100 820 440]);
hold on; grid on; box on;

% Reference lines
yline(loss_nosupport, '--', 'Color',c_gray, 'LineWidth',1.4, ...
    'Label',sprintf('No support (%.3f pu)',loss_nosupport), ...
    'LabelHorizontalAlignment','left', 'FontSize',8);
yline(loss_qgonly, '-.', 'Color',c_green, 'LineWidth',1.4, ...
    'Label',sprintf('Qg only (%.3f pu)',loss_qgonly), ...
    'LabelHorizontalAlignment','left', 'FontSize',8);

% Stage 4 curves
plot(ne4, T4.Loss_STATCOM, '-o', 'Color',c_blue, 'LineWidth',lw, 'MarkerSize',ms, ...
    'MarkerFaceColor',c_blue, 'DisplayName','Basic ES + min STATCOM (S4)');
plot(ne4, T4.Loss_ESS, '-^', 'Color',c_purple, 'LineWidth',lw, 'MarkerSize',ms, ...
    'MarkerFaceColor',c_purple, 'DisplayName','Basic ES + min ESS (S4)');

% Stage 7 curves
plot(ne7, T7.Loss_S, '--s', 'Color',c_red, 'LineWidth',lw, 'MarkerSize',ms, ...
    'MarkerFaceColor',c_red, 'DisplayName','ES-1 + min STATCOM (S7)');
plot(ne7, T7.Loss_B, '--v', 'Color',c_orange, 'LineWidth',lw, 'MarkerSize',ms, ...
    'MarkerFaceColor',c_orange, 'DisplayName','ES-1 + min ESS (S7)');

% ES-1 standalone (Stage 6)
es1_rows = strcmp(T6.CaseType, 'ES1-only') & T6.VoltageFeasible == 1;
if any(es1_rows)
    plot(T6.N_e_max(es1_rows), T6.TotalLoss_pu(es1_rows), ...
        'kp', 'MarkerSize',12, 'MarkerFaceColor','k', ...
        'DisplayName','ES-1 standalone (N_e=4, S6)');
end

xlabel('N_e  (ES budget)', 'FontSize',11);
ylabel('Total 24h Loss (pu)', 'FontSize',11);
title({'Loss Reduction vs ES Budget', ...
    'IEEE 33-Bus | \rho=0.70 | u_{min}=0.20 | Scale=1.80'}, ...
    'FontSize',12, 'FontWeight','bold');
legend('Location','northeast', 'FontSize',9);
xlim([-1, 34]);
ylim([0, loss_nosupport * 1.05]);
set(gca, 'XTick', [0 4 8 12 16 20 24 28 32]);

saveas(fig2, fullfile(out_figs, 'fig2_loss_vs_ne.png'));
saveas(fig2, fullfile(out_figs, 'fig2_loss_vs_ne.fig'));
fprintf('  Saved: fig2_loss_vs_ne\n');

% =========================================================================
%  FIGURE 3: ES-1 STANDALONE PERFORMANCE (Vmin vs N_e)
% =========================================================================
fprintf('Generating Figure 3: ES-1 standalone threshold...\n');

% ES-1 feasibility data (all N_e from Stage 6, including infeasible)
ne6_all = [1 2 3 4 8 16 24 32];
vmin6   = [NaN NaN NaN ...
           T6.Vmin_pu(strcmp(T6.CaseName,'C14_ES1_Ne4')) ...
           T6.Vmin_pu(strcmp(T6.CaseName,'C15_ES1_Ne8')) ...
           T6.Vmin_pu(strcmp(T6.CaseName,'C15_ES1_Ne16')) ...
           T6.Vmin_pu(strcmp(T6.CaseName,'C15_ES1_Ne24')) ...
           T6.Vmin_pu(strcmp(T6.CaseName,'C15_ES1_Ne32'))];
loss6   = [NaN NaN NaN ...
           T6.TotalLoss_pu(strcmp(T6.CaseName,'C14_ES1_Ne4')) ...
           T6.TotalLoss_pu(strcmp(T6.CaseName,'C15_ES1_Ne8')) ...
           T6.TotalLoss_pu(strcmp(T6.CaseName,'C15_ES1_Ne16')) ...
           T6.TotalLoss_pu(strcmp(T6.CaseName,'C15_ES1_Ne24')) ...
           T6.TotalLoss_pu(strcmp(T6.CaseName,'C15_ES1_Ne32'))];

fig3 = figure('Visible','off','Position',[100 100 820 440]);

% Vmin panel
ax3a = subplot(1,2,1);
hold on; grid on; box on;
yline(0.95, 'k--', 'LineWidth',1.2, 'Label','V_{min} limit = 0.95', ...
    'LabelHorizontalAlignment','left', 'FontSize',8);
yline(vmin_nosupport, '--', 'Color',c_gray, 'LineWidth',1.2, ...
    'Label',sprintf('No support %.4f',vmin_nosupport), ...
    'LabelHorizontalAlignment','left', 'FontSize',8);
valid6 = ~isnan(vmin6);
plot(ne6_all(valid6), vmin6(valid6), '-rs', 'LineWidth',lw, 'MarkerSize',ms, ...
    'MarkerFaceColor',c_red);
infeas6 = ~valid6;
if any(infeas6)
    plot(ne6_all(infeas6), 0.92*ones(sum(infeas6),1), 'rx', 'MarkerSize',12, ...
        'LineWidth',2, 'DisplayName','Infeasible');
end
xline(es1_min_ne, ':', 'Color',c_gray, 'LineWidth',1.2);
text(es1_min_ne+0.3, 0.923, sprintf('N_e=%d\nfeasible',es1_min_ne), ...
    'FontSize',8, 'Color',c_gray);
xlabel('N_e (ES-1 budget)', 'FontSize',11);
ylabel('V_{min} 24h (pu)', 'FontSize',11);
title('ES-1 Standalone: Voltage vs N_e', 'FontSize',11, 'FontWeight','bold');
ylim([0.91, 0.965]);
xlim([-0.5, 33]);
set(ax3a, 'XTick', ne6_all);

% Loss panel
ax3b = subplot(1,2,2);
hold on; grid on; box on;
yline(loss_nosupport, '--', 'Color',c_gray, 'LineWidth',1.2, ...
    'Label',sprintf('No support %.3f',loss_nosupport), ...
    'LabelHorizontalAlignment','left', 'FontSize',8);
plot(ne6_all(valid6), loss6(valid6), '-rs', 'LineWidth',lw, 'MarkerSize',ms, ...
    'MarkerFaceColor',c_red);
xline(es1_min_ne, ':', 'Color',c_gray, 'LineWidth',1.2);
xlabel('N_e (ES-1 budget)', 'FontSize',11);
ylabel('Total 24h Loss (pu)', 'FontSize',11);
title('ES-1 Standalone: Loss vs N_e', 'FontSize',11, 'FontWeight','bold');
xlim([-0.5, 33]);
set(ax3b, 'XTick', ne6_all);

sgtitle('ES-1 Standalone Performance (Hou Reactive Model, \rho=0.70)', ...
    'FontSize',12, 'FontWeight','bold');

saveas(fig3, fullfile(out_figs, 'fig3_es1_standalone.png'));
saveas(fig3, fullfile(out_figs, 'fig3_es1_standalone.fig'));
fprintf('  Saved: fig3_es1_standalone\n');

% =========================================================================
%  FIGURE 4: DEVICE COUNT SAVINGS — Stacked bar comparison
% =========================================================================
fprintf('Generating Figure 4: Device count savings...\n');

% Configuration labels and device counts
cfg_labels = {'STATCOM only', 'ESS only', 'Basic ES N_{32}+STATCOM', ...
    'Basic ES N_{32}+ESS', 'ES-1 N_4 alone', 'ES-1 N_{15}^*'};

% [ES/ES-1 count, supplemental count]
cfg_es   = [0,  0,  32, 32, 4,  15];
cfg_supp = [7,  3,   2,  1, 0,   0];
cfg_type = {'STATCOM','ESS','STATCOM','ESS','—','—'};

n_cfg = numel(cfg_labels);
bar_data = [cfg_es' cfg_supp'];

fig4 = figure('Visible','off','Position',[100 100 820 460]);
ax4 = axes('Parent',fig4);

b = bar(ax4, bar_data, 'stacked');
b(1).FaceColor = c_blue;   b(1).DisplayName = 'ES / ES-1 devices';
b(2).FaceColor = c_orange; b(2).DisplayName = 'Supplemental (STATCOM/ESS)';

set(ax4, 'XTickLabel', cfg_labels, 'XTick', 1:n_cfg, ...
    'FontSize', 9, 'TickLabelInterpreter', 'tex');
xtickangle(ax4, 25);
ylabel('Device Count', 'FontSize', 11);
title({'Minimum Device Count for Voltage Feasibility', ...
    'IEEE 33-Bus | \rho=0.70 | u_{min}=0.20'}, ...
    'FontSize',12, 'FontWeight','bold');
legend('Location','northeast', 'FontSize',9);
grid(ax4, 'on'); box(ax4, 'on');
ylim([0, 40]);

% Label total on top of each bar
totals = sum(bar_data, 2);
for i = 1:n_cfg
    text(i, totals(i)+0.5, sprintf('%d', totals(i)), ...
        'HorizontalAlignment','center', 'FontSize',9, 'FontWeight','bold', ...
        'Parent',ax4);
end

% Footnote for ES-1 saturation
text(0.5, -6, '* ES-1 saturates at N_e=15 (optimizer selects 15 of 32 budget)', ...
    'FontSize',8, 'Color',c_gray, 'Units','data');

saveas(fig4, fullfile(out_figs, 'fig4_device_savings.png'));
saveas(fig4, fullfile(out_figs, 'fig4_device_savings.fig'));
fprintf('  Saved: fig4_device_savings\n');

% =========================================================================
%  FIGURE 5: JOINT COMPARISON — Stage 5 (basic ES) vs Stage 8 (ES-1 joint)
%  Only generated if Stage 8 has been run
% =========================================================================
if has_stage8
    fprintf('Generating Figure 5: Joint comparison S5 vs S8...\n');

    % Stage 5 data (available at N_e=0,8,16,32)
    s5_ne  = T5.N_e;
    s5_nr  = T5.Joint_Nr_min;

    % Stage 8 data
    s8_ne  = T8.N_e;
    s8_nr  = T8.ES1_Joint_Nr;
    % Replace 0 with 0 for clarity; NaN means not feasible in sweep range
    s8_nr(isnan(s8_nr)) = NaN;

    fig5 = figure('Visible','off','Position',[100 100 820 440]);

    % --- Subplot 1: Nr_min vs N_e ---
    ax5a = subplot(1,2,1);
    hold on; grid on; box on;

    plot(s5_ne, s5_nr, '-o', 'Color',c_blue, 'LineWidth',lw, 'MarkerSize',ms, ...
        'MarkerFaceColor',c_blue, 'DisplayName','Basic ES Joint (Stage 5)');

    valid8 = ~isnan(s8_nr);
    if any(valid8)
        plot(s8_ne(valid8), s8_nr(valid8), '--s', 'Color',c_red, 'LineWidth',lw, ...
            'MarkerSize',ms, 'MarkerFaceColor',c_red, 'DisplayName','ES-1 Joint (Stage 8)');
    end

    xline(es1_min_ne, ':', 'Color',c_gray, 'LineWidth',1.2, ...
        'Label','ES-1 solo OK (N_e=4)', 'LabelHorizontalAlignment','right', 'FontSize',8);

    xlabel('N_e (ES budget)', 'FontSize',11);
    ylabel('N_r^{min} (joint STATCOM+ESS)', 'FontSize',11);
    title('Min Supplemental Devices: Joint Allocation', 'FontSize',11, 'FontWeight','bold');
    legend('Location','northeast', 'FontSize',9);
    ylim([-0.3, 4]);
    xlim([-1, 34]);

    % --- Subplot 2: Loss comparison at matched N_e ---
    ax5b = subplot(1,2,2);
    hold on; grid on; box on;

    s5_loss = T5.Loss_pu;
    valid5_loss = ~isnan(s5_loss);
    if any(valid5_loss)
        plot(s5_ne(valid5_loss), s5_loss(valid5_loss), '-o', 'Color',c_blue, ...
            'LineWidth',lw, 'MarkerSize',ms, 'MarkerFaceColor',c_blue, ...
            'DisplayName','Basic ES Joint (Stage 5)');
    end

    s8_loss = T8.Loss_pu;
    valid8_loss = ~isnan(s8_loss);
    if any(valid8_loss)
        plot(s8_ne(valid8_loss), s8_loss(valid8_loss), '--s', 'Color',c_red, ...
            'LineWidth',lw, 'MarkerSize',ms, 'MarkerFaceColor',c_red, ...
            'DisplayName','ES-1 Joint (Stage 8)');
    end

    yline(loss_nosupport, '--', 'Color',c_gray, 'LineWidth',1.2, ...
        'Label','No support', 'LabelHorizontalAlignment','left', 'FontSize',8);

    xlabel('N_e (ES budget)', 'FontSize',11);
    ylabel('Total 24h Loss (pu)', 'FontSize',11);
    title('Loss at Minimum Joint Configuration', 'FontSize',11, 'FontWeight','bold');
    legend('Location','northeast', 'FontSize',9);
    xlim([-1, 34]);

    sgtitle({'Joint ES + STATCOM + ESS: Basic ES (Stage 5) vs ES-1 (Stage 8)', ...
        'IEEE 33-Bus | \rho=0.70 | u_{min}=0.20'}, ...
        'FontSize',12, 'FontWeight','bold');

    saveas(fig5, fullfile(out_figs, 'fig5_joint_s5_vs_s8.png'));
    saveas(fig5, fullfile(out_figs, 'fig5_joint_s5_vs_s8.fig'));
    fprintf('  Saved: fig5_joint_s5_vs_s8\n');
else
    fprintf('  Figure 5 skipped (run Stage 8 first).\n');
end

% =========================================================================
%  FIGURE 6: COMPREHENSIVE SUMMARY COMPARISON TABLE (text figure)
% =========================================================================
fprintf('Generating Figure 6: Summary comparison...\n');

fig6 = figure('Visible','off','Position',[50 50 1100 500]);
ax6 = axes('Parent',fig6, 'Visible','off');
axis(ax6, 'off');

% Table data
headers = {'Configuration', 'N_e', 'N_s (STATCOM)', 'N_b (ESS)', ...
    'Total Devices', 'V_{min} (pu)', 'Loss (pu)', 'Feasible?'};

rows_data = {
    'No Support (S1)',            '0',  '0',  '0',  '0',   '0.8308', '0.6711', 'No';
    'Qg-only (S1)',               '0',  '—',  '—',  '—',   '0.9500', '0.5140', 'Yes';
    'STATCOM-only (S2)',          '0',  '7',  '0',  '7',   '0.9500', '0.5325', 'Yes';
    'ESS-only (S3)',              '0',  '0',  '3',  '3',   '0.9500', '0.4361', 'Yes';
    'Basic ES N32 alone (S1)',    '32', '0',  '0',  '32',  '0.9324', '0.1180', 'No';
    'Basic ES+STATCOM min (S4)',  '32', '2',  '0',  '34',  '0.9500', '0.0786', 'Yes';
    'Basic ES+ESS min (S4)',      '32', '0',  '1',  '33',  '0.9543', '0.0826', 'Yes';
    'Basic ES+Joint min (S5)',    '32', '0',  '1',  '33',  '0.9543', '0.0826', 'Yes';
    'ES-1 alone min (S6)',        '4',  '0',  '0',  '4',   '0.9500', '0.3806', 'Yes';
    'ES-1 alone N15* (S6)',       '15', '0',  '0',  '15',  '0.9500', '0.1286', 'Yes';
    'ES-1+STATCOM min (S7)',      '4',  '0',  '0',  '4',   '0.9500', '0.3848', 'Yes';
    'ES-1+ESS min (S7)',          '4',  '0',  '0',  '4',   '0.9500', '0.3848', 'Yes';
};

% Build cell array including header
tbl = [headers; rows_data];
n_rows = size(tbl,1);
n_cols = size(tbl,2);

% Draw as text table
col_x = linspace(0.01, 0.99, n_cols+1);
col_w = diff(col_x);
row_h = 0.80 / n_rows;
row_y = linspace(0.93, 0.13, n_rows);

for r = 1:n_rows
    for c = 1:n_cols
        x_pos = col_x(c) + 0.005;
        y_pos = row_y(r);

        if r == 1
            fw = 'bold'; fs = 9; fc = [0 0 0];
        elseif contains(tbl{r,1},'ES-1') && ~contains(tbl{r,1},'Basic')
            fw = 'normal'; fs = 9; fc = c_red;
        elseif contains(tbl{r,1},'No Support') || strcmp(tbl{r,end},'No')
            fw = 'normal'; fs = 9; fc = [0.5 0.5 0.5];
        else
            fw = 'normal'; fs = 9; fc = [0 0 0];
        end

        text(x_pos, y_pos, tbl{r,c}, 'Units','normalized', ...
            'FontSize',fs, 'FontWeight',fw, 'Color',fc, ...
            'HorizontalAlignment','left', 'VerticalAlignment','middle', ...
            'Parent',ax6);
    end
end

% Header separator
annotation(fig6, 'line', [0.01 0.99], [0.87 0.87], 'LineWidth',1.5);

title(ax6, {'Comprehensive Result Comparison — IEEE 33-Bus ES Framework', ...
    '\rho=0.70 | u_{min}=0.20 | EV scale=1.80 | * ES-1 saturates at N_{e}=15'}, ...
    'FontSize',11, 'FontWeight','bold', 'Visible','on');

saveas(fig6, fullfile(out_figs, 'fig6_summary_comparison.png'));
saveas(fig6, fullfile(out_figs, 'fig6_summary_comparison.fig'));
fprintf('  Saved: fig6_summary_comparison\n');

%% FINAL REPORT
fprintf('\n');
fprintf('=========================================================\n');
fprintf('  STAGE 9 COMPLETE\n');
fprintf('  Figures saved to: 04_results/es_framework/figures/stage9/\n');
fprintf('\n');
fprintf('  fig1_pareto_substitution : S4 vs S7 Pareto curves\n');
fprintf('  fig2_loss_vs_ne          : Loss reduction vs N_e\n');
fprintf('  fig3_es1_standalone      : ES-1 Vmin and loss threshold\n');
fprintf('  fig4_device_savings      : Stacked device count bar chart\n');
if has_stage8
fprintf('  fig5_joint_s5_vs_s8     : Joint comparison S5 vs S8\n');
else
fprintf('  fig5_joint_s5_vs_s8     : SKIPPED (run Stage 8 first)\n');
end
fprintf('  fig6_summary_comparison  : Full comparison table\n');
fprintf('=========================================================\n\n');
