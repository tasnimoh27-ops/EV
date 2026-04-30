%% main_run_es_research.m
% MASTER PIPELINE — Stress-Adaptive ES Placement Research
%
% Runs all research modules in sequence. Toggle flags to skip modules.
%
% Modules:
%   M01  Base OPF without ES (feasibility baseline)
%   M02  Stress scan (Vmin vs load multiplier)
%   M08  VIS ranking and candidate bus selection
%   M09  Greedy ES placement
%   M10  Optimized MISOCP ES placement (main novel module)
%   M11  ES budget sensitivity
%   M12  NCL share sensitivity
%   M13  NCL power factor sensitivity
%   M14  Benchmark comparison
%
% Requirements: YALMIP + Gurobi
%
% Usage:
%   1. Open MATLAB in the project root directory
%   2. Run: main_run_es_research
%   3. Results saved to results/tables/ and results/figures/

clear; clc; close all;

% =========================================================================
%  MODULE FLAGS — set to false to skip
% =========================================================================
run_base_case          = true;
run_stress_scan        = true;
run_vis_ranking        = true;
run_greedy_placement   = true;
run_optimized_placement= true;
run_budget_sensitivity = true;
run_ncl_share_sens     = true;
run_ncl_pf_sens        = true;
run_benchmark          = true;

% =========================================================================
%  SETUP
% =========================================================================
addpath(genpath('./src'));

if ~exist('./results/tables','dir'), mkdir('./results/tables'); end
if ~exist('./results/figures','dir'), mkdir('./results/figures'); end
if ~exist('./results/mat_files','dir'), mkdir('./results/mat_files'); end

fprintf('\n');
fprintf('=========================================================\n');
fprintf('  STRESS-ADAPTIVE ES PLACEMENT RESEARCH PIPELINE\n');
fprintf('  IEEE 33-Bus Distribution Network\n');
fprintf('=========================================================\n\n');

t_start = tic;

% =========================================================================
%  M01 — BASE OPF
% =========================================================================
if run_base_case
    fprintf('\n--- Module 1: Base OPF ---\n');
    run('src/network/run_base_opf.m');
end

% =========================================================================
%  M02 — STRESS SCAN
% =========================================================================
if run_stress_scan
    fprintf('\n--- Module 2: Stress Scan ---\n');
    run('src/studies/run_stress_scan.m');
end

% =========================================================================
%  M08 — VIS RANKING (standalone output)
% =========================================================================
if run_vis_ranking
    fprintf('\n--- Module 8: VIS Ranking ---\n');
    caseDir   = './mp_export_case33bw';
    branchCsv = fullfile(caseDir,'branch.csv');
    loadsCsv  = fullfile(caseDir,'loads_base.csv');
    topo  = build_distflow_topology_from_branch_csv(branchCsv, 1);
    loads = build_24h_load_profile_from_csv(loadsCsv, 'system', true, false);

    alpha_ncl = 0.30;
    vis = calculate_voltage_impact_score(topo, loads, alpha_ncl);

    nb = topo.nb;
    Bus    = (1:nb)';
    Score  = vis.score;
    Rank   = zeros(nb,1);
    Rank(vis.rank) = 1:nb;
    SumR   = vis.sum_R_path;
    SumX   = vis.sum_X_path;
    PNCL   = vis.P_NCL_mean;
    QNCL   = vis.Q_NCL_mean;

    T_vis = table(Bus, Score, Rank, SumR, SumX, PNCL, QNCL, ...
        'VariableNames',{'Bus','VIS_Score','Rank','SumR_path','SumX_path', ...
                         'P_NCL_mean','Q_NCL_mean'});
    writetable(T_vis,'./results/tables/voltage_impact_ranking.csv');

    fig_vis = figure('Visible','off');
    bar(Bus, Score, 'FaceColor',[0.4 0.6 0.3]);
    xlabel('Bus Index'); ylabel('Voltage Impact Score (VIS)');
    title('Voltage Impact Score — ES Candidate Ranking');
    grid on;
    saveas(fig_vis,'./results/figures/voltage_impact_score_bar.png');
    close(fig_vis);
    fprintf('  VIS ranking saved.\n');
end

% =========================================================================
%  M09 — GREEDY
% =========================================================================
if run_greedy_placement
    fprintf('\n--- Module 9: Greedy Placement ---\n');
    run('src/es/run_greedy_es_placement.m');
end

% =========================================================================
%  M10 — OPTIMIZED MISOCP
% =========================================================================
if run_optimized_placement
    fprintf('\n--- Module 10: Optimized MISOCP Placement ---\n');
    run('src/es/run_optimized_es_placement.m');
end

% =========================================================================
%  M11 — BUDGET SENSITIVITY
% =========================================================================
if run_budget_sensitivity
    fprintf('\n--- Module 11: Budget Sensitivity ---\n');
    run('src/studies/run_es_budget_sensitivity.m');
end

% =========================================================================
%  M12 — NCL SHARE SENSITIVITY
% =========================================================================
if run_ncl_share_sens
    fprintf('\n--- Module 12: NCL Share Sensitivity ---\n');
    run('src/studies/run_ncl_share_sensitivity.m');
end

% =========================================================================
%  M13 — NCL PF SENSITIVITY
% =========================================================================
if run_ncl_pf_sens
    fprintf('\n--- Module 13: NCL PF Sensitivity ---\n');
    run('src/studies/run_ncl_pf_sensitivity.m');
end

% =========================================================================
%  M14 — BENCHMARK
% =========================================================================
if run_benchmark
    fprintf('\n--- Module 14: Benchmark Comparison ---\n');
    run('src/studies/run_benchmark_comparison.m');
end

% =========================================================================
%  SUMMARY
% =========================================================================
t_elapsed = toc(t_start);
fprintf('\n=========================================================\n');
fprintf('  PIPELINE COMPLETE  (%.1f min)\n', t_elapsed/60);
fprintf('=========================================================\n');
fprintf('\nOutputs:\n');
fprintf('  Tables  -> results/tables/\n');
fprintf('  Figures -> results/figures/\n');
fprintf('  Mat     -> results/mat_files/\n\n');

% Print key result files
tbl_files = dir('./results/tables/*.csv');
for f = tbl_files'
    fprintf('  %s\n', f.name);
end
