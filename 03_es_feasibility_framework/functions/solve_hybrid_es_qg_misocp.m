function res = solve_hybrid_es_qg_misocp(topo, loads, params)
%SOLVE_HYBRID_ES_QG_MISOCP  Hybrid ES + limited Qg MISOCP.
%
% Extends solve_es_budget_misocp with reactive support (Qg) variables.
% Tests whether limited reactive support reduces required ES count or NCL curtailment.
%
% Additional params fields vs solve_es_budget_misocp:
%   .Qg_limit_frac  fraction of reference Qg capacity [0,1] (default 0)
%                   0 = ES only; 1 = full Qg capacity
%   .Qg_ref_pu      per-bus reference Qg max in pu (default 0.05 * bus peak load)
%   .Qg_buses       buses with reactive support (default: all non-slack)

T    = 24;
nb   = topo.nb;
nl   = topo.nl_tree;
root = topo.root;
from = topo.from(:);
R    = topo.R(:);
X    = topo.X(:);

Pd = loads.P24;
Qd = loads.Q24;

rho          = getf(params,'rho',0.50);
u_min        = getf(params,'u_min',0.20);
N_max        = getf(params,'N_ES_max',32);
Vmin_lim     = getf(params,'Vmin',0.95);
Vmax_lim     = getf(params,'Vmax',1.05);
soft_v       = getf(params,'soft_voltage',true);
mode         = getf(params,'obj_mode','feasibility');
w_loss       = getf(params,'w_loss',1.0);
w_ES         = getf(params,'w_ES',0.01);
w_curt       = getf(params,'w_curt',10.0);
w_vio        = getf(params,'w_vio',1e4);
t_lim        = getf(params,'time_limit',300);
mip_gap      = getf(params,'MIPGap',0.01);
price        = getf(params,'price', ones(T,1)); price=price(:);
Qg_frac      = getf(params,'Qg_limit_frac',0.0);
Qg_buses_in  = getf(params,'Qg_buses', setdiff(1:nb,root)');
cand_buses   = getf(params,'candidate_buses', setdiff(1:nb,root)');

% Reference Qg capacity: fraction of peak load at each bus
P_peak = max(Pd,[],2);
Qg_ref = getf(params,'Qg_ref_pu', 0.05 * P_peak);  % 5% of peak P per bus
Qg_max = Qg_frac * Qg_ref;    % nb×1

% Load decomposition
P_CL  = (1-rho)*Pd;  Q_CL = (1-rho)*Qd;
P_NCL = rho*Pd;      Q_NCL = rho*Qd;

% -------------------------------------------------------------------------
%  VARIABLES
% -------------------------------------------------------------------------
z   = binvar(nb, 1, 'full');
c   = sdpvar(nb, T, 'full');
Qg  = sdpvar(nb, T, 'full');
v   = sdpvar(nb, T, 'full');
Pij = sdpvar(nl, T, 'full');
Qij = sdpvar(nl, T, 'full');
ell = sdpvar(nl, T, 'full');
if soft_v, sv = sdpvar(nb, T, 'full'); end

% -------------------------------------------------------------------------
%  ADJACENCY
% -------------------------------------------------------------------------
outLines      = cell(nb,1);
line_of_child = zeros(nb,1);
for k = 1:nl
    outLines{from(k)}(end+1) = k;
    line_of_child(topo.to(k)) = k;
end

% -------------------------------------------------------------------------
%  CONSTRAINTS
% -------------------------------------------------------------------------
Con = [];
if soft_v
    Con = [Con, sv >= 0, v + sv >= Vmin_lim^2];
else
    Con = [Con, v >= Vmin_lim^2];
end
Con = [Con, v <= Vmax_lim^2, ell >= 0, v(root,:) == 1.0];

% z only at candidates
non_cand = setdiff(1:nb, cand_buses(:)');
if ~isempty(non_cand), Con = [Con, z(non_cand) == 0]; end
Con = [Con, sum(z) <= N_max];

% Curtailment coupling
Con = [Con, c >= 0];
for i = 1:nb
    Con = [Con, c(i,:) <= (1-u_min)*z(i)];
end

% Qg bounds (no binary — continuous reactive support)
Con = [Con, Qg >= 0];
for i = 1:nb
    if ismember(i, Qg_buses_in(:)') && Qg_max(i) > 1e-9
        Con = [Con, Qg(i,:) <= Qg_max(i)];
    else
        Con = [Con, Qg(i,:) == 0];
    end
end

% DistFlow
for t = 1:T
    for j = 1:nb
        if j==root, continue; end
        kpar = line_of_child(j); i = from(kpar);
        ch = outLines{j};
        if isempty(ch), sumP=0; sumQ=0;
        else, sumP=sum(Pij(ch,t)); sumQ=sum(Qij(ch,t)); end

        Peff = P_CL(j,t) + (1-c(j,t))*P_NCL(j,t);
        Qeff = Q_CL(j,t) + (1-c(j,t))*Q_NCL(j,t) - Qg(j,t);

        Con = [Con, ...
            Pij(kpar,t) == Peff + sumP + R(kpar)*ell(kpar,t), ...
            Qij(kpar,t) == Qeff + sumQ + X(kpar)*ell(kpar,t), ...
            v(j,t) == v(i,t) - 2*(R(kpar)*Pij(kpar,t)+X(kpar)*Qij(kpar,t)) ...
                    + (R(kpar)^2+X(kpar)^2)*ell(kpar,t), ...
            cone([2*Pij(kpar,t);2*Qij(kpar,t);ell(kpar,t)-v(i,t)], ...
                  ell(kpar,t)+v(i,t))];
    end
end

% -------------------------------------------------------------------------
%  OBJECTIVE
% -------------------------------------------------------------------------
lossCost = 0;
for t=1:T, lossCost = lossCost + price(t)*sum(R.*ell(:,t)); end
curtCost = 0;
for t=1:T, curtCost = curtCost + sum(c(:,t).*P_NCL(:,t)); end
svCost = 0;
if soft_v, svCost = sum(sum(sv)); end

if strcmp(mode,'feasibility')
    Obj = svCost + 1e-4*lossCost;
else
    Obj = w_loss*lossCost + w_ES*sum(z) + w_curt*curtCost + w_vio*svCost;
end

% -------------------------------------------------------------------------
%  SOLVE
% -------------------------------------------------------------------------
ops_yalmip = sdpsettings('solver','gurobi','verbose',0);
ops_yalmip.gurobi.TimeLimit = t_lim;
ops_yalmip.gurobi.MIPGap    = mip_gap;
t_s = tic;
sol = optimize(Con, Obj, ops_yalmip);
solve_time = toc(t_s);

% -------------------------------------------------------------------------
%  EXTRACT
% -------------------------------------------------------------------------
res = struct();
res.feasible   = (sol.problem==0);
res.sol_code   = sol.problem;
res.sol_info   = sol.info;
res.solve_time = solve_time;
res.rho=rho; res.u_min=u_min; res.N_ES_max=N_max;
res.Qg_limit_frac = Qg_frac;

if res.feasible || sol.problem==4
    z_val   = round(value(z));
    c_val   = max(0,value(c));
    v_val   = value(v);
    ell_val = value(ell);
    Qg_val  = value(Qg);
    V_val   = sqrt(max(v_val,0));
    es_sel  = find(z_val>0.5);
    sv_val  = zeros(nb,T);
    if soft_v, sv_val=max(0,value(sv)); end
    loss_t  = arrayfun(@(t)sum(R.*ell_val(:,t)),1:T)';
    Vmin_t  = min(V_val)';
    [~,VminBus_t] = min(V_val,[],1);
    [Vmin_24h,wh] = min(Vmin_t);
    mean_curt = 0;
    if ~isempty(es_sel), mean_curt = mean(c_val(es_sel,:),'all'); end
    res.z_val=z_val; res.es_buses=es_sel'; res.n_es=numel(es_sel);
    res.c_val=c_val; res.u_val=1-c_val; res.Qg_val=Qg_val;
    res.V_val=V_val; res.sv_val=sv_val; res.loss_t=loss_t;
    res.total_loss=sum(loss_t); res.Vmin_t=Vmin_t; res.VminBus_t=VminBus_t';
    res.Vmin_24h=Vmin_24h; res.worst_hour=wh; res.worst_bus=VminBus_t(wh);
    res.mean_curt=mean_curt; res.max_curt=max(c_val(:));
    res.total_sv=sum(sv_val(:)); res.max_sv=max(sv_val(:));
    res.total_Qg=sum(Qg_val(:)); res.mean_Qg=mean(Qg_val(:));
    res.voltage_ok = (res.total_sv<=1e-6);
    fprintf('  Hybrid: N_ES=%d Qg_frac=%.2f | Vmin=%.4f | Loss=%.5f | Curt=%.1f%% | Qg=%.4f\n',...
        numel(es_sel),Qg_frac,Vmin_24h,sum(loss_t),100*mean_curt,sum(Qg_val(:)));
else
    res.es_buses=[]; res.n_es=NaN; res.V_val=NaN(nb,T);
    res.total_loss=NaN; res.Vmin_24h=NaN; res.worst_hour=NaN; res.worst_bus=NaN;
    res.mean_curt=NaN; res.max_curt=NaN; res.total_sv=NaN; res.max_sv=NaN;
    res.total_Qg=NaN; res.voltage_ok=false;
    fprintf('  Hybrid: INFEASIBLE | Code=%d\n', sol.problem);
end
end

function v = getf(s,f,d)
if isfield(s,f)&&~isempty(s.(f)), v=s.(f); else, v=d; end
end
