function res = solve_es_budget_misocp(topo, loads, params)
%SOLVE_ES_BUDGET_MISOCP  Budget-constrained MISOCP for ES placement.
%
% Main technical contribution. Jointly optimises binary ES installation
% decisions and continuous NCL curtailment to restore voltage feasibility
% with the fewest ES devices.
%
% FORMULATION
% -----------
%   z(i)     in {0,1}    — ES installed at bus i
%   c(i,t)   in [0,1]    — NCL curtailment fraction at bus i, hour t
%   v(i,t)   >= 0        — squared voltage (pu^2)
%   Pij,Qij,ell          — branch flows and squared current
%   sv(i,t)  >= 0        — voltage slack (soft mode only)
%
% Load model:
%   P_eff(i,t) = P_CL(i,t) + (1-c(i,t))*P_NCL(i,t)
%              = P_load(i,t) - c(i,t)*P_NCL(i,t)    [linear in c]
%
% Key linking constraint (linear):
%   c(i,t) <= (1 - u_min) * z(i)
%   → if z(i)=0: c(i,t)=0 (no ES action allowed)
%   → if z(i)=1: c(i,t) can reach up to (1-u_min)
%
% Budget:  sum(z) <= N_ES_max
%
% Objective modes:
%   'feasibility' — minimise total voltage slack (sum of sv > 0)
%   'planning'    — weighted sum of loss + ES count + curtailment + slack
%
% PARAMS FIELDS
%   .rho            NCL fraction (default 0.50)
%   .u_min          min NCL service level (default 0.20)
%   .N_ES_max       max ES devices (default 32)
%   .Vmin           voltage lower bound (default 0.95)
%   .Vmax           voltage upper bound (default 1.05)
%   .soft_voltage   logical — use soft voltage (default true for feasibility)
%   .obj_mode       'feasibility' or 'planning' (default 'feasibility')
%   .w_loss         weight: losses (default 1)
%   .w_ES           weight: ES count penalty (default 0.01)
%   .w_curt         weight: NCL curtailment (default 10)
%   .w_vio          weight: voltage slack (default 1e4)
%   .price          T×1 TOU price vector
%   .candidate_buses buses eligible for ES (default all non-slack)
%   .time_limit     solver time limit seconds (default 300)
%   .MIPGap         MIP optimality gap (default 0.01)
%   .verbose        0 or 1 (default 0)

T    = 24;
nb   = topo.nb;
nl   = topo.nl_tree;
root = topo.root;
from = topo.from(:);
R    = topo.R(:);
X    = topo.X(:);

Pd = loads.P24;    % nb×T
Qd = loads.Q24;

% -------------------------------------------------------------------------
%  PARAMETER DEFAULTS
% -------------------------------------------------------------------------
rho      = getf(params,'rho',0.50);
u_min    = getf(params,'u_min',0.20);
N_max    = getf(params,'N_ES_max',32);
Vmin_lim = getf(params,'Vmin',0.95);
Vmax_lim = getf(params,'Vmax',1.05);
soft_v   = getf(params,'soft_voltage',true);
mode     = getf(params,'obj_mode','feasibility');
w_loss   = getf(params,'w_loss',1.0);
w_ES     = getf(params,'w_ES',0.01);
w_curt   = getf(params,'w_curt',10.0);
w_vio    = getf(params,'w_vio',1e4);
t_lim    = getf(params,'time_limit',300);
mip_gap  = getf(params,'MIPGap',0.01);
verb     = getf(params,'verbose',0);

price = getf(params,'price', ones(T,1));
price = price(:);

