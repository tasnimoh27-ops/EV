%% run_es_scenario_framework.m
% MODULE 8 (REVISED) — Multi-Scenario ES Smart-Load SOCP OPF Framework
%
% Research purpose
% ----------------
% Implements a systematic, scenario-driven workflow for studying the
% Electric Spring (ES) equivalent smart-load model on the IEEE 33-bus
% feeder.  Each scenario varies one or two design choices (ES placement,
% NCL fraction, curtailment bound, voltage constraint type) so that results
% are directly comparable and publishable.
%
% Scenario map
% ---------------
%  A  Strict Benchmark          — original settings, infeasibility allowed
%  B  Feasible Hard-Constrained — minimum rho/u_min change to achieve feasibility
%  C  Soft-Constrained Diag.    — Scenario A with voltage slack, always feasible
%  D  Expanded ES Bus Set       — buses [17,18,32,33], same rho/u_min as A
%  E  Full Controllability      — upper bound: rho=0.80, u_min=0
%  F  Lambda Sensitivity        — Scenario B with lambda_u=0 (no curtailment cost)
%
% Output structure
% ----------------
%   ./out_socp_opf_gurobi_es/
%       scenario_A_strict/
%       scenario_B_feasible/
%       scenario_C_soft_diag/
%       scenario_D_expanded/
%       scenario_E_full_ctrl/
%       scenario_F_lambda0/
%       comparison/
%
% Requirements: YALMIP + Gurobi
% Depends on:   solve_es_socp_opf_case.m
%               build_distflow_topology_from_branch_csv.m
%               build_24h_load_profile_from_csv.m

clear; clc; close all;

% =========================================================================
%  SECTION 1 — FILE PATHS
% =========================================================================
caseDir   = './01_data';
loadsCsv  = fullfile(caseDir, 'loads_base.csv');
branchCsv = fullfile(caseDir, 'branch.csv');

assert(exist(loadsCsv,  'file') == 2, "Missing: %s", loadsCsv);
assert(exist(branchCsv, 'file') == 2, "Missing: %s", branchCsv);

topDir = './out_socp_opf_gurobi_es';
if ~exist(topDir, 'dir'), mkdir(topDir); end

% =========================================================================
%  SECTION 2 — COMMON DATA  (built once, shared across all scenarios)
% =========================================================================
topo  = build_distflow_topology_from_branch_csv(branchCsv, 1);
loads = build_24h_load_profile_from_csv(loadsCsv, 'system', true, false);
assert(isfield(loads,'P24') && isfield(loads,'Q24'), "loads must have P24/Q24.");

T = 24;

% Time-of-use price profile (identical to Module 7 for fair comparison)
price = ones(T, 1);
price(1:6)   = 0.6;    % overnight off-peak
price(7:16)  = 1.0;    % shoulder / daytime
price(17:21) = 1.8;    % evening peak
price(22:24) = 0.9;    % late shoulder

% Gurobi solver options — verbose=0 for clean batch output
ops = sdpsettings('solver', 'gurobi', 'verbose', 0);
ops.gurobi.TimeLimit = 180;    % 3-minute wall-clock limit per scenario

fprintf('\n=============================================\n');
fprintf(' ES Scenario Framework — IEEE 33-bus Feeder \n');
fprintf('=============================================\n');
fprintf('Topology : nb=%d, tree-branches=%d\n', topo.nb, topo.nl_tree);

% =========================================================================
%  SECTION 3 — SCENARIO DEFINITIONS
%
%  Design rationale
%  ----------------
%  The IEEE 33-bus feeder has base-case voltages of ~0.905 at bus 18 and
%  ~0.920 at bus 33 under full load (without compensation).  To raise these
%  above Vmin=0.95 using only NCL curtailment at those two buses, the ES
%  must be able to reduce the effective load at those nodes substantially.
%
%  Scenario A (rho=0.40, u_min=0.20):
%    Minimum effective load = CL + u_min*NCL = 0.60*Pd + 0.20*0.40*Pd = 0.68*Pd
%    The residual 0.68*Pd is still too large to clear the 0.95 constraint
%    along the long branch — hence Scenario A is expected to be INFEASIBLE.
%
%  Scenario B (rho=0.60, u_min=0.0):
%    Minimum effective load = 0.40*Pd  (full NCL curtailment allowed)
%    This larger NCL headroom and deeper cut should restore feasibility.
%
%  All other scenarios keep Vmin=0.95 (hard) except Scenario C (soft slack).
% =========================================================================

