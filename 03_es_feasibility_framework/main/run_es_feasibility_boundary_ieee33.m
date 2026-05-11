%% run_es_feasibility_boundary_ieee33.m
% MASTER RUNNER — ES Feasibility Boundary Framework
% IEEE 33-Bus EV-Stressed Distribution Feeder
%
% Paper title: "Feasibility Boundary of Electric Spring Deployment for
%               Voltage Recovery in EV-Stressed Radial Distribution Feeders"
%
% Run this script from the ES_Feasibility_Boundary_IEEE33/main/ directory,
% or from the repo root.  All paths are computed relative to this file.
%
% Requirements: MATLAB R2020a+, YALMIP, Gurobi
%
% Toggle section flags below to skip heavy sweeps during development.
%
% Results saved to:
%   ES_Feasibility_Boundary_IEEE33/results/es_feasibility_boundary_ieee33/

clear; clc; close all;

%% =========================================================================
%  SECTION FLAGS — set false to skip
%% =========================================================================
run_A1_topology      = true;
run_A2_load_profile  = true;
run_A3_baseline      = true;
run_A4_stress_sweep  = true;
run_A5_qg_reference  = true;

run_B2_weak_bus      = true;
run_B3_p1_p5_scan    = true;   % ~70 cases, ~60-90 min

run_C1_vsi           = true;
run_C2_ranking       = true;
run_C3_heuristics    = true;   % ~moderate runtime

run_D1_misocp        = true;
run_D2_budget_sweep  = true;   % heavy: ~hundreds of cases
run_D3_min_count     = true;
run_D4_misocp_vs_h   = true;
run_D5_infeasibility = true;

run_E1_hybrid        = true;   % heavy sweep
run_E2_hybrid_sweep  = true;

run_F1_scenarios     = true;
run_F2_robustness    = true;
run_F3_risk          = true;

run_G1_final_compare = true;
run_G2_summary_figs  = true;

%% =========================================================================
%  PATH SETUP
%% =========================================================================
script_dir = fileparts(mfilename('fullpath'));          % .../main/
new_root   = fileparts(script_dir);                     % .../03_es_feasibility_framework/
repo_root  = fileparts(new_root);                       % .../EV Research code/

addpath(genpath(fullfile(new_root, 'functions')));
addpath(genpath(fullfile(new_root, 'plotting')));
addpath(genpath(fullfile(new_root, 'data')));
addpath(genpath(fullfile(repo_root, '02_baseline_modules', 'shared')));

out_base  = fullfile(repo_root, '04_results', 'es_framework');
out_tabs  = fullfile(out_base, 'tables');
out_figs  = fullfile(out_base, 'figures');
out_raw   = fullfile(out_base, 'raw_outputs');

for d = {out_tabs, out_figs, out_raw}
    if ~exist(d{1},'dir'), mkdir(d{1}); end
end

fprintf('\n');
fprintf('======================================================\n');
fprintf('  ES FEASIBILITY BOUNDARY — IEEE 33-BUS FRAMEWORK\n');
fprintf('  EV-Stressed Radial Distribution Feeder Study\n');
fprintf('======================================================\n\n');

t_total = tic;

% Gurobi solver settings (used by most SOCP/MISOCP routines)
ops = sdpsettings('solver','gurobi','verbose',0);
ops.gurobi.TimeLimit = 300;

%% =========================================================================
%  PART A — BASELINE
%% =========================================================================

%% A1: Topology verification
if run_A1_topology
    fprintf('\n--- A1: IEEE 33-Bus Topology Verification ---\n');
    [topo, loads_ev] = build_ieee33_network(repo_root, 1.80);
    topo_check = verify_radial_topology(topo);
    T_topo = struct2table(struct( ...
        'N_Bus',topo_check.nb, 'N_Branch',topo_check.nl, ...
        'Slack_Bus',topo_check.root, 'All_Connected',double(topo_check.checks.all_connected), ...
        'Is_Tree',double(topo_check.checks.is_tree), 'All_Pass',double(topo_check.all_pass)));
    writetable(T_topo, fullfile(out_tabs,'table_topology_verification.csv'));
    fprintf('  Saved topology verification.\n');
    plot_ieee33_topology(topo, [], fullfile(out_figs,'fig_ieee33_topology.png'));
