%% run_module9B_hybrid_qg.m
% MODULE 9B — Hybrid ES (terminal buses) + Reactive Support (Qg)
%
% Research question:
%   What is the MINIMUM reactive power (Qg) capacity needed at bottleneck
%   buses to make ES at terminal buses {18, 33} fully feasible?
%
% Approach:
%   Keep ES exactly as Module 8 Scenario A ({18,33}, rho=0.40, u_min=0.20).
%   Add a Qg-capable device at each of several "bottleneck" buses identified
%   from the Scenario C voltage-slack map (buses 6, 9, 16 are deepest in
%   violation on the main branch).
%   Vary Qg_max systematically to find the feasibility threshold.
%
% Physics rationale:
%   The voltage deficit at bus 18 (51.7 mV below 0.95 pu at hour 20) is
%   primarily caused by X*Q flow on the main branch.  A reactive injection
%   at bus 16 reduces Q flowing on ALL branches upstream (1→16), providing
%   cumulative voltage support that ES cannot provide.
%
% Scenario grid:
%   Qg placement:  {16}, {9,16}, {6,9,16}
%   Qg_max each:   0.03, 0.05, 0.08, 0.10 pu
%   (12 combinations — all expected to be feasible beyond some threshold)
%
% Output: ./out_module9/B_hybrid_qg/
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

topDir = './out_module9/B_hybrid_qg';
fprintf('\n=== Module 9B: Hybrid ES + Qg — Minimum Reactive Support ===\n');

% Fixed ES configuration (same as Module 8 Scenario A)
es_buses_fixed = [18, 33];
rho_fixed      = 0.40;
u_min_fixed    = 0.20;
lambda_u_fixed = 5.0;
lambda_q_fixed = 1.0;   % small cost encourages minimum Qg use

% Build rho/u_min vectors
rho_v   = zeros(nb,1); rho_v(es_buses_fixed)   = rho_fixed;
u_min_v = ones(nb,1);  u_min_v(es_buses_fixed) = u_min_fixed;

% =========================================================================
%  SCENARIO GRID
% =========================================================================
qg_placement_sets = {
    [16],       '9B-{16}';
    [9, 16],    '9B-{9,16}';
    [6, 9, 16], '9B-{6,9,16}';
};
qg_max_values = [0.03, 0.05, 0.08, 0.10];

scenarios = {};
for p = 1:size(qg_placement_sets, 1)
    qg_buses = qg_placement_sets{p,1};
    plabel   = qg_placement_sets{p,2};
    for q = 1:numel(qg_max_values)
        qmax = qg_max_values(q);

        Qg_max_v = zeros(nb,1);
        for b = qg_buses
            Qg_max_v(b) = qmax;
        end

        sc               = struct();
        sc.name          = sprintf('9B_Qg%s_max%.2f', ...
                              strrep(mat2str(qg_buses),'[',''), qmax);
        sc.name          = strrep(sc.name,' ','_');
        sc.name          = strrep(sc.name,']','');
        sc.label         = sprintf('%s  Qmax=%.2fpu', plabel, qmax);
        sc.es_buses      = es_buses_fixed;
        sc.rho           = rho_v;
        sc.u_min         = u_min_v;
        sc.lambda_u      = lambda_u_fixed;
        sc.qg_buses      = qg_buses;
        sc.Qg_max        = Qg_max_v;
        sc.lambda_q      = lambda_q_fixed;
        sc.second_gen    = false;
        sc.S_rated       = zeros(nb,1);
        sc.Vmin          = 0.95;
        sc.Vmax          = 1.05;
        sc.soft_voltage  = false;
        sc.lambda_sv     = 0;
        sc.price         = price;
        sc.out_dir       = fullfile(topDir, sc.name);
        scenarios{end+1} = sc; %#ok<AGROW>
    end
end

nSc = numel(scenarios);
fprintf('Running %d hybrid ES+Qg scenarios...\n', nSc);

% =========================================================================
%  RUN ALL
% =========================================================================
results = cell(nSc,1);
for s = 1:nSc
    sc = scenarios{s};
    fprintf('\n[%d/%d] %s\n', s, nSc, sc.label);
    try
        results{s} = solve_hybrid_opf_case(sc, topo, loads, ops);
    catch ME
        fprintf('  MATLAB ERROR: %s\n', ME.message);
        results{s} = make_infeasible_result(sc, nb, T);
    end
end

% =========================================================================
%  RESULTS TABLE + MINIMUM QG FINDER
% =========================================================================
cmpDir = fullfile(topDir,'comparison');
if ~exist(cmpDir,'dir'), mkdir(cmpDir); end

fprintf('\n%s\n  9B: HYBRID ES+Qg RESULTS\n%s\n', repmat('=',1,90), repmat('=',1,90));
fmt = '  %-38s  %-11s  %-8s  %-10s  %-10s  %-9s\n';
fprintf(fmt,'Label','Status','MinVmin','TotalLoss','MeanCurt%','PeakQg');
fprintf('  %s\n', repmat('-',1,90));

