%% run_ess_and_device_composition_analysis.m
% MASTER RUNNER FOR ESS RATING SENSITIVITY AND DEVICE COMPOSITION ANALYSIS
%
% Orchestrates the complete ESS installed-rating analysis pipeline:
% 1. Run ESS rating sensitivity study (tests 4 ESS unit sizes)
% 2. Generate ESS sensitivity tables and figures
% 3. Update and run device composition analysis using base ESS results
% 4. Print final summary
%
% Single command execution:
%   cd 03_es_feasibility_framework/main
%   run_ess_and_device_composition_analysis
%
% Output:
%   All ESS sensitivity tables and figures in 04_results/es_framework/
%   Updated device composition table with explicit ESS MVA/MWh values
%   Final summary in command window
%
% Requirements: MATLAB R2020a+, YALMIP, Gurobi
% Run from: 03_es_feasibility_framework/main/

clear; clc; close all;

fprintf('\n');
fprintf('===================================================================\n');
fprintf('  MASTER RUNNER: ESS AND DEVICE COMPOSITION ANALYSIS\n');
fprintf('  IEEE 33-Bus Feeder | scale=1.80\n');
fprintf('===================================================================\n\n');

script_dir = fileparts(mfilename('fullpath'));

fprintf('[1/3] Running ESS installed-rating sensitivity analysis...\n\n');
try
    run_ess_rating_sensitivity;
    fprintf('\n✓ ESS sensitivity analysis complete.\n');
catch ME
    fprintf('\n✗ ESS sensitivity analysis failed:\n%s\n', ME.message);
    rethrow(ME);
end

fprintf('\n[2/3] Running device composition analysis...\n\n');
try
    run_device_composition_analysis;
    fprintf('\n✓ Device composition analysis complete.\n');
catch ME
    fprintf('\n✗ Device composition analysis failed:\n%s\n', ME.message);
    rethrow(ME);
end

fprintf('\n[3/3] Analysis pipeline complete.\n\n');

fprintf('===================================================================\n');
fprintf('  ANALYSIS SUMMARY\n');
fprintf('===================================================================\n\n');

fprintf('ESS Sensitivity Outputs:\n');
fprintf('  ✓ table_ess_rating_sensitivity.csv\n');
fprintf('  ✓ table_ess_rating_minimum_count.csv\n');
fprintf('  ✓ fig_ess_min_count_vs_rating.png\n');
fprintf('  ✓ fig_ess_total_mva_mwh_vs_rating.png\n');
fprintf('  ✓ fig_ess_loss_vs_rating.png\n');
fprintf('  ✓ fig_ess_vmin_vs_rating.png\n\n');

fprintf('Device Composition Outputs:\n');
fprintf('  ✓ table_device_composition_analysis.csv\n');
fprintf('  ✓ fig_device_composition_feasibility.png\n');
fprintf('  ✓ fig_device_composition_loss.png\n');
fprintf('  ✓ fig_device_composition_device_count.png\n');
fprintf('  ✓ fig_device_composition_installed_capacity.png\n\n');

fprintf('All outputs saved to: 04_results/es_framework/\n\n');
fprintf('===================================================================\n\n');
