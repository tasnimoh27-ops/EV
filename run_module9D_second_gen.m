%% run_module9D_second_gen.m
% MODULE 9D — Second-Generation ES (Reactive-Capable Inverter)
%
% Research question:
%   Can equipping ES inverters at {18, 33} with reactive power capability
%   (2nd-gen ES) achieve voltage feasibility WITHOUT adding any extra Qg
%   devices or changing ES placement?
%
% Physical model:
%   A 2nd-gen ES inverter has an apparent power rating S_rated [pu].
%   It handles BOTH curtailed active power AND reactive injection:
%
%     P_curtailed(j,t)  =  (1 - u(j,t)) * Pncl0(j,t)    [active curtailment]
%     Q_ES(j,t)  >= 0                                     [reactive injection]
%
%   Inverter rating constraint (SOCP cone):
%     P_curtailed(j,t)^2 + Q_ES(j,t)^2  <=  S_rated(j)^2
%
%   When u = u_min (full curtailment):  P_curt = (1-u_min)*rho*Pd
%     → remaining Q capacity = sqrt(S_rated^2 - P_curt^2)
%     → for small Pd values, nearly all S_rated is available for Q
%
%   Effect on power balance:
%     Qij(kpar,t) = [Qd_eff(j,t) - Q_ES(j,t)] + sumQchild + X*ell
%
% Scenarios:
%   D1 — S_rated=0.05 pu each, ES at {18,33}, rho=0.40, u_min=0.20
%   D2 — S_rated=0.10 pu each, ES at {18,33}, rho=0.40, u_min=0.20
%   D3 — S_rated=0.15 pu each, ES at {18,33}, rho=0.40, u_min=0.20
%   D4 — S_rated=0.10 pu each, ES at {18,33}, rho=0.40, u_min=0.00
%   D5 — S_rated=0.10 pu each, ES at VIS-7 buses, rho=0.40, u_min=0.20
%   D6 — S_rated=0.10 pu each, ES at VIS-7 buses, rho=0.40, u_min=0.00
%
% Output: ./out_module9/D_second_gen_es/
%
% Requirements: YALMIP + Gurobi, solve_hybrid_opf_case.m

clear; clc; close all;

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
price(1:6)=0.6; price(7:16)=1.0; price(17:21)=1.8; price(22:24)=0.9;

ops = sdpsettings('solver','gurobi','verbose',0);
ops.gurobi.TimeLimit = 300;

topDir = './out_module9/D_second_gen_es';
fprintf('\n=== Module 9D: Second-Generation ES (Reactive Capability) ===\n');

es_term = [18, 33];                           % terminal ES buses
es_vis  = [6, 9, 13, 18, 26, 30, 33];        % VIS-ranked ES buses

function [rv,uv,sv_r] = build_vectors(nb, es_buses, rho_val, umin_val, srated_val)
    rv=zeros(nb,1); uv=ones(nb,1); sv_r=zeros(nb,1);
    for b=es_buses(:)'
        rv(b)=rho_val; uv(b)=umin_val; sv_r(b)=srated_val;
    end
end

base.Vmin=0.95; base.Vmax=1.05; base.price=price;
base.lambda_u=5.0; base.qg_buses=[]; base.Qg_max=zeros(nb,1);
base.lambda_q=0; base.second_gen=true;
base.soft_voltage=false; base.lambda_sv=0;

% --- D1: S_rated=0.05, terminal buses, u_min=0.20 ---
sc1         = base;
sc1.name    = '9D1_Srated005_term_umin020';
sc1.label   = '9D-1: 2ndGen S=0.05 {18,33} u_min=0.20';
sc1.es_buses= es_term;
[sc1.rho, sc1.u_min, sc1.S_rated] = build_vectors(nb, es_term, 0.40, 0.20, 0.05);
sc1.out_dir = fullfile(topDir, sc1.name);

% --- D2: S_rated=0.10, terminal buses, u_min=0.20 ---
sc2         = base;
sc2.name    = '9D2_Srated010_term_umin020';
sc2.label   = '9D-2: 2ndGen S=0.10 {18,33} u_min=0.20';
sc2.es_buses= es_term;
[sc2.rho, sc2.u_min, sc2.S_rated] = build_vectors(nb, es_term, 0.40, 0.20, 0.10);
sc2.out_dir = fullfile(topDir, sc2.name);