base.Vmin         = 0.95;
base.Vmax         = 1.05;
base.price        = price;
base.soft_voltage = false;
base.lambda_sv    = 0;

% ---------- Scenario A — Strict Benchmark (exact original settings) ------
scA            = base;
scA.name       = 'scenario_A_strict';
scA.label      = 'Scenario A — Strict Benchmark';
scA.es_buses   = [18, 33];
scA.rho_val    = 0.40;
scA.u_min_val  = 0.20;
scA.lambda_u   = 5.0;
scA.out_dir    = fullfile(topDir, scA.name);

% ---------- Scenario B — Feasible Hard-Constrained -----------------------
% Changed from A: rho 0.40 → 0.60, u_min 0.20 → 0.00
% Rationale: more NCL is exposed AND full curtailment is allowed.
% No other parameter changes — keeps the scenario as close to A as possible.
scB            = scA;
scB.name       = 'scenario_B_feasible';
scB.label      = 'Scenario B — Feasible Hard-Constrained';
scB.rho_val    = 0.60;
scB.u_min_val  = 0.0;
scB.out_dir    = fullfile(topDir, scB.name);

% ---------- Scenario C — Soft-Constrained Diagnostic ---------------------
% Keeps EXACT Scenario A parameters; replaces hard Vmin with a slack sv.
% The slack sv(j,t) = Vmin^2 - v(j,t) when v < Vmin^2, else 0.
% Purpose: map where and when the grid violates Vmin under Scenario A
%          settings — provides engineering insight into the infeasibility.
scC                = scA;
scC.name           = 'scenario_C_soft_diag';
scC.label          = 'Scenario C — Soft-Constrained Diagnostic';
scC.soft_voltage   = true;
scC.lambda_sv      = 1000;  % large → optimizer minimises slack, not exploits it
scC.out_dir        = fullfile(topDir, scC.name);

% ---------- Scenario D — Expanded ES Bus Set [17,18,32,33] ---------------
% Adds buses 17 and 32 (one hop upstream of the two weakest buses).
% Keeps rho=0.40 and u_min=0.20 identical to Scenario A.
% Isolates the effect of placement vs. controllability headroom.
scD            = scA;
scD.name       = 'scenario_D_expanded';
scD.label      = 'Scenario D — Expanded ES Set [17,18,32,33]';
scD.es_buses   = [17, 18, 32, 33];
scD.out_dir    = fullfile(topDir, scD.name);

% ---------- Scenario E — Full Controllability (upper bound) --------------
% rho=0.80, u_min=0 at buses [18,33].
% Represents the theoretical best case for this placement —
% useful as an upper-bound reference in thesis figures.
scE            = scA;
scE.name       = 'scenario_E_full_ctrl';
scE.label      = 'Scenario E — Full Controllability (Upper Bound)';
scE.rho_val    = 0.80;
scE.u_min_val  = 0.0;
scE.out_dir    = fullfile(topDir, scE.name);

% ---------- Scenario F — Lambda Sensitivity (Scenario B, lambda_u = 0) --
% Removes curtailment penalty; pure loss minimisation drives ES control.
% Compares with Scenario B to show how much the penalty shapes curtailment.
scF            = scB;
scF.name       = 'scenario_F_lambda0';
scF.label      = 'Scenario F — Sensitivity: lambda\_u = 0';
scF.lambda_u   = 0.0;
scF.out_dir    = fullfile(topDir, scF.name);

scenarios = {scA, scB, scC, scD, scE, scF};
nSc       = numel(scenarios);

