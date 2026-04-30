%% run_es_budget_sensitivity.m
% MODULE 11 — ES Budget Sensitivity
%
% Runs the MISOCP optimized placement for each budget in N_ES_max_list.
% Calls run_optimized_es_placement logic as a function-like block.
% Produces budget vs Vmin and budget vs loss plots.
%
% This module re-uses the MISOCP from Module 10 but sweeps N_ES_max only,
% keeping all other parameters fixed.
%
% Output:
%   results/tables/es_budget_sensitivity.csv
%   results/figures/es_budget_vs_min_voltage.png
%   results/figures/es_budget_vs_loss.png
%   results/figures/es_budget_feasibility.png

clear; clc; close all;
addpath(genpath('./src'));

cfg.load_multiplier = 1.0;
cfg.alpha_ncl       = 0.30;
cfg.ncl_pf          = 1.00;
cfg.u_min           = 0.20;
cfg.rho_max         = 0.80;
cfg.N_ES_max_list   = [1, 2, 3, 4, 5, 6, 8, 10, 15, 20, 32];
cfg.Vmin            = 0.95;
cfg.Vmax            = 1.05;
cfg.c_loss = 1.0; cfg.c_es = 0.10; cfg.c_rho = 0.05; cfg.c_curt = 0.50;
cfg.time_limit = 300;

caseDir   = './mp_export_case33bw';
branchCsv = fullfile(caseDir, 'branch.csv');
loadsCsv  = fullfile(caseDir, 'loads_base.csv');
topo  = build_distflow_topology_from_branch_csv(branchCsv, 1);
loads = build_24h_load_profile_from_csv(loadsCsv, 'system', true, false);
loads.P24 = cfg.load_multiplier * loads.P24;
loads.Q24 = cfg.load_multiplier * loads.Q24;

nb = topo.nb; T = 24; root = topo.root;
price = ones(T,1);
price(1:6)=0.6; price(7:16)=1.0; price(17:21)=1.8; price(22:24)=0.9;

ops = sdpsettings('solver','gurobi','verbose',0);
ops.gurobi.TimeLimit = cfg.time_limit;
ops.gurobi.MIPGap    = 0.01;

all_buses = setdiff(1:nb, root);
cl_ncl    = split_cl_ncl_load(loads, cfg.alpha_ncl, all_buses, cfg.ncl_pf);
P_CL = cl_ncl.P_CL; Q_CL = cl_ncl.Q_CL;
P_NCL = cl_ncl.P_NCL; Q_NCL = cl_ncl.Q_NCL;
S_NCL = sqrt(mean(P_NCL,2).^2 + mean(Q_NCL,2).^2);

nl = topo.nl_tree; from = topo.from(:); to = topo.to(:);
R = topo.R(:); X = topo.X(:);
line_of_child = zeros(nb,1); outLines = cell(nb,1);
for k=1:nl
    line_of_child(to(k))=k;
    outLines{from(k)}(end+1)=k;
end

outDir = './results/tables'; figDir = './results/figures';
if ~exist(outDir,'dir'), mkdir(outDir); end
if ~exist(figDir,'dir'), mkdir(figDir); end

fprintf('\n=== Module 11: ES Budget Sensitivity ===\n');

nB = numel(cfg.N_ES_max_list);
row_Budget = cfg.N_ES_max_list(:);
row_Feas   = false(nB,1);
row_NES    = zeros(nB,1);
row_Vmin   = NaN(nB,1);
row_Loss   = NaN(nB,1);
row_Rho    = NaN(nB,1);
row_Curt   = NaN(nB,1);
row_Buses  = cell(nB,1);