% --- D3: S_rated=0.15, terminal buses, u_min=0.20 ---
sc3         = base;
sc3.name    = '9D3_Srated015_term_umin020';
sc3.label   = '9D-3: 2ndGen S=0.15 {18,33} u_min=0.20';
sc3.es_buses= es_term;
[sc3.rho, sc3.u_min, sc3.S_rated] = build_vectors(nb, es_term, 0.40, 0.20, 0.15);
sc3.out_dir = fullfile(topDir, sc3.name);

% --- D4: S_rated=0.10, terminal buses, u_min=0.00 (full curtailment) ---
sc4         = base;
sc4.name    = '9D4_Srated010_term_umin000';
sc4.label   = '9D-4: 2ndGen S=0.10 {18,33} u_min=0.00';
sc4.es_buses= es_term;
[sc4.rho, sc4.u_min, sc4.S_rated] = build_vectors(nb, es_term, 0.40, 0.00, 0.10);
sc4.out_dir = fullfile(topDir, sc4.name);

% --- D5: S_rated=0.10, VIS-7 buses, u_min=0.20 ---
sc5         = base;
sc5.name    = '9D5_Srated010_vis7_umin020';
sc5.label   = '9D-5: 2ndGen S=0.10 VIS-7 u_min=0.20';
sc5.es_buses= es_vis;
[sc5.rho, sc5.u_min, sc5.S_rated] = build_vectors(nb, es_vis, 0.40, 0.20, 0.10);
sc5.out_dir = fullfile(topDir, sc5.name);

% --- D6: S_rated=0.10, VIS-7 buses, u_min=0.00 ---
sc6         = base;
sc6.name    = '9D6_Srated010_vis7_umin000';
sc6.label   = '9D-6: 2ndGen S=0.10 VIS-7 u_min=0.00';
sc6.es_buses= es_vis;
[sc6.rho, sc6.u_min, sc6.S_rated] = build_vectors(nb, es_vis, 0.40, 0.00, 0.10);
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

fprintf('\n%s\n  9D: 2ND-GEN ES RESULTS\n%s\n',repmat('=',1,85),repmat('=',1,85));
fmt = '  %-38s  %-11s  %-8s  %-10s  %-9s  %-9s\n';
fprintf(fmt,'Label','Status','MinVmin','TotalLoss','MeanCurt%','MaxQES');
fprintf('  %s\n', repmat('-',1,85));
names=cell(nSc,1); labels=cell(nSc,1); status=cell(nSc,1);
minVmin=NaN(nSc,1); totLoss=NaN(nSc,1); meanC=NaN(nSc,1); maxQES=NaN(nSc,1);
for s=1:nSc
    r=results{s}; sc=r.params;
    names{s}=sc.name; labels{s}=sc.label;
    if r.feasible
        status{s}='FEASIBLE'; minVmin(s)=min(r.Vmin_t);
        totLoss(s)=r.total_loss; meanC(s)=r.mean_curtailment*100;
        maxQES(s)=r.max_Q_ES;
    else, status{s}='INFEASIBLE'; end
    fprintf(fmt, sc.label(1:min(end,38)), status{s}, ...
        fna(minVmin(s),'%.4f'), fna(totLoss(s),'%.5f'), ...
        fna(meanC(s),'%.2f'),   fna(maxQES(s),'%.4f'));
end
fprintf('%s\n', repmat('=',1,85));

writetable(table(names,labels,status,minVmin,totLoss,meanC,maxQES, ...
    'VariableNames',{'ID','Label','Status','MinVmin_pu','TotalLoss_pu','MeanCurt_pct','MaxQ_ES_pu'}), ...
    fullfile(cmpDir,'9D_comparison.csv'));

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
    title('9D: 2nd-Gen ES — Minimum Voltage vs Hour');
    legend('Location','best'); hold off;
    saveas(fh, fullfile(cmpDir,'9D_Vmin_comparison.png')); close(fh);

    % Q_ES dispatch comparison (at bus 18)
    fh = figure('Visible','off'); hold on; grid on;
    for k=1:numel(feasIdx)
        r = results{feasIdx(k)};
        if max(r.Q_ES_val(18,:)) > 1e-6
            plot(1:24, r.Q_ES_val(18,:),'-s','Color',clr(k,:),'LineWidth',1.2, ...
                'DisplayName', r.params.label);
        end
    end
    xlabel('Hour'); ylabel('Q_{ES}(18,t)  [p.u.]');
    title('9D: Reactive Injection at Bus 18 — 2nd-Gen ES');
    legend('Location','best'); hold off;
    saveas(fh, fullfile(cmpDir,'9D_Q_ES_bus18.png')); close(fh);
end

fprintf('\n=== 9D complete. Output: %s ===\n', topDir);


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