% =========================================================================
%  SECTION 4 — RUN ALL SCENARIOS  (continue on failure — never crash)
% =========================================================================
results = cell(nSc, 1);

for s = 1:nSc
    sc = scenarios{s};
    fprintf('\n[%d/%d] %s\n', s, nSc, sc.label);
    try
        results{s} = solve_es_socp_opf_case(sc, topo, loads, ops);
    catch ME
        fprintf('    MATLAB ERROR: %s\n', ME.message);
        % Build a minimal infeasible-style result so the comparison still works
        r.params            = sc;
        r.feasible          = false;
        r.sol_code          = -99;
        r.sol_info          = ME.message;
        r.V_val             = NaN(topo.nb, T);
        r.u_val             = NaN(topo.nb, T);
        r.sv_val            = NaN(topo.nb, T);
        r.Vmin_t            = NaN(T, 1);
        r.VminBus_t         = NaN(T, 1);
        r.loss_t            = NaN(T, 1);
        r.costloss_t        = NaN(T, 1);
        r.total_loss        = NaN;
        r.weighted_obj      = NaN;
        r.mean_curtailment  = NaN;
        r.max_sv            = NaN;
        r.worst_hour        = NaN;
        results{s} = r;

        if ~exist(sc.out_dir,'dir'), mkdir(sc.out_dir); end
        fid = fopen(fullfile(sc.out_dir,'error_report.txt'),'w');
        fprintf(fid,'MATLAB ERROR: %s\n%s\n', ME.message, getReport(ME,'extended'));
        fclose(fid);
    end
end

% =========================================================================
%  SECTION 5 — COMPARISON TABLE
% =========================================================================

% Classify each scenario
statusStr = cell(nSc, 1);
for s = 1:nSc
    r  = results{s};
    sc = r.params;
    if ~r.feasible
        statusStr{s} = 'INFEASIBLE';
    elseif sc.soft_voltage
        statusStr{s} = 'Diagnostic';
    else
        statusStr{s} = 'Feasible';
    end
end

% Build numeric comparison arrays
cmpMinVmin = NaN(nSc,1);
cmpLoss    = NaN(nSc,1);
cmpObj     = NaN(nSc,1);
cmpCurt    = NaN(nSc,1);
cmpSlack   = NaN(nSc,1);

for s = 1:nSc
    r = results{s};
    if r.feasible
        cmpMinVmin(s) = min(r.Vmin_t);
        cmpLoss(s)    = r.total_loss;
        cmpObj(s)     = r.weighted_obj;
        cmpCurt(s)    = r.mean_curtailment * 100;
        cmpSlack(s)   = r.max_sv;
    end
end

% Print to console
fprintf('\n\n=====================================================================\n');
fprintf('  SCENARIO COMPARISON SUMMARY\n');
fprintf('=====================================================================\n');
hdr = '  %-34s  %-10s  %-8s  %-10s  %-10s  %-9s  %-9s';
fmt = '  %-34s  %-10s  %-8s  %-10s  %-10s  %-9s  %-9s\n';
fprintf([hdr '\n'], 'Scenario Label','Status','MinVmin','TotalLoss','WeightObj','MeanCurt%','MaxSlack');
fprintf('  %s\n', repmat('-',1,99));
for s = 1:nSc
    r  = results{s};
    sc = r.params;
    fprintf(fmt, ...
        sc.label(1:min(end,34)), statusStr{s}, ...
        fmtOrNA(cmpMinVmin(s),'%.4f'), ...
        fmtOrNA(cmpLoss(s),   '%.5f'), ...
        fmtOrNA(cmpObj(s),    '%.4f'), ...
        fmtOrNA(cmpCurt(s),   '%.2f'), ...
        fmtOrNA(cmpSlack(s),  '%.2e'));
end
fprintf('=====================================================================\n\n');

% Save master comparison CSV
cmpDir = fullfile(topDir, 'comparison');
if ~exist(cmpDir,'dir'), mkdir(cmpDir); end

