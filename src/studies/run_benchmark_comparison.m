%% run_benchmark_comparison.m
% MODULE 14 — Benchmark Comparison
%
% Compares ES placement strategies:
%   B0: No ES
%   B1: Manual P1 — {18,33} (2 terminal buses)
%   B2: Manual P2 — {9,18,26,33} (4 buses)
%   B3: Manual P3 — VIS-top7 (7 buses)
%   B4: Greedy (up to 10 buses, fixed rho=0.60)
%   B5: Optimized MISOCP (N_max=10)
%   B6: All-bus ES (benchmark upper bound)
%
% All use same: alpha_ncl=0.30, u_min=0.20, Vmin=0.95
%
% Output:
%   results/tables/benchmark_comparison.csv
%   results/figures/benchmark_voltage_profiles.png
%   results/figures/benchmark_loss_comparison.png
%   results/figures/benchmark_es_count_comparison.png

clear; clc; close all;
addpath(genpath('./src'));

cfg.load_multiplier = 1.0;
cfg.alpha_ncl       = 0.30;
cfg.ncl_pf          = 1.00;
cfg.u_min           = 0.20;
cfg.rho_val         = 0.60;   % for manual + greedy
cfg.rho_max         = 0.80;   % for optimized
cfg.N_ES_max_opt    = 10;
cfg.Vmin=0.95; cfg.Vmax=1.05;
cfg.c_loss=1.0; cfg.c_es=0.10; cfg.c_rho=0.05; cfg.c_curt=0.50;
cfg.lambda_u=2.0;
cfg.time_limit=300;

caseDir='./mp_export_case33bw';
branchCsv=fullfile(caseDir,'branch.csv'); loadsCsv=fullfile(caseDir,'loads_base.csv');
topo=build_distflow_topology_from_branch_csv(branchCsv,1);
loads=build_24h_load_profile_from_csv(loadsCsv,'system',true,false);
loads.P24=cfg.load_multiplier*loads.P24; loads.Q24=cfg.load_multiplier*loads.Q24;

nb=topo.nb; T=24; root=topo.root;
price=ones(T,1); price(1:6)=0.6; price(7:16)=1.0; price(17:21)=1.8; price(22:24)=0.9;

ops=sdpsettings('solver','gurobi','verbose',0);
ops.gurobi.TimeLimit=cfg.time_limit; ops.gurobi.MIPGap=0.01;

% VIS ranking for P3
vis=calculate_voltage_impact_score(topo,loads,cfg.alpha_ncl);
vis_top7=vis.rank(1:7)';

all_buses=setdiff(1:nb,root);

outDir='./results/tables'; figDir='./results/figures';
if ~exist(outDir,'dir'),mkdir(outDir);end; if ~exist(figDir,'dir'),mkdir(figDir);end

fprintf('\n=== Module 14: Benchmark Comparison ===\n');

% Strategy definitions: {name, label, es_buses_or_'misocp', use_misocp}
strategies = {
    [],         'B0: No ES';
    [18,33],    'B1: Manual P1 {18,33}';
    [9,18,26,33],'B2: Manual P2 {9,18,26,33}';
    vis_top7,   'B3: Manual P3 VIS-top7';
    'greedy',   'B4: Greedy (N<=10)';
    'misocp',   'B5: Optimized MISOCP (N<=10)';
    all_buses,  'B6: All-bus (upper bound)';
};
nS=size(strategies,1);

row_Label=cell(nS,1); row_NES=zeros(nS,1); row_Feas=false(nS,1);
row_Vmin=NaN(nS,1); row_Loss=NaN(nS,1); row_Curt=NaN(nS,1);
V_profiles=NaN(nb,nS); row_Buses=cell(nS,1);