end

%% A2: Load profile
if run_A2_load_profile
    fprintf('\n--- A2: 24-Hour Load Profile ---\n');
    prof = load_profile_24h(1.80);
    T_prof = table(prof.hours, prof.mult, 'VariableNames',{'Hour','Multiplier'});
    writetable(T_prof, fullfile(out_tabs,'table_load_profile.csv'));
    fh = figure('Visible','off');
    plot(prof.hours, prof.mult,'-o','LineWidth',1.4,'MarkerSize',5);
    grid on; xlabel('Hour'); ylabel('Load Multiplier');
    title('24-Hour Load Profile (EV Peak = 1.80×)');
    yline(0.95,'--r','V_{min} ref');
    saveas(fh, fullfile(out_figs,'fig_load_profile_24h.png')); close(fh);
    fprintf('  Load profile saved.\n');
end

%% A3: No-support DistFlow baseline
if run_A3_baseline
    fprintf('\n--- A3: No-Support DistFlow Baseline ---\n');
    [topo, loads_ev] = build_ieee33_network(repo_root, 1.80);
    r_base = run_distflow_baseline(topo, loads_ev);

    T_base = table((1:24)', r_base.Vmin_t, r_base.VminBus_t, r_base.loss_t, r_base.n_viol_t, ...
        'VariableNames',{'Hour','Vmin_pu','VminBus','Loss_pu','N_Violations'});
    writetable(T_base, fullfile(out_tabs,'table_no_support_baseline.csv'));

    ph = r_base.worst_hour;
    plot_voltage_profile_peak({r_base.V_all(:,ph)}, {'No Support'}, ph, ...
        fullfile(out_figs,'fig_no_support_voltage_peak.png'));
    plot_min_voltage_24h({r_base.Vmin_t}, {'No Support'}, ...
        fullfile(out_figs,'fig_no_support_min_voltage_24h.png'));

    fh=figure('Visible','off'); bar(1:24, r_base.n_viol_t,0.7);
    grid on; xlabel('Hour'); ylabel('Violating bus count');
    title('Voltage-Violating Buses per Hour (No Support)');
    saveas(fh,fullfile(out_figs,'fig_no_support_violating_bus_count.png')); close(fh);
    fprintf('  Baseline: Vmin=%.4f at bus %d (hour %d)\n', ...
        r_base.Vmin_24h, r_base.worst_bus, r_base.worst_hour);
end

%% A4: Load multiplier stress sweep
if run_A4_stress_sweep
    fprintf('\n--- A4: Load Multiplier Stress Sweep ---\n');
    mult_vals = [1.0, 1.2, 1.4, 1.6, 1.8];
    sweep_rows = {};
    for m = mult_vals
        [~, loads_m] = build_ieee33_network(repo_root, m);
        r_m = run_distflow_baseline(topo, loads_m);
        sweep_rows{end+1} = {m, r_m.Vmin_24h, r_m.worst_bus, ...
            r_m.total_loss, r_m.n_viol_peak};
    end
    T_sweep = cell2table(vertcat(sweep_rows{:}),'VariableNames', ...
        {'Multiplier','Vmin_pu','WorstBus','TotalLoss_pu','N_Viol_Peak'});
    writetable(T_sweep, fullfile(out_tabs,'table_load_multiplier_sweep.csv'));
    plot_load_multiplier_sweep(T_sweep, fullfile(out_figs,'fig_load_multiplier_sweep.png'));
    fprintf('  Stress sweep saved.\n');
end