cmpNames  = cellfun(@(r) r.params.name,  results, 'UniformOutput', false);
cmpLabels = cellfun(@(r) r.params.label, results, 'UniformOutput', false);
cmpTable  = table(cmpNames, cmpLabels, statusStr, cmpMinVmin, cmpLoss, cmpObj, cmpCurt, cmpSlack, ...
    'VariableNames', {'ScenarioID','Label','Status', ...
        'MinVmin_pu','TotalLoss_pu','WeightedObj','MeanCurtailment_pct','MaxVoltageSlack_V2'});
writetable(cmpTable, fullfile(cmpDir, 'scenario_comparison.csv'));

% =========================================================================
%  SECTION 6 — CROSS-SCENARIO COMPARISON FIGURES
% =========================================================================

feasIdx = find(cellfun(@(r) r.feasible, results));

if numel(feasIdx) >= 2
    clrAll = lines(numel(feasIdx));

    labels_feas = cellfun(@(r) strrep(r.params.label,'\_','_'), ...
        results(feasIdx), 'UniformOutput', false);

    % --- Minimum voltage comparison ---
    fh = figure('Visible','off');
    hold on; grid on;
    for k = 1:numel(feasIdx)
        r = results{feasIdx(k)};
        plot(1:T, r.Vmin_t, '-o', 'Color', clrAll(k,:), ...
            'LineWidth',1.3, 'DisplayName', labels_feas{k});
    end
    plot([1 T],[0.95 0.95],'--k','LineWidth',1.0,'DisplayName','Vmin limit');
    xlabel('Hour'); ylabel('Min Voltage (p.u.)');
    title('Comparison: Minimum Voltage vs Hour (feasible scenarios)');
    legend('Location','best'); hold off;
    saveas(fh, fullfile(cmpDir,'compare_Vmin_vs_hour.png')); close(fh);

    % --- Loss comparison ---
    fh = figure('Visible','off');
    hold on; grid on;
    for k = 1:numel(feasIdx)
        r = results{feasIdx(k)};
        plot(1:T, r.loss_t, '-o', 'Color', clrAll(k,:), ...
            'LineWidth',1.3, 'DisplayName', labels_feas{k});
    end
    xlabel('Hour'); ylabel('Total Loss (p.u.)');
    title('Comparison: Feeder Loss vs Hour (feasible scenarios)');
    legend('Location','best'); hold off;
    saveas(fh, fullfile(cmpDir,'compare_loss_vs_hour.png')); close(fh);

    % --- ES control at bus 18 comparison ---
    fh = figure('Visible','off');
    hold on; grid on;
    for k = 1:numel(feasIdx)
        r = results{feasIdx(k)};
        u18 = r.u_val(18,:);
        if ~any(isnan(u18)) && any(abs(u18-1) > 1e-4)
            plot(1:T, u18, '-o', 'Color', clrAll(k,:), ...
                'LineWidth',1.3, 'DisplayName', labels_feas{k});
        end
    end
    xlabel('Hour'); ylabel('u(18,t)  —  NCL scaling');
    ylim([0, 1.1]);
    title('Comparison: ES Control at Bus 18');
    legend('Location','best'); hold off;
    saveas(fh, fullfile(cmpDir,'compare_u_bus18.png')); close(fh);

    % --- ES control at bus 33 comparison ---
    fh = figure('Visible','off');
    hold on; grid on;
    for k = 1:numel(feasIdx)
        r = results{feasIdx(k)};
        u33 = r.u_val(33,:);
        if ~any(isnan(u33)) && any(abs(u33-1) > 1e-4)
            plot(1:T, u33, '-o', 'Color', clrAll(k,:), ...
                'LineWidth',1.3, 'DisplayName', labels_feas{k});
        end
    end
    xlabel('Hour'); ylabel('u(33,t)  —  NCL scaling');
    ylim([0, 1.1]);
    title('Comparison: ES Control at Bus 33');
    legend('Location','best'); hold off;
    saveas(fh, fullfile(cmpDir,'compare_u_bus33.png')); close(fh);

    % --- Voltage profiles at worst hour of best feasible scenario ---
    % "best" = highest minimum voltage (most voltage support)
    [~, bestK] = max(cmpMinVmin(feasIdx));
    bestIdx    = feasIdx(bestK);
    wh         = results{bestIdx}.worst_hour;

    fh = figure('Visible','off');
    hold on; grid on;
    for k = 1:numel(feasIdx)
        r = results{feasIdx(k)};
        plot(1:topo.nb, r.V_val(:,wh), '-o', 'Color', clrAll(k,:), ...
            'LineWidth',1.3, 'DisplayName', labels_feas{k});
    end
    plot([1 topo.nb],[0.95 0.95],'--k','DisplayName','Vmin limit');
    xlabel('Bus'); ylabel('Voltage (p.u.)');
    title(sprintf('Comparison: Voltage Profiles at Hour %d', wh));
    legend('Location','best'); hold off;
    saveas(fh, fullfile(cmpDir, sprintf('compare_voltage_profile_h%02d.png',wh))); close(fh);

    % --- Bar chart: total 24h loss per scenario ---
    feasNames = cellfun(@(r) r.params.name, results(feasIdx), 'UniformOutput', false);
    fh = figure('Visible','off');
    bar(cmpLoss(feasIdx));
    set(gca,'XTickLabel', feasNames, 'XTick', 1:numel(feasIdx));
    ylabel('Total 24h Loss (p.u.)');
    title('Comparison: Total Feeder Loss by Scenario');
    grid on;
    saveas(fh, fullfile(cmpDir,'compare_total_loss_bar.png')); close(fh);

    % --- Bar chart: mean curtailment per scenario ---
    fh = figure('Visible','off');
    bar(cmpCurt(feasIdx));
    set(gca,'XTickLabel', feasNames, 'XTick', 1:numel(feasIdx));
    ylabel('Mean NCL Curtailment at ES Buses (%)');
    title('Comparison: Mean Curtailment by Scenario');
    grid on;
    saveas(fh, fullfile(cmpDir,'compare_curtailment_bar.png')); close(fh);
