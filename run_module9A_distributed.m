%% run_module9A_distributed.m
% MODULE 9A — Distributed ES at VIS-ranked midpoint buses
%
% Research question:
%   Does placing ES at electrically significant MIDPOINT buses (instead of
%   only at terminal buses 18 and 33) achieve voltage feasibility?
%
% Approach:
%   ES is distributed across 7 buses spanning both the main branch and the
%   long lateral branch.  Buses are chosen by descending Voltage Impact
%   Score (VIS), which ranks a bus by the product of its available demand
%   reduction and the cumulative path resistance from the root to that bus
%   (a proxy for how much upstream voltage drop its curtailment relieves).
%
%   VIS-selected buses:  [6, 9, 13, 18, 26, 30, 33]
%     Bus  6  — main branch junction, 5 hops from substation
%     Bus  9  — main branch midpoint, 8 hops
%     Bus 13  — main branch deep midpoint, 12 hops
%     Bus 18  — main branch terminal  (also used in Module 8)
%     Bus 26  — lateral branch junction (highest individual load)
%     Bus 30  — lateral branch midpoint
%     Bus 33  — lateral branch terminal (also used in Module 8)
%
% Parameters kept identical to Module 8 Scenario A for fair comparison:
%   rho = 0.40  (40% NCL)
%   u_min = 0.20  (max 80% curtailment)
%   lambda_u = 5.0
%   Hard voltage constraint Vmin = 0.95 pu
%
% Expected result:
%   With ES at upstream buses, the cumulative R*P drop on multiple branches
%   is reduced simultaneously.  This may achieve or approach feasibility
%   that Module 8 (terminal buses only) could not reach.
%
% Output: ./out_module9/A_distributed_es/
%
% Requirements: YALMIP + Gurobi, solve_hybrid_opf_case.m

clear; clc; close all;

% =========================================================================
%  PATHS AND DATA
% =========================================================================
caseDir   = './mp_export_case33bw';
loadsCsv  = fullfile(caseDir, 'loads_base.csv');
branchCsv = fullfile(caseDir, 'branch.csv');
assert(exist(loadsCsv,'file')==2,  'Missing: %s', loadsCsv);
assert(exist(branchCsv,'file')==2, 'Missing: %s', branchCsv);

topo  = build_distflow_topology_from_branch_csv(branchCsv, 1);
loads = build_24h_load_profile_from_csv(loadsCsv, 'system', true, false);
nb    = topo.nb;

T = 24;
price = ones(T,1);
price(1:6)   = 0.6;
price(7:16)  = 1.0;
price(17:21) = 1.8;
price(22:24) = 0.9;

ops = sdpsettings('solver','gurobi','verbose',0);
ops.gurobi.TimeLimit = 300;

topDir = './out_module9/A_distributed_es';

fprintf('\n=== Module 9A: Distributed ES at VIS-ranked buses ===\n');
fprintf('Topology: nb=%d, nl=%d\n', topo.nb, topo.nl_tree);

% =========================================================================
%  SCENARIO DEFINITIONS
%  Each scenario tests a different ES bus set while keeping rho and u_min
%  identical to Module 8 Scenario A for direct comparison.
% =========================================================================

% Helper to build full rho/u_min vectors from a bus list
function [rho_v, umin_v] = build_rho_umin(nb, es_buses, rho_val, u_min_val)
    rho_v  = zeros(nb,1);
    umin_v = ones(nb,1);
    for b = es_buses(:)'
        rho_v(b)  = rho_val;
        umin_v(b) = u_min_val;
    end
end

base.Vmin         = 0.95;
base.Vmax         = 1.05;
base.price        = price;
base.lambda_u     = 5.0;
base.qg_buses     = [];
base.Qg_max       = zeros(nb,1);
base.lambda_q     = 0;
base.second_gen   = false;
base.S_rated      = zeros(nb,1);
base.soft_voltage = false;
base.lambda_sv    = 0;