for si=1:nS
    es_def=strategies{si,1}; label=strategies{si,2};
    row_Label{si}=label;
    fprintf('  %s ...\n',label);

    if ischar(es_def) && strcmp(es_def,'greedy')
        % Run simplified greedy (max 10 steps, fixed rho)
        sel=[]; cur_Vmin=-Inf;
        for step=1:10
            remaining=setdiff(all_buses,sel);
            best_v=-Inf; best_b=-1;
            for j=remaining
                trial=[sel,j];
                p.name=sprintf('bm_greedy_%d',j); p.label='trial';
                p.es_buses=trial; p.rho_val=cfg.rho_val;
                p.u_min_val=cfg.u_min; p.lambda_u=cfg.lambda_u;
                p.Vmin=cfg.Vmin; p.Vmax=cfg.Vmax;
                p.soft_voltage=true; p.lambda_sv=1000;
                p.price=price; p.out_dir='';
                r=solve_es_socp_opf_case(p,topo,loads,ops);
                mv=min(r.Vmin_t);
                if mv>best_v, best_v=mv; best_b=j; end
            end
            if best_b<0, break; end
            sel(end+1)=best_b;
            if best_v>=cfg.Vmin-1e-4, break; end
        end
        % Final solve with selected
        if ~isempty(sel)
            p.name='bm_greedy_final'; p.label='Greedy final';
            p.es_buses=sel; p.rho_val=cfg.rho_val;
            p.u_min_val=cfg.u_min; p.lambda_u=cfg.lambda_u;
            p.Vmin=cfg.Vmin; p.Vmax=cfg.Vmax;
            p.soft_voltage=false; p.lambda_sv=0;
            p.price=price; p.out_dir='';
            res=solve_es_socp_opf_case(p,topo,loads,ops);
            row_Feas(si)=res.feasible; row_NES(si)=numel(sel);
            row_Vmin(si)=min(res.Vmin_t); row_Loss(si)=res.total_loss;
            row_Curt(si)=res.mean_curtailment; row_Buses{si}=sel;
            if res.feasible && ~any(isnan(res.V_val(:,20)))
                V_profiles(:,si)=res.V_val(:,20);
            end
        end

    elseif ischar(es_def) && strcmp(es_def,'misocp')
        % Inline MISOCP (same as Module 10 but single budget)
        nl=topo.nl_tree; from=topo.from(:); to=topo.to(:); R=topo.R(:); X=topo.X(:);
        lc2=zeros(nb,1); ols=cell(nb,1);
        for k=1:nl; lc2(to(k))=k; ols{from(k)}(end+1)=k; end
        cl_ncl=split_cl_ncl_load(loads,cfg.alpha_ncl,all_buses,cfg.ncl_pf);
        P_CL=cl_ncl.P_CL; Q_CL=cl_ncl.Q_CL; P_NCL=cl_ncl.P_NCL; Q_NCL=cl_ncl.Q_NCL;
        S_NCL=sqrt(mean(P_NCL,2).^2+mean(Q_NCL,2).^2);
        v=sdpvar(nb,T,'full'); Pij=sdpvar(nl,T,'full');
        Qij=sdpvar(nl,T,'full'); ell=sdpvar(nl,T,'full');
        u=sdpvar(nb,T,'full'); z=binvar(nb,1); rho=sdpvar(nb,1);
        Con=[v>=cfg.Vmin^2,v<=cfg.Vmax^2,ell>=0,v(root,:)==1.0];
        Con=[Con,z(root)==0,rho(root)==0,rho>=0,rho<=cfg.rho_max*z,sum(z)<=cfg.N_ES_max_opt];
        for j=1:nb; if j==root,Con=[Con,u(j,:)==1];continue;end
            for t=1:T; Con=[Con,u(j,t)>=1-z(j)*(1-cfg.u_min),u(j,t)<=1,1-u(j,t)<=rho(j)]; end; end
        for t=1:T; for j=1:nb; if j==root,continue;end
            k2=lc2(j); i=from(k2); ch=ols{j};
            Pe=P_CL(j,t)+u(j,t)*P_NCL(j,t); Qe=Q_CL(j,t)+u(j,t)*Q_NCL(j,t);
            if isempty(ch),sP=0;sQ=0; else,sP=sum(Pij(ch,t));sQ=sum(Qij(ch,t));end
            Con=[Con,Pij(k2,t)==Pe+sP+R(k2)*ell(k2,t),Qij(k2,t)==Qe+sQ+X(k2)*ell(k2,t)];
            Con=[Con,v(j,t)==v(i,t)-2*(R(k2)*Pij(k2,t)+X(k2)*Qij(k2,t))+(R(k2)^2+X(k2)^2)*ell(k2,t)];
            Con=[Con,cone([2*Pij(k2,t);2*Qij(k2,t);ell(k2,t)-v(i,t)],ell(k2,t)+v(i,t))];
        end; end
        lc3=0; for t=1:T,lc3=lc3+price(t)*sum(R.*ell(:,t));end
        cc=0; for j=all_buses;for t=1:T;cc=cc+cfg.c_curt*(1-u(j,t))*P_NCL(j,t);end;end
        Obj=cfg.c_loss*lc3+cfg.c_es*sum(z)+cfg.c_rho*sum(rho.*S_NCL)+cc;
        sol=optimize(Con,Obj,ops);
        if sol.problem==0
            z_v=round(value(z)); u_v=value(u); v_v=sqrt(max(value(v),0));
            ell_v=value(ell); sel=find(z_v>0.5)';
            row_Feas(si)=true; row_NES(si)=sum(z_v);
            row_Vmin(si)=min(v_v(:)); row_Loss(si)=sum(sum(R.*ell_v));
            cv=[]; for j=sel,cv(end+1)=mean(1-u_v(j,:));end
            row_Curt(si)=mean(cv); row_Buses{si}=sel;
            V_profiles(:,si)=v_v(:,20);
        end

    else
        % Manual fixed placement
        p.name=sprintf('bm_s%d',si); p.label=label;
        p.es_buses=es_def; p.rho_val=cfg.rho_val;
        p.u_min_val=cfg.u_min; p.lambda_u=cfg.lambda_u;
        p.Vmin=cfg.Vmin; p.Vmax=cfg.Vmax;
        p.soft_voltage=false; p.lambda_sv=0;
        p.price=price; p.out_dir='';
        res=solve_es_socp_opf_case(p,topo,loads,ops);
        row_Feas(si)=res.feasible; row_NES(si)=numel(es_def);
        if res.feasible
            row_Vmin(si)=min(res.Vmin_t); row_Loss(si)=res.total_loss;
            row_Curt(si)=res.mean_curtailment; row_Buses{si}=es_def;
            if ~any(isnan(res.V_val(:,20))), V_profiles(:,si)=res.V_val(:,20);end
        end
    end

    fprintf('    Feas=%d  NES=%d  Vmin=%.4f  Loss=%.5f\n', ...
        row_Feas(si),row_NES(si),row_Vmin(si),row_Loss(si));
