%% run_module9C_hetero_rho.m
% MODULE 9C — Distributed ES with Heterogeneous NCL Fraction (rho)
%
% Research question:
%   Does assigning HIGHER rho to load-dense upstream buses (where
%   flexibility has greater voltage impact) achieve feasibility more
%   efficiently than uniform rho across all ES buses?
%
% Approach:
%   ES at VIS-ranked buses [6, 9, 13, 18, 26, 30, 33].
%   rho(j) is differentiated by bus position and load type:
%     Bus 6,26  : commercial/industrial junction  → rho = 0.60
%     Bus 9,30  : mixed feeder midpoint           → rho = 0.50
%     Bus 13    : residential deep midpoint       → rho = 0.45
%     Bus 18,33 : end-of-feeder terminal          → rho = 0.40
%
%   Compared against homogeneous rho=0.40 (Module 8) and rho=0.60 (Scen B).
%
% Physics rationale:
%   Voltage Impact Score VIS(j) ∝ rho(j) * Pd(j) * sum(R_k, path_to_j)
%   Assigning higher rho at buses with high Pd AND high upstream path
%   resistance maximises the voltage relief per unit of curtailed load.
%
% Scenarios:
%   C1 — Hetero rho (profile above), u_min=0.20, hard V
%   C2 — Hetero rho, u_min=0.10 (more aggressive)
%   C3 — Hetero rho, u_min=0.00 (full curtailment allowed)
%   C4 — Uniform rho=0.50 (mid-point reference), u_min=0.20
%   C5 — Uniform rho=0.60 (high reference), u_min=0.20
%
% Output: ./out_module9/C_hetero_rho/
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

topDir = './out_module9/C_hetero_rho';
fprintf('\n=== Module 9C: Distributed ES — Heterogeneous rho ===\n');

% VIS-ranked ES bus set (same across all 9C scenarios)
es_buses_vis = [6, 9, 13, 18, 26, 30, 33];

% Heterogeneous rho profile (bus-type differentiated)
rho_hetero = zeros(nb,1);
rho_hetero(6)  = 0.60;   % commercial junction
rho_hetero(9)  = 0.50;   % mixed midpoint
rho_hetero(13) = 0.45;   % residential deep
rho_hetero(18) = 0.40;   % terminal
rho_hetero(26) = 0.60;   % lateral junction (high load)
rho_hetero(30) = 0.50;   % lateral midpoint
rho_hetero(33) = 0.40;   % lateral terminal

base.Vmin=0.95; base.Vmax=1.05; base.price=price;
base.lambda_u=5.0; base.qg_buses=[]; base.Qg_max=zeros(nb,1);
base.lambda_q=0; base.second_gen=false; base.S_rated=zeros(nb,1);
base.soft_voltage=false; base.lambda_sv=0;
base.es_buses = es_buses_vis;

% Uniform rho builder
function [rv, uv] = uni_rho(nb, es_buses, rho_val, u_min_val)
    rv = zeros(nb,1);  uv = ones(nb,1);
    for b = es_buses(:)', rv(b)=rho_val; uv(b)=u_min_val; end
end

% --- C1: Heterogeneous rho, u_min=0.20 ---
sc1         = base;
sc1.name    = '9C1_hetero_umin020';
sc1.label   = '9C-1: Hetero-rho  u_min=0.20';
sc1.rho     = rho_hetero;
sc1.u_min   = ones(nb,1);
for b=es_buses_vis, sc1.u_min(b)=0.20; end
sc1.out_dir = fullfile(topDir, sc1.name);

% --- C2: Heterogeneous rho, u_min=0.10 ---
sc2         = base;
sc2.name    = '9C2_hetero_umin010';
sc2.label   = '9C-2: Hetero-rho  u_min=0.10';
sc2.rho     = rho_hetero;
sc2.u_min   = ones(nb,1);
for b=es_buses_vis, sc2.u_min(b)=0.10; end
sc2.out_dir = fullfile(topDir, sc2.name);

% --- C3: Heterogeneous rho, u_min=0.00 ---
sc3         = base;
sc3.name    = '9C3_hetero_umin000';
sc3.label   = '9C-3: Hetero-rho  u_min=0.00';
sc3.rho     = rho_hetero;
sc3.u_min   = ones(nb,1);
for b=es_buses_vis, sc3.u_min(b)=0.00; end
sc3.out_dir = fullfile(topDir, sc3.name);

% --- C4: Uniform rho=0.50, u_min=0.20 ---
sc4         = base;
sc4.name    = '9C4_uni_rho050';
sc4.label   = '9C-4: Uni rho=0.50  u_min=0.20';
[sc4.rho, sc4.u_min] = uni_rho(nb, es_buses_vis, 0.50, 0.20);
sc4.out_dir = fullfile(topDir, sc4.name);

