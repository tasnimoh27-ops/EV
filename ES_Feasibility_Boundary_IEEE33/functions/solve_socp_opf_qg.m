function res = solve_socp_opf_qg(topo, loads, params)
%SOLVE_SOCP_OPF_QG  SOCP OPF with reactive power support only (no ES).
%
% Traditional reactive support benchmark.
% Adds continuous Qg variables at candidate buses to minimise losses
% subject to voltage constraints.
%
% params fields:
%   .Vmin          lower voltage bound (default 0.95)
%   .Vmax          upper voltage bound (default 1.05)
%   .Qg_max_pu     per-bus Qg capacity in pu (scalar applied to all buses)
%   .Qg_buses      buses with Qg (default: all non-slack)
%   .price         T×1 TOU price vector
%   .soft_voltage  logical (default false)
%   .lambda_sv     voltage-slack penalty (default 1e4)
%   .time_limit    solver time limit (default 300)

if nargin < 3, params = struct(); end
Vmin  = getf(params,'Vmin',0.95);
Vmax  = getf(params,'Vmax',1.05);
T     = 24;
nb    = topo.nb;
nl    = topo.nl_tree;
root  = topo.root;
from  = topo.from(:);
R     = topo.R(:);
X     = topo.X(:);

Pd = loads.P24;
Qd = loads.Q24;

price = getf(params,'price', ones(T,1));
price = price(:);

Qg_buses  = getf(params,'Qg_buses', setdiff(1:nb, root)');
Qg_max_pu = getf(params,'Qg_max_pu', 0.10);   % 10% of Sbase per bus

ops = sdpsettings('solver','gurobi','verbose',0);
ops.gurobi.TimeLimit = getf(params,'time_limit',300);

% -------------------------------------------------------------------------
%  VARIABLES
% -------------------------------------------------------------------------
v   = sdpvar(nb, T, 'full');
Pij = sdpvar(nl, T, 'full');
Qij = sdpvar(nl, T, 'full');
ell = sdpvar(nl, T, 'full');
Qg  = sdpvar(nb, T, 'full');   % reactive support (zero at non-Qg buses)

if getf(params,'soft_voltage',false)
    sv = sdpvar(nb, T, 'full');
end

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
if getf(params,'soft_voltage',false)
    Con = [Con, sv >= 0, v + sv >= Vmin^2];
else
    Con = [Con, v >= Vmin^2];
end
Con = [Con, v <= Vmax^2, ell >= 0];
Con = [Con, v(root,:) == 1.0];

% Qg bounds
Con = [Con, Qg >= 0, Qg <= Qg_max_pu];
Qg_mask = zeros(nb,1);
Qg_mask(Qg_buses) = 1;
for j = 1:nb
    if ~Qg_mask(j)
        Con = [Con, Qg(j,:) == 0];
    end
end

% DistFlow
for t = 1:T
    for j = 1:nb
        if j == root, continue; end
        kpar = line_of_child(j);
        i    = from(kpar);
        ch   = outLines{j};
        if isempty(ch), sumP=0; sumQ=0;
        else, sumP=sum(Pij(ch,t)); sumQ=sum(Qij(ch,t)); end

        Con = [Con, ...
            Pij(kpar,t) == Pd(j,t) + sumP + R(kpar)*ell(kpar,t), ...
            Qij(kpar,t) == Qd(j,t) - Qg(j,t) + sumQ + X(kpar)*ell(kpar,t), ...
            v(j,t) == v(i,t) - 2*(R(kpar)*Pij(kpar,t)+X(kpar)*Qij(kpar,t)) ...
                             + (R(kpar)^2+X(kpar)^2)*ell(kpar,t), ...
            cone([2*Pij(kpar,t); 2*Qij(kpar,t); ell(kpar,t)-v(i,t)], ...
                  ell(kpar,t)+v(i,t))];
    end
end

% -------------------------------------------------------------------------
%  OBJECTIVE
% -------------------------------------------------------------------------
lossCost = 0;
for t = 1:T
    lossCost = lossCost + price(t)*sum(R.*ell(:,t));
end
svCost = 0;
if getf(params,'soft_voltage',false)
    svCost = getf(params,'lambda_sv',1e4)*sum(sum(sv));
end
Obj = lossCost + svCost;

% -------------------------------------------------------------------------
%  SOLVE
% -------------------------------------------------------------------------
sol = optimize(Con, Obj, ops);
res = struct();
res.feasible  = (sol.problem == 0);
res.sol_code  = sol.problem;
res.sol_info  = sol.info;

if res.feasible
    v_val   = value(v);
    V_val   = sqrt(max(v_val,0));
    ell_val = value(ell);
    Qg_val  = value(Qg);
    loss_t2 = arrayfun(@(t) sum(R.*ell_val(:,t)), 1:T)';
    Vmin_t  = min(V_val)';
    [Vmin_v, VminBus] = min(V_val,[],1);

    res.V_val       = V_val;
    res.Qg_val      = Qg_val;
    res.loss_t      = loss_t2;
    res.total_loss  = sum(loss_t2);
    res.Vmin_t      = Vmin_t;
    res.VminBus_t   = VminBus';
    res.Vmin_24h    = min(Vmin_t);
    res.worst_hour  = find(Vmin_t==min(Vmin_t),1);
    res.total_Qg    = sum(Qg_val(:));
    res.max_sv      = 0;
    if getf(params,'soft_voltage',false)
        res.max_sv = max(max(value(sv)));
    end
    fprintf('  Qg-SOCP: Vmin=%.4f (h%d) | Loss=%.5f | Qg_total=%.4f\n',...
        res.Vmin_24h, res.worst_hour, res.total_loss, res.total_Qg);
else
    res.V_val      = NaN(nb,T);
    res.Qg_val     = NaN(nb,T);
    res.loss_t     = NaN(T,1);
    res.total_loss = NaN;
    res.Vmin_t     = NaN(T,1);
    res.VminBus_t  = NaN(T,1);
    res.Vmin_24h   = NaN;
    res.worst_hour = NaN;
    res.total_Qg   = NaN;
    res.max_sv     = NaN;
    fprintf('  Qg-SOCP: INFEASIBLE | Code=%d\n', sol.problem);
end
end

function v = getf(s,f,d)
if isfield(s,f), v=s.(f); else, v=d; end
end