%% A5: Qg-only SOCP reference
if run_A5_qg_reference
    fprintf('\n--- A5: Qg-Only SOCP Reference Benchmark ---\n');
    [topo, loads_ev] = build_ieee33_network(repo_root, 1.80);
    T = 24; price = ones(T,1); price(1:6)=0.6; price(7:16)=1.0; price(17:21)=1.8; price(22:24)=0.9;
    p_qg.Vmin=0.95; p_qg.Vmax=1.05; p_qg.price=price;
    p_qg.Qg_max_pu=0.10; p_qg.soft_voltage=false;
    r_qg = solve_socp_opf_qg(topo, loads_ev, p_qg);

    T_qg = table((1:T)', r_qg.Vmin_t, r_qg.VminBus_t, r_qg.loss_t, ...
        'VariableNames',{'Hour','Vmin_pu','VminBus','Loss_pu'});
    writetable(T_qg, fullfile(out_tabs,'table_qg_reference.csv'));
    if r_qg.feasible
        ph_qg = r_qg.worst_hour;
        plot_voltage_profile_peak({r_qg.V_val(:,ph_qg)}, {'Qg Only'}, ph_qg, ...
            fullfile(out_figs,'fig_qg_voltage_peak.png'));
        plot_min_voltage_24h({r_qg.Vmin_t},{'Qg Only'}, ...
            fullfile(out_figs,'fig_qg_min_voltage_24h.png'));
    end
    fprintf('  Qg reference saved.\n');
end

%% =========================================================================
%  PART B — P1-P5 FEASIBILITY SCAN
%% =========================================================================

if run_B2_weak_bus || run_B3_p1_p5_scan
    if ~exist('topo','var') || ~exist('loads_ev','var')
        [topo, loads_ev] = build_ieee33_network(repo_root, 1.80);
    end
end

%% B2: Weak-bus placement
if run_B2_weak_bus
    fprintf('\n--- B2: Weak-Bus ES Placement ---\n');
    wb_rows = {};
    weak_sets = {[18,33],'WB2'; [17,18,32,33],'WB4'};
    for ip=1:size(weak_sets,1)
        buses = weak_sets{ip,1}; pname = weak_sets{ip,2};
        for rho=[0.30,0.50,0.60,0.70]
            for u_min=[0.00,0.20]
                r=solve_es_fixed_placement(topo,loads_ev,buses,rho,u_min,ops,[pname '_r' num2str(rho*100,'%.0f')]);
                if r.feasible
                    Vm=min(r.Vmin_t); Lo=r.total_loss; Mc=r.mean_curtailment;
                    wb=r.VminBus_t(r.worst_hour);
                else
                    Vm=NaN; Lo=NaN; Mc=NaN; wb=NaN;
                end
                wb_rows{end+1}={pname,mat2str(buses),numel(buses),rho,u_min,...
                    double(r.feasible),Vm,wb,Lo,Mc,r.sol_code};
            end
        end
    end
    T_wb=cell2table(vertcat(wb_rows{:}),'VariableNames',{'PlacementName','Buses','N_ES','rho','u_min',...
        'Feasible','Vmin_pu','WorstBus','TotalLoss_pu','MeanCurt','SolCode'});
    writetable(T_wb,fullfile(out_tabs,'table_weak_bus_es_results.csv'));
    fprintf('  Weak-bus results saved.\n');
end

%% B3: P1-P5 feasibility scan
if run_B3_p1_p5_scan
    fprintf('\n--- B3: P1–P5 Feasibility Scan ---\n');
    ops_fast = sdpsettings('solver','gurobi','verbose',0);
    ops_fast.gurobi.TimeLimit = 90;
    T_p1p5 = run_p1_p5_feasibility_scan(topo, loads_ev, out_tabs, ops_fast);
    save(fullfile(out_raw,'p1p5_scan.mat'),'T_p1p5');

    plot_p1_p5_feasibility(T_p1p5, 0.00, fullfile(out_figs,'fig_p1_p5_feasibility_umin_0.png'));
    plot_p1_p5_feasibility(T_p1p5, 0.20, fullfile(out_figs,'fig_p1_p5_feasibility_umin_020.png'));
    plot_feasibility_heatmap(T_p1p5,'rho','u_min','Feasible', ...
        fullfile(out_figs,'fig_p1_p5_min_voltage_heatmap.png'), ...
        'P1–P5 Feasibility (any placement)');
    fprintf('  P1-P5 scan done.\n');