cand_buses = getf(params,'candidate_buses', setdiff(1:nb,root)');
cand_buses = cand_buses(:)';   % row vector

% -------------------------------------------------------------------------
%  LOAD DECOMPOSITION
%  P_CL(i,t)  = (1-rho)*P(i,t)  — critical load, never curtailed
%  P_NCL(i,t) = rho*P(i,t)      — non-critical, curtailed by c(i,t)
% -------------------------------------------------------------------------
P_CL  = (1 - rho) * Pd;
Q_CL  = (1 - rho) * Qd;
P_NCL = rho * Pd;
Q_NCL = rho * Qd;

% -------------------------------------------------------------------------
%  DECISION VARIABLES
% -------------------------------------------------------------------------
z   = binvar(nb, 1, 'full');        % binary ES installation
c   = sdpvar(nb, T, 'full');        % NCL curtailment fraction [0, (1-u_min)*z]
v   = sdpvar(nb, T, 'full');        % squared voltage
Pij = sdpvar(nl, T, 'full');
Qij = sdpvar(nl, T, 'full');
ell = sdpvar(nl, T, 'full');

if soft_v
    sv = sdpvar(nb, T, 'full');     % voltage slack for soft lower bound
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

% Voltage bounds
if soft_v
    Con = [Con, sv >= 0];
    Con = [Con, v + sv >= Vmin_lim^2];    % soft lower
else
    Con = [Con, v >= Vmin_lim^2];          % hard lower
end
Con = [Con, v <= Vmax_lim^2, ell >= 0];
Con = [Con, v(root,:) == 1.0];

% z only at candidate buses; force z=0 elsewhere
non_cand = setdiff(1:nb, cand_buses);
if ~isempty(non_cand)
    Con = [Con, z(non_cand) == 0];
end

% Curtailment coupling: c(i,t) <= (1-u_min)*z(i)   [KEY LINKING CONSTRAINT]
% Also c >= 0
Con = [Con, c >= 0];
for i = 1:nb
    Con = [Con, c(i,:) <= (1-u_min) * z(i)];
end

% Budget constraint
Con = [Con, sum(z) <= N_max];

% DistFlow power balance, voltage drop, SOCP cone
for t = 1:T
    for j = 1:nb
        if j == root, continue; end

        kpar = line_of_child(j);
        i    = from(kpar);
        ch   = outLines{j};
        if isempty(ch), sumP=0; sumQ=0;
        else, sumP=sum(Pij(ch,t)); sumQ=sum(Qij(ch,t)); end

        % Effective demand after ES action (linear in c — P_NCL is constant)
        Peff = P_CL(j,t) + (1-c(j,t))*P_NCL(j,t);
        Qeff = Q_CL(j,t) + (1-c(j,t))*Q_NCL(j,t);

        Con = [Con, ...
            Pij(kpar,t) == Peff + sumP + R(kpar)*ell(kpar,t), ...
            Qij(kpar,t) == Qeff + sumQ + X(kpar)*ell(kpar,t), ...
            v(j,t) == v(i,t) ...
                    - 2*(R(kpar)*Pij(kpar,t) + X(kpar)*Qij(kpar,t)) ...
                    + (R(kpar)^2 + X(kpar)^2)*ell(kpar,t), ...
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

curtCost = 0;
for t = 1:T
    curtCost = curtCost + sum(c(:,t) .* P_NCL(:,t));
end

EScount  = sum(z);
svCost   = 0;
if soft_v
    svCost = sum(sum(sv));
end

if strcmp(mode,'feasibility')
    % Minimise total voltage deficit — find feasibility boundary
    Obj = svCost + 1e-4*lossCost;
else
    % Weighted planning objective
    Obj = w_loss*lossCost + w_ES*EScount + w_curt*curtCost + w_vio*svCost;
end

% -------------------------------------------------------------------------
%  SOLVE
% -------------------------------------------------------------------------
ops = sdpsettings('solver','gurobi','verbose',verb);
ops.gurobi.TimeLimit = t_lim;
ops.gurobi.MIPGap    = mip_gap;

t_solve = tic;
sol = optimize(Con, Obj, ops);
solve_time = toc(t_solve);

% -------------------------------------------------------------------------
%  EXTRACT RESULTS
% -------------------------------------------------------------------------
res = struct();
res.feasible   = (sol.problem == 0);
res.sol_code   = sol.problem;
res.sol_info   = sol.info;
res.solve_time = solve_time;
res.rho        = rho;
res.u_min      = u_min;
res.N_ES_max   = N_max;
res.obj_mode   = mode;

if res.feasible || sol.problem == 4   % code 4 = near-feasible (numerical)
    z_val   = round(value(z));     % round binary
    c_val   = max(0, value(c));
    v_val   = value(v);
    ell_val = value(ell);

    V_val   = sqrt(max(v_val, 0));
    u_val   = 1 - c_val;

    es_sel  = find(z_val > 0.5);

    sv_val  = zeros(nb,T);
    if soft_v, sv_val = max(0, value(sv)); end

    loss_t  = arrayfun(@(t) sum(R.*ell_val(:,t)), 1:T)';
    Vmin_t  = min(V_val)';
    [~, VminBus_t] = min(V_val,[],1);
    [Vmin_24h, worst_hour] = min(Vmin_t);

    total_curt  = sum(sum(c_val .* P_NCL));
    mean_curt   = mean(c_val(es_sel,:), 'all');
    if isempty(es_sel), mean_curt = 0; end
    max_curt    = max(c_val(:));
    total_sv    = sum(sv_val(:));
    max_sv      = max(sv_val(:));

    try
        mip_gap_v = sol.solveroutput.objbound;  % Gurobi bound
    catch
        mip_gap_v = NaN;
    end

    res.z_val        = z_val;
    res.es_buses     = es_sel';
    res.n_es         = numel(es_sel);
    res.c_val        = c_val;
    res.u_val        = u_val;
    res.V_val        = V_val;
    res.sv_val       = sv_val;
    res.loss_t       = loss_t;
    res.total_loss   = sum(loss_t);
    res.Vmin_t       = Vmin_t;
    res.VminBus_t    = VminBus_t';
    res.Vmin_24h     = Vmin_24h;
    res.worst_hour   = worst_hour;
    res.worst_bus    = VminBus_t(worst_hour);
    res.total_curt   = total_curt;
    res.mean_curt    = mean_curt;
    res.max_curt     = max_curt;
    res.total_sv     = total_sv;
    res.max_sv       = max_sv;
    res.mip_gap      = mip_gap_v;

    % Mark truly feasible only if soft voltage slack is negligible
    res.voltage_ok = (total_sv <= 1e-6);

    fprintf('  MISOCP: z=%d ES | Vmin=%.4f (h%d,b%d) | Loss=%.5f | Curt=%.1f%% | SV=%.2e | t=%.1fs\n',...
        numel(es_sel), Vmin_24h, worst_hour, VminBus_t(worst_hour), ...
        sum(loss_t), 100*mean_curt, total_sv, solve_time);
else
    % Infeasible — populate NaN
    res.z_val      = NaN(nb,1);
    res.es_buses   = [];
    res.n_es       = NaN;
    res.c_val      = NaN(nb,T);
    res.u_val      = NaN(nb,T);
    res.V_val      = NaN(nb,T);
    res.sv_val     = NaN(nb,T);
    res.loss_t     = NaN(T,1);
    res.total_loss = NaN;
    res.Vmin_t     = NaN(T,1);
    res.VminBus_t  = NaN(T,1);
    res.Vmin_24h   = NaN;
    res.worst_hour = NaN;
    res.worst_bus  = NaN;
    res.total_curt = NaN;
    res.mean_curt  = NaN;
    res.max_curt   = NaN;
    res.total_sv   = NaN;
    res.max_sv     = NaN;
    res.mip_gap    = NaN;
    res.voltage_ok = false;

    fprintf('  MISOCP: INFEASIBLE | Code=%d | t=%.1fs\n', sol.problem, solve_time);
end
end

function v = getf(s,f,d)
if isfield(s,f) && ~isempty(s.(f)), v=s.(f); else, v=d; end
end