rowNames   = cell(nSc,1);
rowLabels  = cell(nSc,1);
rowStatus  = cell(nSc,1);
rowMinVmin = NaN(nSc,1);
rowLoss    = NaN(nSc,1);
rowCurt    = NaN(nSc,1);
rowTotQg   = NaN(nSc,1);

for s = 1:nSc
    r  = results{s};
    sc = r.params;
    rowNames{s}  = sc.name;
    rowLabels{s} = sc.label;
    if r.feasible
        rowStatus{s}  = 'FEASIBLE';
        rowMinVmin(s) = min(r.Vmin_t);
        rowLoss(s)    = r.total_loss;
        rowCurt(s)    = r.mean_curtailment*100;
        rowTotQg(s)   = r.total_Qg;
    else
        rowStatus{s} = 'INFEASIBLE';
    end
    fprintf(fmt, sc.label(1:min(end,38)), rowStatus{s}, ...
        fmt_na(rowMinVmin(s),'%.4f'), fmt_na(rowLoss(s),'%.5f'), ...
        fmt_na(rowCurt(s),'%.2f'),    fmt_na(rowTotQg(s),'%.4f'));
end
fprintf('%s\n', repmat('=',1,90));

% Find minimum Qg threshold for each placement
fprintf('\n--- Minimum Qg_max for feasibility per placement ---\n');
for p = 1:size(qg_placement_sets,1)
    plabel = qg_placement_sets{p,2};
    found  = false;
    for q = 1:numel(qg_max_values)
        idx = (p-1)*numel(qg_max_values) + q;
        if results{idx}.feasible
            fprintf('  %s : FEASIBLE at Qg_max = %.2f pu\n', plabel, qg_max_values(q));
            found = true;
            break;
        end
    end
    if ~found
        fprintf('  %s : INFEASIBLE at all tested Qg_max values\n', plabel);
    end
end

% Save CSV
T_cmp = table(rowNames, rowLabels, rowStatus, rowMinVmin, rowLoss, rowCurt, rowTotQg, ...
    'VariableNames', {'ScenarioID','Label','Status', ...
        'MinVmin_pu','TotalLoss_pu','MeanCurt_pct','TotalQg_puh'});
writetable(T_cmp, fullfile(cmpDir,'9B_comparison.csv'));

% Plot: Vmin vs hour for all feasible, grouped by placement
feasIdx = find(cellfun(@(r) r.feasible, results));
if ~isempty(feasIdx)
    fh = figure('Visible','off'); hold on; grid on;
    clr = lines(numel(feasIdx));
    for k = 1:numel(feasIdx)
        r = results{feasIdx(k)};
        plot(1:24, r.Vmin_t,'-o','Color',clr(k,:),'LineWidth',1.1, ...
            'DisplayName',r.params.label);
    end
    plot([1 24],[0.95 0.95],'--k','DisplayName','Vmin limit');
    xlabel('Hour'); ylabel('Min Voltage (p.u.)');
    title('9B: Minimum Voltage vs Hour — Hybrid ES+Qg Scenarios');
    legend('Location','best'); hold off;
    saveas(fh, fullfile(cmpDir,'9B_Vmin_comparison.png')); close(fh);

    % Bar chart: peak Qg vs scenario
    fh = figure('Visible','off');
    bar(rowTotQg(feasIdx));
    xt = arrayfun(@(s) results{s}.params.label(1:min(end,20)), feasIdx(:), ...
        'UniformOutput',false);
    set(gca,'XTick',1:numel(feasIdx),'XTickLabel',xt,'XTickLabelRotation',30);
    ylabel('Total Qg dispatch 24h (pu·h)');
    title('9B: Total Reactive Support Needed');
    grid on;
    saveas(fh, fullfile(cmpDir,'9B_Qg_bar.png')); close(fh);
end

fprintf('\n=== 9B complete. Output: %s ===\n', topDir);


% =========================================================================
%  LOCAL HELPERS
% =========================================================================
function r = make_infeasible_result(sc, nb, T)
    r.params=sc; r.feasible=false; r.sol_code=-99; r.sol_info='error';
    r.V_val=NaN(nb,T); r.u_val=NaN(nb,T); r.Qg_val=NaN(nb,T);
    r.Q_ES_val=NaN(nb,T); r.sv_val=NaN(nb,T);
    r.Vmin_t=NaN(T,1); r.VminBus_t=NaN(T,1);
    r.loss_t=NaN(T,1); r.costloss_t=NaN(T,1);
    r.total_loss=NaN; r.weighted_obj=NaN; r.mean_curtailment=NaN;
    r.total_Qg=NaN; r.max_Q_ES=NaN; r.max_sv=NaN; r.worst_hour=NaN;
end

function s = fmt_na(x,fmt)
    if isnan(x), s='N/A'; else, s=sprintf(fmt,x); end
end
