%% run_ncl_pf_sensitivity.m
% MODULE 13 — NCL Power Factor Sensitivity
%
% Studies whether resistive vs inductive NCL affects ES voltage support.
% Reference ES literature distinguishes NCL type because the ES physical
% mechanism differs; at OPF level, NCL PF changes the Q_NCL profile.
%
% Cases:
%   NCL-R    PF = 1.00  (pure resistive)
%   NCL-L1   PF = 0.95 lagging
%   NCL-L2   PF = 0.90 lagging
%   NCL-L3   PF = 0.85 lagging
%
% Output:
%   results/tables/ncl_pf_sensitivity.csv
%   results/figures/ncl_pf_vs_min_voltage.png
%   results/figures/ncl_pf_vs_es_capacity.png
%   results/figures/ncl_pf_vs_loss.png

clear; clc; close all;
addpath(genpath('./src'));

cfg.load_multiplier = 1.0;
cfg.alpha_ncl       = 0.30;
cfg.u_min           = 0.20;
cfg.rho_max         = 0.80;
cfg.N_ES_max        = 10;
cfg.pf_list         = [1.00, 0.95, 0.90, 0.85];
cfg.pf_labels       = {'NCL-R (PF=1.00)','NCL-L1 (PF=0.95)','NCL-L2 (PF=0.90)','NCL-L3 (PF=0.85)'};
cfg.Vmin=0.95; cfg.Vmax=1.05;
cfg.c_loss=1.0; cfg.c_es=0.10; cfg.c_rho=0.05; cfg.c_curt=0.50;
cfg.time_limit=300;

caseDir='./mp_export_case33bw';
branchCsv=fullfile(caseDir,'branch.csv'); loadsCsv=fullfile(caseDir,'loads_base.csv');
topo=build_distflow_topology_from_branch_csv(branchCsv,1);
loads=build_24h_load_profile_from_csv(loadsCsv,'system',true,false);
loads.P24=cfg.load_multiplier*loads.P24; loads.Q24=cfg.load_multiplier*loads.Q24;

nb=topo.nb; T=24; root=topo.root; nl=topo.nl_tree;
from=topo.from(:); to=topo.to(:); R=topo.R(:); X=topo.X(:);
price=ones(T,1); price(1:6)=0.6; price(7:16)=1.0; price(17:21)=1.8; price(22:24)=0.9;

line_of_child=zeros(nb,1); outLines=cell(nb,1);
for k=1:nl; line_of_child(to(k))=k; outLines{from(k)}(end+1)=k; end
all_buses=setdiff(1:nb,root);

ops=sdpsettings('solver','gurobi','verbose',0);
ops.gurobi.TimeLimit=cfg.time_limit; ops.gurobi.MIPGap=0.01;

outDir='./results/tables'; figDir='./results/figures';
if ~exist(outDir,'dir'),mkdir(outDir);end; if ~exist(figDir,'dir'),mkdir(figDir);end

fprintf('\n=== Module 13: NCL Power Factor Sensitivity ===\n');

nPF=numel(cfg.pf_list);
row_PF=cfg.pf_list(:); row_Feas=false(nPF,1); row_NES=zeros(nPF,1);
row_Vmin=NaN(nPF,1); row_Loss=NaN(nPF,1); row_TotRho=NaN(nPF,1);
row_Curt=NaN(nPF,1); row_Buses=cell(nPF,1);