end

% =========================================================================
%  SECTION 7 — BASELINE COMPARISON  (vs Module 7)
% =========================================================================
baseFile = './out_socp_opf_gurobi/opf_summary_24h_cost.csv';
if exist(baseFile,'file') == 2
    base7 = readtable(baseFile);

    for s = feasIdx(:)'
        r  = results{s};
        sc = r.params;
        if sc.soft_voltage, continue; end   % skip diagnostic in baseline plot

        fh = figure('Visible','off');
        hold on; grid on;
        plot(1:T, base7.Vmin_pu, '-s', 'LineWidth',1.3, ...
            'DisplayName','Baseline (Module 7)');
        plot(1:T, r.Vmin_t, '-o', 'LineWidth',1.3, ...
            'DisplayName', sc.label);
        plot([1 T],[0.95 0.95],'--k','DisplayName','Vmin limit');
        xlabel('Hour'); ylabel('Min Voltage (p.u.)');
        title(['Module 7 vs ' sc.label ': Minimum Voltage']);
        legend('Location','best'); hold off;
        saveas(fh, fullfile(sc.out_dir,'compare_vs_module7_Vmin.png')); close(fh);
    end

    fprintf('Baseline comparison figures saved (vs Module 7).\n');
else
    fprintf('[INFO] Module 7 baseline not found at %s — skipping comparison.\n', baseFile);
    fprintf('       Run optimization.m first to enable baseline comparison.\n');
end

fprintf('\n=== All %d scenarios complete ===\n', nSc);
fprintf('Outputs root  : %s\n', topDir);
fprintf('Comparison CSV: %s\n', fullfile(cmpDir,'scenario_comparison.csv'));

% =========================================================================
%  LOCAL HELPER  (must be at end of script in MATLAB R2016b+)
% =========================================================================
function s = fmtOrNA(x, fmt)
%FMTORNA  Format a numeric value or return 'N/A' if it is NaN.
if isnan(x)
    s = 'N/A';
else
    s = sprintf(fmt, x);
end
end