% --- 9A-1: Reference — terminal buses only (replicates Module 8 Scenario A) ---
sc1          = base;
sc1.name     = '9A1_terminal_only';
sc1.label    = '9A-1: Terminal Only {18,33}';
sc1.es_buses = [18, 33];
[sc1.rho, sc1.u_min] = build_rho_umin(nb, sc1.es_buses, 0.40, 0.20);
sc1.out_dir  = fullfile(topDir, sc1.name);

% --- 9A-2: Add bus 9 (main branch midpoint) ---
sc2          = base;
sc2.name     = '9A2_add_bus9';
sc2.label    = '9A-2: {9, 18, 33}';
sc2.es_buses = [9, 18, 33];
[sc2.rho, sc2.u_min] = build_rho_umin(nb, sc2.es_buses, 0.40, 0.20);
sc2.out_dir  = fullfile(topDir, sc2.name);

% --- 9A-3: Add lateral midpoint bus 26 ---
sc3          = base;
sc3.name     = '9A3_add_bus26';
sc3.label    = '9A-3: {9, 18, 26, 33}';
sc3.es_buses = [9, 18, 26, 33];
[sc3.rho, sc3.u_min] = build_rho_umin(nb, sc3.es_buses, 0.40, 0.20);
sc3.out_dir  = fullfile(topDir, sc3.name);

% --- 9A-4: VIS top-5 buses ---
sc4          = base;
sc4.name     = '9A4_vis_top5';
sc4.label    = '9A-4: VIS Top-5 {6,9,18,26,33}';
sc4.es_buses = [6, 9, 18, 26, 33];
[sc4.rho, sc4.u_min] = build_rho_umin(nb, sc4.es_buses, 0.40, 0.20);
sc4.out_dir  = fullfile(topDir, sc4.name);

% --- 9A-5: Full VIS set — 7 buses ---
sc5          = base;
sc5.name     = '9A5_vis_full';
sc5.label    = '9A-5: VIS Full {6,9,13,18,26,30,33}';
sc5.es_buses = [6, 9, 13, 18, 26, 30, 33];
[sc5.rho, sc5.u_min] = build_rho_umin(nb, sc5.es_buses, 0.40, 0.20);
sc5.out_dir  = fullfile(topDir, sc5.name);

% --- 9A-6: Dense — every third bus along both branches ---
sc6          = base;
sc6.name     = '9A6_dense';
sc6.label    = '9A-6: Dense {3,6,9,12,15,18,24,27,30,33}';
sc6.es_buses = [3, 6, 9, 12, 15, 18, 24, 27, 30, 33];
[sc6.rho, sc6.u_min] = build_rho_umin(nb, sc6.es_buses, 0.40, 0.20);
sc6.out_dir  = fullfile(topDir, sc6.name);

% --- 9A-7: Maximum — all non-slack buses ---
sc7          = base;
sc7.name     = '9A7_all_buses';
sc7.label    = '9A-7: All Non-Slack Buses';
sc7.es_buses = setdiff(1:nb, topo.root);
[sc7.rho, sc7.u_min] = build_rho_umin(nb, sc7.es_buses, 0.40, 0.20);
sc7.out_dir  = fullfile(topDir, sc7.name);

scenarios = {sc1, sc2, sc3, sc4, sc5, sc6, sc7};
nSc       = numel(scenarios);

% =========================================================================
%  RUN ALL SCENARIOS
% =========================================================================
results = cell(nSc, 1);
for s = 1:nSc
    sc = scenarios{s};
    fprintf('\n[%d/%d] %s\n', s, nSc, sc.label);
    try
        results{s} = solve_hybrid_opf_case(sc, topo, loads, ops);
    catch ME
        fprintf('  MATLAB ERROR: %s\n', ME.message);
        r = make_infeasible_result(sc, topo.nb, T);
        results{s} = r;
    end
end

% =========================================================================
%  COMPARISON TABLE
% =========================================================================
print_comparison(results, nSc, topDir);