for pi=1:nPF
    pf=cfg.pf_list(pi);
    fprintf('  NCL PF = %.2f ...\n', pf);

    cl_ncl=split_cl_ncl_load(loads,cfg.alpha_ncl,all_buses,pf);
    P_CL=cl_ncl.P_CL; Q_CL=cl_ncl.Q_CL;
    P_NCL=cl_ncl.P_NCL; Q_NCL=cl_ncl.Q_NCL;
    S_NCL=sqrt(mean(P_NCL,2).^2+mean(Q_NCL,2).^2);

    v=sdpvar(nb,T,'full'); Pij=sdpvar(nl,T,'full');
    Qij=sdpvar(nl,T,'full'); ell=sdpvar(nl,T,'full');
    u=sdpvar(nb,T,'full'); z=binvar(nb,1); rho=sdpvar(nb,1);

    Con=[v>=cfg.Vmin^2,v<=cfg.Vmax^2,ell>=0,v(root,:)==1.0];
    Con=[Con,z(root)==0,rho(root)==0,rho>=0,rho<=cfg.rho_max*z,sum(z)<=cfg.N_ES_max];
    for j=1:nb
        if j==root, Con=[Con,u(j,:)==1]; continue; end
        for t=1:T
            Con=[Con,u(j,t)>=1-z(j)*(1-cfg.u_min),u(j,t)<=1,1-u(j,t)<=rho(j)];
        end
    end
    for t=1:T; for j=1:nb; if j==root, continue; end
        kpar=line_of_child(j); i=from(kpar); ch=outLines{j};
        Peff=P_CL(j,t)+u(j,t)*P_NCL(j,t); Qeff=Q_CL(j,t)+u(j,t)*Q_NCL(j,t);
        if isempty(ch),sumP=0;sumQ=0; else,sumP=sum(Pij(ch,t));sumQ=sum(Qij(ch,t));end
        Con=[Con,Pij(kpar,t)==Peff+sumP+R(kpar)*ell(kpar,t),...
                 Qij(kpar,t)==Qeff+sumQ+X(kpar)*ell(kpar,t)];
        Con=[Con,v(j,t)==v(i,t)-2*(R(kpar)*Pij(kpar,t)+X(kpar)*Qij(kpar,t))+(R(kpar)^2+X(kpar)^2)*ell(kpar,t)];
        Con=[Con,cone([2*Pij(kpar,t);2*Qij(kpar,t);ell(kpar,t)-v(i,t)],ell(kpar,t)+v(i,t))];
    end; end

    lc=0; for t=1:T, lc=lc+price(t)*sum(R.*ell(:,t)); end
    cc=0; for j=all_buses; for t=1:T; cc=cc+cfg.c_curt*(1-u(j,t))*P_NCL(j,t); end; end
    Obj=cfg.c_loss*lc+cfg.c_es*sum(z)+cfg.c_rho*sum(rho.*S_NCL)+cc;
    sol=optimize(Con,Obj,ops);

    if sol.problem==0
        z_v=round(value(z)); u_v=value(u); v_v=sqrt(max(value(v),0));
        ell_v=value(ell); rho_v=value(rho); sel=find(z_v>0.5)';
        row_Feas(pi)=true; row_NES(pi)=sum(z_v);
        row_Vmin(pi)=min(v_v(:)); row_Loss(pi)=sum(sum(R.*ell_v));
        row_TotRho(pi)=sum(rho_v); row_Buses{pi}=sel;
        cv=[]; for j=sel, cv(end+1)=mean(1-u_v(j,:)); end
        row_Curt(pi)=mean(cv);
        fprintf('    FEASIBLE  NES=%d  Vmin=%.4f  TotRho=%.3f\n',sum(z_v),min(v_v(:)),sum(rho_v));
    else
        row_Buses{pi}=[];
        fprintf('    INFEASIBLE\n');
    end
end

sel_str=cellfun(@mat2str,row_Buses,'UniformOutput',false);
T_out=table(row_PF,row_Feas,row_NES,row_Vmin,row_Loss,row_TotRho,row_Curt,sel_str,...
    'VariableNames',{'NCL_PF','Feasible','N_ES_used','Vmin_pu','TotalLoss_pu','SumRho','MeanCurt','SelectedBuses'});
writetable(T_out,fullfile(outDir,'ncl_pf_sensitivity.csv'));

fig1=figure('Visible','off');
plot(row_PF,row_Vmin,'-o','LineWidth',1.5,'MarkerSize',7);
hold on; yline(0.95,'r--','LineWidth',1.5); hold off;
set(gca,'XDir','reverse'); xlabel('NCL Power Factor'); ylabel('Minimum Voltage (p.u.)');
title('NCL PF Sensitivity: Vmin'); grid on;
saveas(fig1,fullfile(figDir,'ncl_pf_vs_min_voltage.png')); close(fig1);

fig2=figure('Visible','off');
plot(row_PF,row_TotRho,'-s','LineWidth',1.5,'MarkerSize',7,'Color',[0.7 0.2 0.1]);
set(gca,'XDir','reverse'); xlabel('NCL Power Factor'); ylabel('Total rho (sum of ES sizes)');
title('NCL PF Sensitivity: Total ES Capacity'); grid on;
saveas(fig2,fullfile(figDir,'ncl_pf_vs_es_capacity.png')); close(fig2);

fig3=figure('Visible','off');
plot(row_PF,row_Loss,'-^','LineWidth',1.5,'MarkerSize',7,'Color',[0.2 0.4 0.7]);
set(gca,'XDir','reverse'); xlabel('NCL Power Factor'); ylabel('Total Loss (p.u.)');
title('NCL PF Sensitivity: Network Loss'); grid on;
saveas(fig3,fullfile(figDir,'ncl_pf_vs_loss.png')); close(fig3);

fprintf('\nModule 13 complete.\n');
