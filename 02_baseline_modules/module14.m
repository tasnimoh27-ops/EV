%% run_module9E_full_hybrid.m
% MODULE 9E — Full Hybrid: Distributed ES + Heterogeneous rho + 2nd-Gen + Qg
%
% Research question:
%   What is the best achievable performance (lowest loss, highest Vmin,
%   minimum curtailment) when ALL available degrees of freedom are combined?
%
% This module is the UPPER BOUND benchmark for the ES framework.
% It combines every mechanism from Modules 9A-9D simultaneously and
% tests whether the combination achieves significantly better results
% than any individual approach.
%
% Architecture:
%   Layer 1 (ES demand):  Distributed ES at VIS-7 buses [6,9,13,18,26,30,33]
%                          with heterogeneous rho (higher at upstream junctions)
%   Layer 2 (2nd-gen Q):  ES inverters at VIS-7 buses have reactive capability
%                          S_rated per bus based on load size
%   Layer 3 (Qg support): Minimal Qg at critical bottleneck buses [6, 16]
%                          (if needed to close remaining voltage gap)
%
% Scenarios:
%   E1 — Dist-ES hetero-rho + 2ndGen, NO extra Qg   (pure ES upper bound)
%   E2 — Dist-ES hetero-rho + 2ndGen + Qg@{6,16}   (full hybrid)
%   E3 — Dist-ES hetero-rho + NO 2ndGen + Qg@{6,16} (ES+Qg without inverter Q)
%   E4 — E2 with aggressive u_min=0.00               (maximum curtailment)
%   E5 — E2 with lambda_u=0 (free curtailment)        (no curtailment penalty)
%
% Output: ./out_module9/E_full_hybrid/
%
% Requirements: YALMIP + Gurobi, solve_hybrid_opf_case.m

clear; clc; close all;

caseDir   = './01_data';
loadsCsv  = fullfile(caseDir, 'loads_base.csv');
branchCsv = fullfile(caseDir, 'branch.csv');
assert(exist(loadsCsv,'file')==2,  'Missing: %s', loadsCsv);
assert(exist(branchCsv,'file')==2, 'Missing: %s', branchCsv);

topo  = build_distflow_topology_from_branch_csv(branchCsv, 1);
loads = build_24h_load_profile_from_csv(loadsCsv, 'system', true, false);
nb    = topo.nb;

T = 24;
price = ones(T,1);
price(1:6)=0.6; price(7:16)=1.0; price(17:21)=1.8; price(22:24)=0.9;

ops = sdpsettings('solver','gurobi','verbose',0);
ops.gurobi.TimeLimit = 300;

topDir = './out_module9/E_full_hybrid';
fprintf('\n=== Module 9E: Full Hybrid (ES + 2nd-Gen + Qg) ===\n');

% ----- Common configuration -----
es_vis = [6, 9, 13, 18, 26, 30, 33];

% Heterogeneous rho
rho_h = zeros(nb,1);
rho_h(6)=0.60; rho_h(9)=0.50; rho_h(13)=0.45; rho_h(18)=0.40;
rho_h(26)=0.60; rho_h(30)=0.50; rho_h(33)=0.40;

% u_min (standard)
u_min_std = ones(nb,1);
for b=es_vis, u_min_std(b)=0.20; end

% u_min aggressive
u_min_agg = ones(nb,1);
for b=es_vis, u_min_agg(b)=0.00; end

% S_rated proportional to rho*Pd_max (rough sizing: 0.05-0.12 pu)
% Larger loads and upstream position → larger inverter rating
S_rated_h = zeros(nb,1);
S_rated_h(6)=0.10;  S_rated_h(9)=0.08;  S_rated_h(13)=0.06;
S_rated_h(18)=0.05; S_rated_h(26)=0.12; S_rated_h(30)=0.08;
S_rated_h(33)=0.05;

% Qg support at bottleneck buses
qg_buses_e = [6, 16];
Qg_max_e   = zeros(nb,1);
Qg_max_e(6)=0.08; Qg_max_e(16)=0.10;

base.Vmin=0.95; base.Vmax=1.05; base.price=price;
base.es_buses=es_vis; base.lambda_u=5.0;