end

%% =========================================================================
%  PART C — VOLTAGE SENSITIVITY AND CANDIDATE RANKING
%% =========================================================================

if run_C1_vsi || run_C2_ranking || run_C3_heuristics
    if ~exist('topo','var'), [topo,loads_ev]=build_ieee33_network(repo_root,1.80); end
end

%% C1: VSI
if run_C1_vsi
    fprintf('\n--- C1: Voltage Sensitivity Index ---\n');
    vsi = compute_voltage_sensitivity_index(topo, loads_ev, 0.05, out_tabs);
    save(fullfile(out_raw,'vsi.mat'),'vsi');
    plot_voltage_sensitivity_bar(vsi, fullfile(out_figs,'fig_voltage_sensitivity_bar.png'));
    plot_candidate_bus_topology(topo, struct('score_combined',vsi.VSI_norm,...
        'rank_weak',vsi.rank,'rank_endfeed',vsi.rank,'rank_load',vsi.rank,...
        'rank_vsi',vsi.rank,'rank_combined',vsi.rank,'score_vsi',vsi.VSI_norm,...
        'score_load',zeros(topo.nb,1),'score_dist',zeros(topo.nb,1),...
        'V_peak',ones(topo.nb,1),'non_slack',setdiff(1:topo.nb,1)), ...
        fullfile(out_figs,'fig_ieee33_top_vsi_buses.png'));
    fprintf('  VSI done. Top bus: %d\n', vsi.rank(1));
end

%% C2: Candidate ranking
if run_C2_ranking
    fprintf('\n--- C2: Candidate Bus Ranking ---\n');
    if ~exist('vsi','var'), load(fullfile(out_raw,'vsi.mat')); end
    ranking = rank_es_candidates(topo, loads_ev, vsi);
    save(fullfile(out_raw,'ranking.mat'),'ranking');
    T_rank = table((1:topo.nb)', ranking.score_vsi, ranking.score_load, ...
        ranking.score_dist, ranking.score_combined, ...
        'VariableNames',{'Bus','VSI_norm','Load_norm','Dist_norm','Combined'});
    writetable(T_rank, fullfile(out_tabs,'table_candidate_rankings.csv'));
    plot_candidate_bus_topology(topo, ranking, ...
        fullfile(out_figs,'fig_candidate_bus_topology.png'));
    fprintf('  Ranking done.\n');
end

%% C3: Heuristic placement comparison
if run_C3_heuristics
    fprintf('\n--- C3: Heuristic Placement Comparison ---\n');
    if ~exist('ranking','var'), load(fullfile(out_raw,'ranking.mat')); end
    T_heur = compare_candidate_placement_sets(topo, loads_ev, ranking, out_tabs, ops);
    save(fullfile(out_raw,'heuristic_comparison.mat'),'T_heur');
    plot_placement_comparison_curve(T_heur,'Vmin_pu', ...
        fullfile(out_figs,'fig_heuristic_vmin_vs_es_count.png'),...
        'Heuristic Placement: V_{min} vs ES Count');
    plot_placement_comparison_curve(T_heur,'TotalLoss_pu', ...
        fullfile(out_figs,'fig_heuristic_loss_vs_es_count.png'),...
        'Heuristic Placement: Loss vs ES Count');
    fprintf('  Heuristic comparison done.\n');
end

%% =========================================================================
%  PART D — BUDGET-CONSTRAINED MISOCP
%% =========================================================================

if run_D1_misocp || run_D2_budget_sweep || run_D3_min_count
    if ~exist('topo','var'), [topo,loads_ev]=build_ieee33_network(repo_root,1.80); end
end

