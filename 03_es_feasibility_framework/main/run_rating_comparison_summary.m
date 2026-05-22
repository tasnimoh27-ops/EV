%% run_rating_comparison_summary.m
% TOTAL INSTALLED RATING COMPARISON
%
% Purpose:
%   Lightweight post-processing script to answer the question:
%   "Have you compared the total kVA/kVAr rating of STATCOMs, ESSs and ESs?"
%
% This script does NOT rerun optimisation and does NOT modify solver results.
% It summarises the final reported cases using the same 10 MVA base and the
% same per-device reactive limits used in the existing study.
%
% Interpretation notes:
%   - STATCOM and ES-1 can be compared by installed MVAr because both have
%     explicit reactive-power limits in the model.
%   - Standard ES is not an independent reactive source. It is reported as a
%     controllable non-critical-load resource, not as MVAr injection.
%   - ESS requires both inverter MVA and battery MWh normalisation. If the
%     exact rating is not explicitly extracted here, it is marked accordingly.
%
% Output:
%   04_results/es_framework/tables/table_total_rating_comparison.csv
%   04_results/es_framework/figures/fig_total_rating_comparison.png

clear; clc; close all;

%% Paths
script_dir = fileparts(mfilename('fullpath'));
framework_root = fileparts(script_dir);
repo_root = fileparts(framework_root);

out_tabs = fullfile(repo_root, '04_results', 'es_framework', 'tables');
out_figs = fullfile(repo_root, '04_results', 'es_framework', 'figures');
if ~exist(out_tabs, 'dir'), mkdir(out_tabs); end
if ~exist(out_figs, 'dir'), mkdir(out_figs); end

%% Base assumptions from the existing study
Sbase_MVA = 10.0;
Qs_max_pu = 0.10;      % STATCOM per-device reactive limit
Qes_max_pu = 0.10;     % ES-1 per-device reactive limit

STATCOM_per_device_MVAr = Qs_max_pu * Sbase_MVA;
ES1_per_device_MVAr = Qes_max_pu * Sbase_MVA;

%% Final reported cases
% These values are taken from the final reported study results.
% The purpose is a concise installed-rating comparison, not a rerun.
CaseName = {};
Technology = {};
MinimumDevices = {};
DeviceRole = {};
PerDeviceRating_pu = [];
PerDeviceRating_MVA_or_MVAr = {};
TotalInstalledRating_pu = [];
TotalInstalledRating_MVA_or_MVAr = {};
EnergyCapacity_MWh = {};
Vmin_pu = [];
Vmax_pu = [];
TotalLoss_pu = [];
VoltageFeasible = {};
ComparisonBasis = {};
Notes = {};

addRow('No support', 'None', '0', ...
    'No voltage support device', NaN, 'N/A', NaN, 'N/A', 'N/A', ...
    0.8308, NaN, 0.6710, 'No', ...
    'Reference stressed feeder', ...
    'Baseline case with no support device.');

addRow('STATCOM only', 'STATCOM', '7', ...
    'Reactive compensation', Qs_max_pu, sprintf('%.2f MVAr', STATCOM_per_device_MVAr), ...
    7*Qs_max_pu, sprintf('%.2f MVAr', 7*STATCOM_per_device_MVAr), 'N/A', ...
    0.9500, NaN, 0.5365, 'Yes', ...
    'Installed reactive capacity', ...
    'Reactive injection only; locations selected by VSI candidate screening and MISOCP placement.');

addRow('ESS only', 'ESS', '3', ...
    'Storage plus inverter support', NaN, 'Requires ESS inverter rating', ...
    NaN, 'Requires kVA/kWh normalisation', 'Requires battery energy rating', ...
    0.9500, NaN, 0.4337, 'Yes', ...
    'Inverter MVA plus energy MWh', ...
    'ESS should be compared using both inverter power rating and battery energy capacity.');

addRow('Standard ES only', 'Standard ES', '32', ...
    'Non-critical-load control', NaN, 'Not direct MVAr injection', ...
    NaN, 'Controllable load capacity', 'N/A', ...
    0.9324, NaN, 0.1180, 'No', ...
    'Controllable non-critical load', ...
    'Standard ES reduces load but has no independent reactive injection.');

addRow('Standard ES + STATCOM', 'Hybrid', '32 ES + 2 STATCOM', ...
    'Load control plus reactive compensation', Qs_max_pu, sprintf('%.2f MVAr per STATCOM', STATCOM_per_device_MVAr), ...
    2*Qs_max_pu, sprintf('%.2f MVAr STATCOM + ES load-control capacity', 2*STATCOM_per_device_MVAr), 'N/A', ...
    0.9500, NaN, 0.0786, 'Yes', ...
    'Hybrid support capacity', ...
    'Standard ES reduces STATCOM requirement from 7 to 2 but does not eliminate it.');

addRow('Standard ES + ESS', 'Hybrid', '32 ES + 1 ESS', ...
    'Load control plus storage/inverter', NaN, 'Requires ESS inverter rating', ...
    NaN, '1 ESS + ES load-control capacity', 'Requires battery energy rating', ...
    0.9544, NaN, 0.0826, 'Yes', ...
    'Hybrid support capacity', ...
    'Standard ES reduces ESS requirement from 3 to 1 but does not eliminate it.');

addRow('ES-1 only', 'ES-1', '4', ...
    'Load control plus independent reactive support', Qes_max_pu, sprintf('%.2f MVAr', ES1_per_device_MVAr), ...
    4*Qes_max_pu, sprintf('%.2f MVAr', 4*ES1_per_device_MVAr), 'N/A', ...
    0.9500, NaN, 0.3806, 'Yes', ...
    'Equivalent reactive support capacity', ...
    'Planning-level ES-1 model with independent Q_es reactive support.');