% --- E1: Distributed-ES + hetero-rho + 2ndGen, NO Qg ---
sc1              = base;
sc1.name         = '9E1_dist_hetero_2ndgen_noQg';
sc1.label        = '9E-1: Dist-ES+HeteroRho+2ndGen (no Qg)';
sc1.rho          = rho_h;
sc1.u_min        = u_min_std;
sc1.qg_buses     = [];
sc1.Qg_max       = zeros(nb,1);
sc1.lambda_q     = 0;
sc1.second_gen   = true;
sc1.S_rated      = S_rated_h;
sc1.soft_voltage = false; sc1.lambda_sv=0;
sc1.out_dir      = fullfile(topDir, sc1.name);

% --- E2: Distributed-ES + hetero-rho + 2ndGen + Qg (FULL HYBRID) ---
sc2              = base;
sc2.name         = '9E2_full_hybrid';
sc2.label        = '9E-2: FULL HYBRID (All combined)';
sc2.rho          = rho_h;
sc2.u_min        = u_min_std;
sc2.qg_buses     = qg_buses_e;
sc2.Qg_max       = Qg_max_e;
sc2.lambda_q     = 1.0;
sc2.second_gen   = true;
sc2.S_rated      = S_rated_h;
sc2.soft_voltage = false; sc2.lambda_sv=0;
sc2.out_dir      = fullfile(topDir, sc2.name);

% --- E3: Distributed-ES + hetero-rho + NO 2ndGen + Qg ---
sc3              = base;
sc3.name         = '9E3_dist_hetero_noQ_ES_withQg';
sc3.label        = '9E-3: Dist-ES+HeteroRho+Qg (no 2ndGen)';
sc3.rho          = rho_h;
sc3.u_min        = u_min_std;
sc3.qg_buses     = qg_buses_e;
sc3.Qg_max       = Qg_max_e;
sc3.lambda_q     = 1.0;
sc3.second_gen   = false;
sc3.S_rated      = zeros(nb,1);
sc3.soft_voltage = false; sc3.lambda_sv=0;
sc3.out_dir      = fullfile(topDir, sc3.name);

% --- E4: Full hybrid + aggressive u_min=0.00 ---
sc4              = sc2;
sc4.name         = '9E4_full_hybrid_aggressive';
sc4.label        = '9E-4: FULL HYBRID  u_min=0.00';
sc4.u_min        = u_min_agg;
sc4.out_dir      = fullfile(topDir, sc4.name);

% --- E5: Full hybrid + lambda_u=0 (no curtailment penalty) ---
sc5              = sc2;
sc5.name         = '9E5_full_hybrid_lambda0';
sc5.label        = '9E-5: FULL HYBRID  lambda_u=0';
sc5.lambda_u     = 0;
sc5.out_dir      = fullfile(topDir, sc5.name);

scenarios = {sc1, sc2, sc3, sc4, sc5};
nSc       = numel(scenarios);

% =========================================================================
%  RUN
% =========================================================================
results = cell(nSc,1);
for s = 1:nSc
    sc = scenarios{s};
    fprintf('\n[%d/%d] %s\n', s, nSc, sc.label);
    try
        results{s} = solve_hybrid_opf_case(sc, topo, loads, ops);
    catch ME
        fprintf('  MATLAB ERROR: %s\n', ME.message);
        results{s} = make_inf(sc, nb, T);
    end
end

% =========================================================================
%  COMPARISON + MULTI-METRIC SUMMARY
% =========================================================================
cmpDir = fullfile(topDir,'comparison');
if ~exist(cmpDir,'dir'), mkdir(cmpDir); end

fprintf('\n%s\n  9E: FULL HYBRID RESULTS\n%s\n',repmat('=',1,90),repmat('=',1,90));
fmt = '  %-38s  %-11s  %-8s  %-10s  %-10s  %-9s  %-8s\n';
fprintf(fmt,'Label','Status','MinVmin','TotalLoss','MeanCurt%','TotQg','MaxQES');
fprintf('  %s\n', repmat('-',1,90));

names=cell(nSc,1); labels=cell(nSc,1); status=cell(nSc,1);
minVmin=NaN(nSc,1); totLoss=NaN(nSc,1); meanC=NaN(nSc,1);
totQg=NaN(nSc,1); maxQES=NaN(nSc,1);