%% D1/D2: Budget sweep
if run_D2_budget_sweep
    fprintf('\n--- D2: ES Budget Sweep (MISOCP) ---\n');
    sweep_opts.N_ES_list  = [2,4,6,8,10,12,16,20,24,28,32];
    sweep_opts.rho_vals   = [0.30,0.40,0.50,0.60,0.70,0.80];
    sweep_opts.umin_vals  = [0.00,0.10,0.20,0.30];
    sweep_opts.time_limit = 300;
    T_sweep = run_es_budget_sweep(topo, loads_ev, out_tabs, sweep_opts);
    save(fullfile(out_raw,'budget_sweep.mat'),'T_sweep');
    plot_voltage_slack_vs_es_budget(T_sweep, fullfile(out_figs,'fig_voltage_slack_vs_es_budget.png'));
    fprintf('  Budget sweep done.\n');
end

%% D1: Quick single-case MISOCP (if sweep skipped)
if run_D1_misocp && ~run_D2_budget_sweep
    fprintf('\n--- D1: MISOCP Single Case (rho=0.70, u_min=0.20) ---\n');
    T = 24; price=ones(T,1); price(1:6)=0.6; price(7:16)=1.0; price(17:21)=1.8; price(22:24)=0.9;
    params_d1.rho=0.70; params_d1.u_min=0.20; params_d1.N_ES_max=32;
    params_d1.Vmin=0.95; params_d1.Vmax=1.05; params_d1.soft_voltage=true;
    params_d1.obj_mode='feasibility'; params_d1.price=price; params_d1.time_limit=300;
    r_miso = solve_es_budget_misocp(topo, loads_ev, params_d1);
    save(fullfile(out_raw,'misocp_single.mat'),'r_miso');
    plot_misocp_voltage_profile(r_miso, topo, fullfile(out_figs,'fig_misocp_voltage_profile_peak.png'));
end

%% D3: Minimum ES count
if run_D3_min_count
    fprintf('\n--- D3: Minimum ES Count ---\n');
    if ~exist('T_sweep','var')
        if exist(fullfile(out_raw,'budget_sweep.mat'),'file')
            load(fullfile(out_raw,'budget_sweep.mat'));
        else
            fprintf('  No sweep data — skip D3\n'); T_sweep = [];
        end
    end
    if ~isempty(T_sweep)
        [T_min, ~] = identify_minimum_es_count(T_sweep, out_tabs);
        save(fullfile(out_raw,'min_es_count.mat'),'T_min');
        plot_minimum_es_count_vs_rho(T_min, fullfile(out_figs,'fig_minimum_es_count_vs_rho.png'));
        plot_minimum_es_count_vs_umin(T_min, fullfile(out_figs,'fig_minimum_es_count_vs_umin.png'));
    end
end

%% D4: MISOCP vs heuristics
if run_D4_misocp_vs_h
    fprintf('\n--- D4: MISOCP vs Heuristics ---\n');
    if ~exist('ranking','var')
        if exist(fullfile(out_raw,'ranking.mat'),'file')
            load(fullfile(out_raw,'ranking.mat'));
        else
            vsi=compute_voltage_sensitivity_index(topo,loads_ev,0.05,[]);
            ranking=rank_es_candidates(topo,loads_ev,vsi);
        end
    end
    T_comp = compare_misocp_with_heuristics(topo, loads_ev, ranking, out_tabs, ops);
    save(fullfile(out_raw,'misocp_vs_heuristics.mat'),'T_comp');
    plot_misocp_vs_heuristics(T_comp, fullfile(out_figs,'fig_misocp_vs_heuristics.png'));
    fprintf('  MISOCP vs heuristics done.\n');
end

%% D5: Infeasibility diagnosis
if run_D5_infeasibility
    fprintf('\n--- D5: Infeasibility Diagnostics ---\n');
    if exist('T_sweep','var') && ~isempty(T_sweep)
        T_diag = diagnose_voltage_infeasibility(topo, loads_ev, T_sweep, out_tabs);
        save(fullfile(out_raw,'infeasibility_diag.mat'),'T_diag');
        if ~isempty(T_diag) && height(T_diag) > 0
            plot_voltage_slack_vs_es_budget(T_sweep, ...
                fullfile(out_figs,'fig_worst_voltage_deficit_vs_rho.png'));
        end
    else
        fprintf('  No sweep data — skip D5\n');
    end