for bi = 1:nB
    N_max = cfg.N_ES_max_list(bi);
    fprintf('  N_ES_max = %d ...\n', N_max);

    v=sdpvar(nb,T,'full'); Pij=sdpvar(nl,T,'full');
    Qij=sdpvar(nl,T,'full'); ell=sdpvar(nl,T,'full');
    u=sdpvar(nb,T,'full'); z=binvar(nb,1); rho=sdpvar(nb,1);

    Con = [v>=cfg.Vmin^2, v<=cfg.Vmax^2, ell>=0, v(root,:)==1.0];
    Con = [Con, z(root)==0, rho(root)==0];
    Con = [Con, rho>=0, rho<=cfg.rho_max*z, sum(z)<=N_max];

    for j=1:nb
        if j==root, Con=[Con, u(j,:)==1]; continue; end
        for t=1:T
            Con=[Con, u(j,t)>=1-z(j)*(1-cfg.u_min), u(j,t)<=1];
            Con=[Con, 1-u(j,t)<=rho(j)];
        end
    end

    for t=1:T
        for j=1:nb
            if j==root, continue; end
            kpar=line_of_child(j); i=from(kpar); ch=outLines{j};
            Peff=P_CL(j,t)+u(j,t)*P_NCL(j,t);
            Qeff=Q_CL(j,t)+u(j,t)*Q_NCL(j,t);
            if isempty(ch), sumP=0; sumQ=0;
            else, sumP=sum(Pij(ch,t)); sumQ=sum(Qij(ch,t)); end
            Con=[Con, Pij(kpar,t)==Peff+sumP+R(kpar)*ell(kpar,t), ...
                      Qij(kpar,t)==Qeff+sumQ+X(kpar)*ell(kpar,t)];
            Con=[Con, v(j,t)==v(i,t)-2*(R(kpar)*Pij(kpar,t)+X(kpar)*Qij(kpar,t)) ...
                      +(R(kpar)^2+X(kpar)^2)*ell(kpar,t)];
            Con=[Con, cone([2*Pij(kpar,t);2*Qij(kpar,t);ell(kpar,t)-v(i,t)],ell(kpar,t)+v(i,t))];
        end
    end

    lc=0; for t=1:T, lc=lc+price(t)*sum(R.*ell(:,t)); end
    cc=0; for j=all_buses; for t=1:T
        cc=cc+cfg.c_curt*(1-u(j,t))*P_NCL(j,t); end; end
    Obj=cfg.c_loss*lc+cfg.c_es*sum(z)+cfg.c_rho*sum(rho.*S_NCL)+cc;

    sol=optimize(Con,Obj,ops);

    if sol.problem==0
        z_v=round(value(z)); rho_v=value(rho); u_v=value(u);
        v_v=sqrt(max(value(v),0)); ell_v=value(ell);
        sel=find(z_v>0.5)';
        row_Feas(bi)=true;
        row_NES(bi)=sum(z_v);
        row_Vmin(bi)=min(v_v(:));
        row_Loss(bi)=sum(sum(R.*ell_v));
        row_Rho(bi)=sum(rho_v);
        curt_v=[];
        for j=sel, curt_v(end+1)=mean(1-u_v(j,:)); end %#ok<AGROW>
        row_Curt(bi)=mean(curt_v);
        row_Buses{bi}=sel;
        fprintf('    FEASIBLE  NES=%d  Vmin=%.4f  Buses=%s\n',sum(z_v),min(v_v(:)),mat2str(sel));
    else
        row_Buses{bi}=[];
        fprintf('    INFEASIBLE\n');
    end
end

sel_str=cellfun(@mat2str,row_Buses,'UniformOutput',false);
T_out=table(row_Budget,row_Feas,row_NES,row_Vmin,row_Loss,row_Rho,row_Curt,sel_str,...
    'VariableNames',{'N_ES_max','Feasible','N_ES_used','Vmin_pu','TotalLoss_pu',...
                     'SumRho','MeanCurt','SelectedBuses'});
writetable(T_out,fullfile(outDir,'es_budget_sensitivity.csv'));
fprintf('Saved: results/tables/es_budget_sensitivity.csv\n');

fig1=figure('Visible','off');
bar(row_Budget,row_Vmin,'FaceColor',[0.2 0.6 0.4]);
hold on; yline(0.95,'r--','LineWidth',1.5,'Label','V_{min}=0.95 pu'); hold off;
xlabel('ES Budget (N_{ES,max})'); ylabel('Minimum Voltage (p.u.)');
title('ES Budget Sensitivity: Vmin vs Budget'); grid on;
saveas(fig1,fullfile(figDir,'es_budget_vs_min_voltage.png')); close(fig1);

fig2=figure('Visible','off');
bar(row_Budget,row_Loss,'FaceColor',[0.3 0.4 0.8]);
xlabel('ES Budget'); ylabel('Total Network Loss (p.u.)');
title('ES Budget Sensitivity: Loss vs Budget'); grid on;
saveas(fig2,fullfile(figDir,'es_budget_vs_loss.png')); close(fig2);

fig3=figure('Visible','off');
bar(row_Budget,double(row_Feas),'FaceColor',[0.5 0.8 0.3]);
xlabel('ES Budget'); ylabel('Feasible (1=yes)');
title('ES Budget Sensitivity: Feasibility'); grid on; ylim([0 1.3]);
saveas(fig3,fullfile(figDir,'es_budget_feasibility.png')); close(fig3);

fprintf('\nModule 11 complete.\n');