addRow('PV + ES-1', 'ES-1', '8', ...
    'Reactive-capable ES under PV penetration', Qes_max_pu, sprintf('%.2f MVAr', ES1_per_device_MVAr), ...
    8*Qes_max_pu, sprintf('%.2f MVAr', 8*ES1_per_device_MVAr), 'N/A', ...
    0.9500, 1.0445, 0.44756, 'Yes', ...
    'Equivalent reactive support capacity', ...
    'Stage 10 PV case; feasible up to 200%% PV scale in the tested sweep.');

%% Build and save table
T = table(CaseName', Technology', MinimumDevices', DeviceRole', ...
    PerDeviceRating_pu', PerDeviceRating_MVA_or_MVAr', ...
    TotalInstalledRating_pu', TotalInstalledRating_MVA_or_MVAr', ...
    EnergyCapacity_MWh', Vmin_pu', Vmax_pu', TotalLoss_pu', ...
    VoltageFeasible', ComparisonBasis', Notes', ...
    'VariableNames', {'CaseName','Technology','MinimumDevices','DeviceRole', ...
    'PerDeviceRating_pu','PerDeviceRating_MVA_or_MVAr', ...
    'TotalInstalledRating_pu','TotalInstalledRating_MVA_or_MVAr', ...
    'EnergyCapacity_MWh','Vmin_pu','Vmax_pu','TotalLoss_pu', ...
    'VoltageFeasible','ComparisonBasis','Notes'});

out_csv = fullfile(out_tabs, 'table_total_rating_comparison.csv');
writetable(T, out_csv);

%% Figure: only directly comparable reactive ratings
fig = figure('Color','w','Position',[100 100 850 480]);
labels = categorical({'STATCOM only','ES-1 only','PV + ES-1'});
ratings = [7.0, 4.0, 8.0];
bar(labels, ratings);
ylabel('Total installed reactive rating (MVAr)');
title('Total Installed Reactive Rating Comparison');
grid on;
text(1:numel(ratings), ratings + 0.15, compose('%.1f MVAr', ratings), ...
    'HorizontalAlignment','center', 'FontSize', 10);

note_text = {'Note: Standard ES is not plotted because it is load-control capacity, not MVAr injection.', ...
             'ESS is not plotted unless inverter MVA and energy MWh are explicitly normalised.'};
annotation('textbox', [0.10 0.01 0.85 0.10], 'String', note_text, ...
    'FitBoxToText','on', 'EdgeColor','none', 'FontSize', 9);

out_png = fullfile(out_figs, 'fig_total_rating_comparison.png');
try
    exportgraphics(fig, out_png, 'Resolution', 300);
catch
    saveas(fig, out_png);
end
close(fig);

%% Command window summary
fprintf('\n============================================================\n');
fprintf(' TOTAL INSTALLED RATING COMPARISON COMPLETE\n');
fprintf('============================================================\n');
fprintf(' System base: %.1f MVA\n', Sbase_MVA);
fprintf(' STATCOM: 7 devices x %.2f pu = %.1f MVAr total\n', Qs_max_pu, 7*STATCOM_per_device_MVAr);
fprintf(' ES-1 only: 4 devices x %.2f pu = %.1f MVAr total\n', Qes_max_pu, 4*ES1_per_device_MVAr);
fprintf(' PV + ES-1: 8 devices x %.2f pu = %.1f MVAr total\n', Qes_max_pu, 8*ES1_per_device_MVAr);
fprintf(' Standard ES: reported as controllable load capacity, not MVAr injection.\n');
fprintf(' ESS: requires inverter MVA plus battery MWh normalisation.\n');
fprintf('\n Saved table:  %s\n', out_csv);
fprintf(' Saved figure: %s\n', out_png);
fprintf('============================================================\n\n');

%% Local helper
function addRow(caseName, tech, minDevices, role, perPu, perText, totalPu, totalText, energyText, vmin, vmax, loss, feas, basis, note)
    assignin('caller', 'CaseName', [evalin('caller','CaseName'), {caseName}]);
    assignin('caller', 'Technology', [evalin('caller','Technology'), {tech}]);
    assignin('caller', 'MinimumDevices', [evalin('caller','MinimumDevices'), {minDevices}]);
    assignin('caller', 'DeviceRole', [evalin('caller','DeviceRole'), {role}]);
    assignin('caller', 'PerDeviceRating_pu', [evalin('caller','PerDeviceRating_pu'), perPu]);
    assignin('caller', 'PerDeviceRating_MVA_or_MVAr', [evalin('caller','PerDeviceRating_MVA_or_MVAr'), {perText}]);
    assignin('caller', 'TotalInstalledRating_pu', [evalin('caller','TotalInstalledRating_pu'), totalPu]);
    assignin('caller', 'TotalInstalledRating_MVA_or_MVAr', [evalin('caller','TotalInstalledRating_MVA_or_MVAr'), {totalText}]);
    assignin('caller', 'EnergyCapacity_MWh', [evalin('caller','EnergyCapacity_MWh'), {energyText}]);
    assignin('caller', 'Vmin_pu', [evalin('caller','Vmin_pu'), vmin]);
    assignin('caller', 'Vmax_pu', [evalin('caller','Vmax_pu'), vmax]);
    assignin('caller', 'TotalLoss_pu', [evalin('caller','TotalLoss_pu'), loss]);
    assignin('caller', 'VoltageFeasible', [evalin('caller','VoltageFeasible'), {feas}]);
    assignin('caller', 'ComparisonBasis', [evalin('caller','ComparisonBasis'), {basis}]);
    assignin('caller', 'Notes', [evalin('caller','Notes'), {note}]);
end