end

%% =========================================================================
%  PART E — HYBRID ES + QG
%% =========================================================================

%% E2: Hybrid sweep
if run_E2_hybrid_sweep
    fprintf('\n--- E2: Hybrid ES+Qg Sweep ---\n');
    hybrid_opts.rho_vals  = [0.30,0.40,0.50,0.60,0.70];
    hybrid_opts.umin_vals = [0.00,0.20];
    hybrid_opts.N_ES_list = [4,8,12,16,20,24,28,32];
    hybrid_opts.Qg_fracs  = [0,0.25,0.50,0.75,1.00];
    hybrid_opts.time_limit = 300;
    T_hybrid = run_hybrid_es_qg_sweep(topo, loads_ev, out_tabs, hybrid_opts);
    save(fullfile(out_raw,'hybrid_sweep.mat'),'T_hybrid');
    plot_min_es_count_vs_qg_limit(T_hybrid, fullfile(out_figs,'fig_min_es_count_vs_qg_limit.png'));
    plot_curtailment_reduction_hybrid(T_hybrid, fullfile(out_figs,'fig_curtailment_reduction_hybrid.png'));
    plot_hybrid_cost_tradeoff(T_hybrid, fullfile(out_figs,'fig_hybrid_tradeoff.png'));
    fprintf('  Hybrid sweep done.\n');
end

%% E1: Single hybrid case comparison
if run_E1_hybrid && ~run_E2_hybrid_sweep
    fprintf('\n--- E1: Hybrid ES+Qg Single Case ---\n');
    T=24; price=ones(T,1); price(1:6)=0.6; price(7:16)=1.0; price(17:21)=1.8; price(22:24)=0.9;
    params_e1.rho=0.70; params_e1.u_min=0.20; params_e1.N_ES_max=16;
    params_e1.Qg_limit_frac=0.50; params_e1.price=price;
    params_e1.Vmin=0.95; params_e1.Vmax=1.05;
    params_e1.soft_voltage=true; params_e1.obj_mode='feasibility';
    params_e1.time_limit=300;
    r_hyb = solve_hybrid_es_qg_misocp(topo, loads_ev, params_e1);
    save(fullfile(out_raw,'hybrid_single.mat'),'r_hyb');
    if r_hyb.feasible
        ph_hyb = r_hyb.worst_hour;
        plot_hybrid_voltage_profiles({r_hyb.V_val(:,ph_hyb)},{'Hybrid ES+Qg'},ph_hyb,...
            fullfile(out_figs,'fig_hybrid_voltage_profiles.png'));
    end
end

%% =========================================================================
%  PART F — EV STRESS ROBUSTNESS
%% =========================================================================

%% F1: Generate EV stress scenarios
if run_F1_scenarios
    fprintf('\n--- F1: EV Stress Scenarios ---\n');
    scen_opts.n_stoch  = 0;     % set >0 for stochastic
    scen_opts.out_dir  = out_raw;
    [scenarios, loads_cell] = generate_aggregate_ev_stress_scenarios(...
        topo, repo_root, scen_opts);
    save(fullfile(out_raw,'ev_scenarios.mat'),'scenarios','loads_cell');
    fprintf('  Generated %d scenarios.\n', scenarios.n_total);
end