fprintf('\n=== 9A complete. Output: %s ===\n', topDir);


% =========================================================================
%  LOCAL HELPERS
% =========================================================================
function r = make_infeasible_result(sc, nb, T)
    r.params = sc;  r.feasible = false;  r.sol_code = -99;
    r.sol_info = 'MATLAB error';
    r.V_val = NaN(nb,T);  r.u_val = NaN(nb,T);
    r.Qg_val = NaN(nb,T); r.Q_ES_val = NaN(nb,T); r.sv_val = NaN(nb,T);
    r.Vmin_t = NaN(T,1);  r.VminBus_t = NaN(T,1);
    r.loss_t = NaN(T,1);  r.costloss_t = NaN(T,1);
    r.total_loss = NaN;   r.weighted_obj = NaN;
    r.mean_curtailment = NaN;  r.total_Qg = NaN;
    r.max_Q_ES = NaN;  r.max_sv = NaN;  r.worst_hour = NaN;
end

function print_comparison(results, nSc, topDir)
    fprintf('\n%s\n  MODULE 9A COMPARISON\n%s\n', repmat('=',1,80), repmat('=',1,80));
    hdr = '  %-38s  %-11s  %-8s  %-10s  %-10s';
    fmt = '  %-38s  %-11s  %-8s  %-10s  %-10s\n';
    fprintf([hdr '\n'], 'Label','Status','MinVmin','TotalLoss','MeanCurt%');
    fprintf('  %s\n', repmat('-',1,80));
    names   = cell(nSc,1);
    labels  = cell(nSc,1);
    status  = cell(nSc,1);
    minVmin = NaN(nSc,1);
    totLoss = NaN(nSc,1);
    meanC   = NaN(nSc,1);
    for s = 1:nSc
        r  = results{s};
        sc = r.params;
        names{s}  = sc.name;
        labels{s} = sc.label;
        if r.feasible
            status{s}  = 'FEASIBLE';
            minVmin(s) = min(r.Vmin_t);
            totLoss(s) = r.total_loss;
            meanC(s)   = r.mean_curtailment*100;
        else
            status{s} = 'INFEASIBLE';
        end
        fprintf(fmt, sc.label(1:min(end,38)), status{s}, ...
            fmt_na(minVmin(s),'%.4f'), fmt_na(totLoss(s),'%.5f'), fmt_na(meanC(s),'%.2f'));
    end
    fprintf('%s\n', repmat('=',1,80));
    cmpDir = fullfile(topDir,'comparison');
    if ~exist(cmpDir,'dir'), mkdir(cmpDir); end
    T_cmp = table(names, labels, status, minVmin, totLoss, meanC, ...
        'VariableNames',{'ScenarioID','Label','Status','MinVmin_pu','TotalLoss_pu','MeanCurt_pct'});
    writetable(T_cmp, fullfile(cmpDir,'9A_comparison.csv'));

    % Comparison plot: Vmin vs hour for all feasible scenarios
    feasIdx = find(cellfun(@(r) r.feasible, results));
    if numel(feasIdx) >= 1
        T24 = 24;
        fh = figure('Visible','off'); hold on; grid on;
        clr = lines(numel(feasIdx));
        for k = 1:numel(feasIdx)
            r = results{feasIdx(k)};
            plot(1:T24, r.Vmin_t,'-o','Color',clr(k,:),'LineWidth',1.3, ...
                'DisplayName', r.params.label);
        end
        plot([1 T24],[0.95 0.95],'--k','DisplayName','Vmin limit');
        xlabel('Hour'); ylabel('Min Voltage (p.u.)');
        title('9A: Minimum Voltage vs Hour — Feasible Scenarios');
        legend('Location','best'); hold off;
        saveas(fh, fullfile(cmpDir,'9A_Vmin_comparison.png')); close(fh);
    end
end

function s = fmt_na(x, fmt)
    if isnan(x), s = 'N/A'; else, s = sprintf(fmt,x); end
end