% --- C5: Uniform rho=0.60, u_min=0.20 ---
sc5         = base;
sc5.name    = '9C5_uni_rho060';
sc5.label   = '9C-5: Uni rho=0.60  u_min=0.20';
[sc5.rho, sc5.u_min] = uni_rho(nb, es_buses_vis, 0.60, 0.20);
sc5.out_dir = fullfile(topDir, sc5.name);

% --- C6: Uniform rho=0.60, u_min=0.00 ---
sc6         = base;
sc6.name    = '9C6_uni_rho060_umin0';
sc6.label   = '9C-6: Uni rho=0.60  u_min=0.00';
[sc6.rho, sc6.u_min] = uni_rho(nb, es_buses_vis, 0.60, 0.00);
sc6.out_dir = fullfile(topDir, sc6.name);

scenarios = {sc1, sc2, sc3, sc4, sc5, sc6};
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
%  COMPARISON
% =========================================================================
cmpDir = fullfile(topDir,'comparison');
if ~exist(cmpDir,'dir'), mkdir(cmpDir); end
print_cmp(results, nSc, cmpDir);

fprintf('\n=== 9C complete. Output: %s ===\n', topDir);


% =========================================================================
%  LOCAL HELPERS
% =========================================================================
function r = make_inf(sc, nb, T)
    r.params=sc; r.feasible=false; r.sol_code=-99; r.sol_info='error';
    r.V_val=NaN(nb,T); r.u_val=NaN(nb,T); r.Qg_val=NaN(nb,T);
    r.Q_ES_val=NaN(nb,T); r.sv_val=NaN(nb,T);
    r.Vmin_t=NaN(T,1); r.VminBus_t=NaN(T,1);
    r.loss_t=NaN(T,1); r.costloss_t=NaN(T,1);
    r.total_loss=NaN; r.weighted_obj=NaN; r.mean_curtailment=NaN;
    r.total_Qg=NaN; r.max_Q_ES=NaN; r.max_sv=NaN; r.worst_hour=NaN;
end

function print_cmp(results, nSc, cmpDir)
    fprintf('\n%s\n  9C COMPARISON\n%s\n', repmat('=',1,80), repmat('=',1,80));
    fmt = '  %-38s  %-11s  %-8s  %-10s  %-10s\n';
    fprintf(fmt,'Label','Status','MinVmin','TotalLoss','MeanCurt%');
    fprintf('  %s\n', repmat('-',1,80));
    names=cell(nSc,1); labels=cell(nSc,1); status=cell(nSc,1);
    minVmin=NaN(nSc,1); totLoss=NaN(nSc,1); meanC=NaN(nSc,1);
    for s=1:nSc
        r=results{s}; sc=r.params;
        names{s}=sc.name; labels{s}=sc.label;
        if r.feasible
            status{s}='FEASIBLE'; minVmin(s)=min(r.Vmin_t);
            totLoss(s)=r.total_loss; meanC(s)=r.mean_curtailment*100;
        else, status{s}='INFEASIBLE'; end
        fprintf(fmt, sc.label(1:min(end,38)), status{s}, ...
            fna(minVmin(s),'%.4f'), fna(totLoss(s),'%.5f'), fna(meanC(s),'%.2f'));
    end
    fprintf('%s\n', repmat('=',1,80));
    writetable(table(names,labels,status,minVmin,totLoss,meanC, ...
        'VariableNames',{'ID','Label','Status','MinVmin_pu','TotalLoss_pu','MeanCurt_pct'}), ...
        fullfile(cmpDir,'9C_comparison.csv'));

    feasIdx = find(cellfun(@(r) r.feasible, results));
    if ~isempty(feasIdx)
        fh = figure('Visible','off'); hold on; grid on;
        clr = lines(numel(feasIdx));
        for k=1:numel(feasIdx)
            r = results{feasIdx(k)};
            plot(1:24, r.Vmin_t,'-o','Color',clr(k,:),'LineWidth',1.3, ...
                'DisplayName', r.params.label);
        end
        plot([1 24],[0.95 0.95],'--k','DisplayName','Vmin limit');
        xlabel('Hour'); ylabel('Min Voltage (p.u.)');
        title('9C: Minimum Voltage — Heterogeneous vs Uniform rho');
        legend('Location','best'); hold off;
        saveas(fh, fullfile(cmpDir,'9C_Vmin_comparison.png')); close(fh);
    end
end

function s = fna(x,fmt)
    if isnan(x), s='N/A'; else, s=sprintf(fmt,x); end
end