%% F2: Evaluate solutions under EV stress
if run_F2_robustness
    fprintf('\n--- F2: EV Stress Robustness Evaluation ---\n');
    if ~exist('scenarios','var'), load(fullfile(out_raw,'ev_scenarios.mat')); end
    if ~exist('ranking','var')
        if exist(fullfile(out_raw,'ranking.mat'),'file'), load(fullfile(out_raw,'ranking.mat'));
        else, vsi=compute_voltage_sensitivity_index(topo,loads_ev,0.05,[]);
              ranking=rank_es_candidates(topo,loads_ev,vsi); end
    end

    % Define solutions to test
    vsi_7 = ranking.rank_vsi(1:7)';
    solutions(1).name='C0_NoSupport';  solutions(1).es_buses=[];   solutions(1).rho=0.70; solutions(1).u_min=0.20; solutions(1).Qg_frac=0;
    solutions(2).name='C1_QgOnly';    solutions(2).es_buses=[];   solutions(2).rho=0.70; solutions(2).u_min=0.20; solutions(2).Qg_frac=0.50;
    solutions(3).name='C2_WeakBus';   solutions(3).es_buses=[18,33]; solutions(3).rho=0.70; solutions(3).u_min=0.20; solutions(3).Qg_frac=0;
    solutions(4).name='C3_VSI7';      solutions(4).es_buses=vsi_7; solutions(4).rho=0.70; solutions(4).u_min=0.20; solutions(4).Qg_frac=0;

    T_robust = evaluate_solution_under_ev_stress(topo, scenarios, loads_cell, solutions, out_tabs, ops);
    save(fullfile(out_raw,'robustness.mat'),'T_robust');
    fprintf('  Robustness evaluation done.\n');
end

%% F3: Risk metrics
if run_F3_risk
    fprintf('\n--- F3: Voltage Risk Metrics ---\n');
    if ~exist('T_robust','var')
        if exist(fullfile(out_raw,'robustness.mat'),'file')
            load(fullfile(out_raw,'robustness.mat'));
        else
            fprintf('  No robustness data — skip F3\n'); T_robust = [];
        end
    end
    if ~isempty(T_robust)
        risk_table = compute_voltage_risk_metrics(T_robust, out_tabs);
        save(fullfile(out_raw,'risk_metrics.mat'),'risk_table');
        plot_cvar_voltage_risk_vs_es_count(risk_table, ...
            fullfile(out_figs,'fig_cvar_voltage_risk_vs_es_count.png'));
        plot_feasibility_probability_vs_rho(risk_table, T_robust, ...
            fullfile(out_figs,'fig_feasibility_probability_vs_rho.png'));
    end
end

%% =========================================================================
%  PART G — FINAL COMPARISON
%% =========================================================================

%% G1: Final case comparison
if run_G1_final_compare
    fprintf('\n--- G1: Final Case Comparison ---\n');
    final_table = compare_final_ieee33_cases(topo, loads_ev, out_tabs, ops);
    save(fullfile(out_raw,'final_comparison.mat'),'final_table');
end

%% G2: Final publication figures
if run_G2_summary_figs && exist('final_table','var')
    fprintf('\n--- G2: Publication-Ready Figures ---\n');
    plot_final_case_comparison(final_table, out_figs);

    % Final voltage profile comparison
    if exist(fullfile(out_raw,'misocp_single.mat'),'file')
        load(fullfile(out_raw,'misocp_single.mat'));
        if r_miso.feasible
            ph_m = r_miso.worst_hour;
            V_baseline = r_base.V_all(:,ph_m);
            V_misocp   = r_miso.V_val(:,ph_m);
            plot_voltage_profile_peak({V_baseline, V_misocp}, ...
                {'No Support','MISOCP ES'}, ph_m, ...
                fullfile(out_figs,'fig_final_voltage_profile_peak.png'));
        end
    end
    fprintf('  Final figures saved.\n');
end

%% =========================================================================
%  PIPELINE COMPLETE
%% =========================================================================
t_elapsed = toc(t_total);
fprintf('\n======================================================\n');
fprintf('  PIPELINE COMPLETE  (%.1f min)\n', t_elapsed/60);
fprintf('======================================================\n');
fprintf('\nOutputs:\n');
fprintf('  Tables  -> %s\n', out_tabs);
fprintf('  Figures -> %s\n', out_figs);
fprintf('  Raw MAT -> %s\n', out_raw);
fprintf('\nKey result files:\n');
tbl_files = dir(fullfile(out_tabs,'*.csv'));
for f = tbl_files'
    fprintf('  %s\n', f.name);
end