for s=1:nSc
    r=results{s}; sc=r.params;
    names{s}=sc.name; labels{s}=sc.label;
    if r.feasible
        status{s}='FEASIBLE'; minVmin(s)=min(r.Vmin_t);
        totLoss(s)=r.total_loss; meanC(s)=r.mean_curtailment*100;
        totQg(s)=r.total_Qg;    maxQES(s)=r.max_Q_ES;
    else
        status{s}='INFEASIBLE';
    end
    fprintf(fmt, sc.label(1:min(end,38)), status{s}, ...
        fna(minVmin(s),'%.4f'), fna(totLoss(s),'%.5f'), fna(meanC(s),'%.2f'), ...
        fna(totQg(s),'%.4f'),   fna(maxQES(s),'%.4f'));
end
fprintf('%s\n', repmat('=',1,90));

% Also compare vs Module 7 baseline if available
base7file = './out_socp_opf_gurobi/opf_summary_24h_cost.csv';
if exist(base7file,'file')
    base7 = readtable(base7file);
    fprintf('\n  Module 7 baseline: MinVmin=%.4f  TotalLoss=%.5f  (uses Qg, no ES)\n', ...
        min(base7.Vmin_pu), sum(base7.Loss_pu));
end

writetable(table(names,labels,status,minVmin,totLoss,meanC,totQg,maxQES, ...
    'VariableNames',{'ID','Label','Status','MinVmin_pu','TotalLoss_pu', ...
        'MeanCurt_pct','TotalQg_puh','MaxQ_ES_pu'}), ...
    fullfile(cmpDir,'9E_comparison.csv'));

feasIdx = find(cellfun(@(r) r.feasible, results));
if ~isempty(feasIdx)
    fh = figure('Visible','off'); hold on; grid on;
    clr = lines(numel(feasIdx)+1);
    % Module 7 baseline for reference
    if exist(base7file,'file')
        plot(1:24, base7.Vmin_pu,'-ks','LineWidth',1.3,'DisplayName','Module 7 Baseline (Qg)');
    end
    for k=1:numel(feasIdx)
        r = results{feasIdx(k)};
        plot(1:24, r.Vmin_t,'-o','Color',clr(k+1,:),'LineWidth',1.3, ...
            'DisplayName', r.params.label);
    end
    plot([1 24],[0.95 0.95],'--k','LineWidth',1,'DisplayName','Vmin limit');
    xlabel('Hour'); ylabel('Min Voltage (p.u.)');
    title('9E: Full Hybrid vs Module 7 Baseline — Minimum Voltage');
    legend('Location','best'); hold off;
    saveas(fh, fullfile(cmpDir,'9E_Vmin_vs_baseline.png')); close(fh);

    % Multi-bar: loss comparison
    fh = figure('Visible','off');
    bar_data = totLoss(feasIdx);
    if exist(base7file,'file')
        bar_data = [sum(base7.Loss_pu); bar_data];
        tick_labels = [{'Module 7'}; cellfun(@(r) r.params.name(1:min(end,15)), ...
            results(feasIdx), 'UniformOutput',false)];
    else
        tick_labels = cellfun(@(r) r.params.name(1:min(end,15)), ...
            results(feasIdx), 'UniformOutput',false);
    end
    bar(bar_data); grid on;
    set(gca,'XTickLabel',tick_labels,'XTick',1:numel(bar_data),'XTickLabelRotation',30);
    ylabel('Total 24h Feeder Loss (p.u.)');
    title('9E: Loss Comparison — Full Hybrid vs Baseline');
    saveas(fh, fullfile(cmpDir,'9E_loss_bar.png')); close(fh);
end

fprintf('\n=== 9E complete. Output: %s ===\n', topDir);


function r = make_inf(sc, nb, T)
    r.params=sc; r.feasible=false; r.sol_code=-99; r.sol_info='error';
    r.V_val=NaN(nb,T); r.u_val=NaN(nb,T); r.Qg_val=NaN(nb,T);
    r.Q_ES_val=NaN(nb,T); r.sv_val=NaN(nb,T);
    r.Vmin_t=NaN(T,1); r.VminBus_t=NaN(T,1);
    r.loss_t=NaN(T,1); r.costloss_t=NaN(T,1);
    r.total_loss=NaN; r.weighted_obj=NaN; r.mean_curtailment=NaN;
    r.total_Qg=NaN; r.max_Q_ES=NaN; r.max_sv=NaN; r.worst_hour=NaN;
end

function s = fna(x,fmt)
    if isnan(x), s='N/A'; else, s=sprintf(fmt,x); end
end