end

sel_str=cellfun(@mat2str,row_Buses,'UniformOutput',false);
T_out=table(row_Label,row_Feas,row_NES,row_Vmin,row_Loss,row_Curt,sel_str,...
    'VariableNames',{'Strategy','Feasible','N_ES','Vmin_pu','TotalLoss_pu','MeanCurt','Buses'});
writetable(T_out,fullfile(outDir,'benchmark_comparison.csv'));
fprintf('Saved: results/tables/benchmark_comparison.csv\n');

% Figure 1: Voltage profiles comparison
fig1=figure('Visible','off'); hold on;
colors=lines(nS); styles={'-o','-s','-d','-^','-v','->','-<'};
for si=1:nS
    if ~any(isnan(V_profiles(:,si)))
        style=styles{mod(si-1,7)+1};
        plot(1:nb,V_profiles(:,si),style,'Color',colors(si,:),'LineWidth',1.2,...
            'DisplayName',row_Label{si});
    end
end
yline(0.95,'k--','LineWidth',1.5,'Label','V_{min}=0.95 pu');
hold off; xlabel('Bus Index'); ylabel('Voltage (p.u.)');
title('Benchmark: Voltage Profiles at Peak Hour');
legend('Location','southwest'); grid on; ylim([0.85 1.05]);
saveas(fig1,fullfile(figDir,'benchmark_voltage_profiles.png')); close(fig1);

% Figure 2: Loss comparison (bar)
fig2=figure('Visible','off');
bar(categorical(row_Label),row_Loss,'FaceColor',[0.3 0.5 0.8]);
xlabel('Strategy'); ylabel('Total Loss (p.u.)');
title('Benchmark: Total Network Loss Comparison'); grid on;
xtickangle(30);
saveas(fig2,fullfile(figDir,'benchmark_loss_comparison.png')); close(fig2);

% Figure 3: ES count
fig3=figure('Visible','off');
bar(categorical(row_Label),row_NES,'FaceColor',[0.7 0.4 0.2]);
xlabel('Strategy'); ylabel('Number of ES Units');
title('Benchmark: ES Unit Count Comparison'); grid on;
xtickangle(30);
saveas(fig3,fullfile(figDir,'benchmark_es_count_comparison.png')); close(fig3);

fprintf('\nModule 14 complete.\n');
