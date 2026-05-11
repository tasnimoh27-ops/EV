function res = solve_es1_misocp(topo, loads, params)
%SOLVE_ES1_MISOCP  ES-1 (Hou) reactive model MISOCP.
%
% Extends the basic ES curtailment model with independent reactive injection
% Q_es(i,t) from the ES inverter. In ES-1 (Hou et al.), the series-connected
% ES device can provide reactive compensation beyond proportional curtailment.
%
% Key difference vs solve_es_budget_misocp:
%   Basic ES: Qeff = Q_CL + (1-c)*Q_NCL       [Q reduced only via curtailment]
%   ES-1:     Qeff = Q_CL + (1-c)*Q_NCL - Q_es [+ independent reactive injection]
%
% VARIABLES
%   z(i)      in {0,1}                     ES installed at bus i
%   c(i,t)    in [0, (1-u_min)*z(i)]       NCL curtailment fraction
%   Q_es(i,t) in [0, Q_es_max*z(i)]        reactive injection from ES inverter
%   v,Pij,Qij,ell,sv                        DistFlow variables
%
% Q_es is bounded per-device (Q_es_max). The ES inverter reactive capacity
% is decoupled from curtailment level (sufficient inverter rating assumed).
% For tighter coupling, an SOC apparent power constraint can be added.
%
% PARAMS FIELDS
%   .rho / .u_min        NCL fraction / min service level
%   .N_ES_max            ES budget (default 32)
%   .Q_es_max_pu         max reactive injection per ES device (default 0.10)
%   .Vmin / .Vmax        voltage limits (default 0.95 / 1.05)
%   .soft_voltage        soft voltage lower bound (default true)
%   .obj_mode            'feasibility' or 'planning' (default 'feasibility')
%   .w_loss / .w_ES / .w_curt / .w_vio   objective weights
%   .candidate_buses     eligible ES buses (default all non-slack)
%   .price               T×1 TOU price vector
%   .time_limit / .MIPGap

T    = 24;
nb   = topo.nb;
nl   = topo.nl_tree;
root = topo.root;
from = topo.from(:);
R    = topo.R(:);
X    = topo.X(:);

Pd = loads.P24;
Qd = loads.Q24;

rho        = getf(params,'rho',         0.70);
u_min      = getf(params,'u_min',       0.20);
N_max      = getf(params,'N_ES_max',    32);
Q_es_max   = getf(params,'Q_es_max_pu', 0.10);
Vmin_lim   = getf(params,'Vmin',        0.95);
Vmax_lim   = getf(params,'Vmax',        1.05);
soft_v     = getf(params,'soft_voltage',true);
mode       = getf(params,'obj_mode',    'feasibility');
w_loss     = getf(params,'w_loss',      1.0);
w_ES       = getf(params,'w_ES',        0.01);
w_curt     = getf(params,'w_curt',      10.0);
w_vio      = getf(params,'w_vio',       1e4);
t_lim      = getf(params,'time_limit',  300);
mip_gap    = getf(params,'MIPGap',      0.01);
price      = getf(params,'price',       ones(T,1)); price = price(:);
cand_buses = getf(params,'candidate_buses', setdiff(1:nb,root)');
cand_buses = cand_buses(:)';

P_CL  = (1-rho)*Pd;  Q_CL  = (1-rho)*Qd;
P_NCL = rho*Pd;      Q_NCL = rho*Qd;

% -------------------------------------------------------------------------
%  VARIABLES
% -------------------------------------------------------------------------
z     = binvar(nb, 1, 'full');
c     = sdpvar(nb, T, 'full');
Q_es  = sdpvar(nb, T, 'full');
v     = sdpvar(nb, T, 'full');
Pij   = sdpvar(nl, T, 'full');
Qij   = sdpvar(nl, T, 'full');
ell   = sdpvar(nl, T, 'full');
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

% Candidates and budget
non_cand = setdiff(1:nb, cand_buses);
if ~isempty(non_cand), Con = [Con, z(non_cand) == 0]; end
Con = [Con, sum(z) <= N_max];

% ES-1: curtailment + reactive injection, both coupled to z
Con = [Con, c >= 0, Q_es >= 0];
for i = 1:nb
    Con = [Con, c(i,:)    <= (1-u_min) * z(i)];
    Con = [Con, Q_es(i,:) <= Q_es_max  * z(i)];
end

% DistFlow: ES curtails P+Q NCL; additionally injects Q_es
for t = 1:T
    for j = 1:nb
        if j == root, continue; end
        kpar = line_of_child(j); i = from(kpar);
        ch = outLines{j};
        if isempty(ch), sumP = 0; sumQ = 0;
        else,           sumP = sum(Pij(ch,t)); sumQ = sum(Qij(ch,t)); end

        Peff = P_CL(j,t) + (1-c(j,t))*P_NCL(j,t);
        Qeff = Q_CL(j,t) + (1-c(j,t))*Q_NCL(j,t) - Q_es(j,t);

        Con = [Con, ...
            Pij(kpar,t) == Peff + sumP + R(kpar)*ell(kpar,t), ...
            Qij(kpar,t) == Qeff + sumQ + X(kpar)*ell(kpar,t), ...
            v(j,t) == v(i,t) - 2*(R(kpar)*Pij(kpar,t) + X(kpar)*Qij(kpar,t)) ...
                    + (R(kpar)^2 + X(kpar)^2)*ell(kpar,t), ...
            cone([2*Pij(kpar,t); 2*Qij(kpar,t); ell(kpar,t)-v(i,t)], ...
                  ell(kpar,t)+v(i,t))];
    end
end

% -------------------------------------------------------------------------
%  OBJECTIVE
% -------------------------------------------------------------------------
lossCost = 0;
for t = 1:T, lossCost = lossCost + price(t)*sum(R.*ell(:,t)); end
curtCost = 0;
for t = 1:T, curtCost = curtCost + sum(c(:,t).*P_NCL(:,t)); end
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
ops = sdpsettings('solver','gurobi','verbose',0);
ops.gurobi.TimeLimit      = t_lim;
ops.gurobi.MIPGap         = mip_gap;
ops.gurobi.DualReductions = 0;
t_s = tic;
sol = optimize(Con, Obj, ops);
solve_time = toc(t_s);

% -------------------------------------------------------------------------
%  EXTRACT
% -------------------------------------------------------------------------
res = struct();
res.solver_ok  = (sol.problem == 0 || sol.problem == 4);
res.feasible   = (sol.problem == 0);
res.sol_code   = sol.problem;
res.sol_info   = sol.info;
res.solve_time = solve_time;
res.rho = rho; res.u_min = u_min;
res.N_ES_max = N_max; res.Q_es_max = Q_es_max;

if res.solver_ok
    z_val    = round(value(z));
    c_val    = max(0, value(c));
    Q_es_val = max(0, value(Q_es));
    v_val    = value(v);
    ell_val  = value(ell);
    V_val    = sqrt(max(v_val, 0));
    sv_val   = zeros(nb, T);
    if soft_v, sv_val = max(0, value(sv)); end

    es_sel  = find(z_val > 0.5);
    loss_t  = arrayfun(@(t) sum(R.*ell_val(:,t)), 1:T)';
    Vmin_t  = min(V_val)';
    [~, VminBus_t] = min(V_val, [], 1);
    [Vmin_24h, wh] = min(Vmin_t);

    mean_curt = 0;
    if ~isempty(es_sel), mean_curt = mean(c_val(es_sel,:), 'all'); end

    res.z_val       = z_val;
    res.es_buses    = es_sel';
    res.n_es        = numel(es_sel);
    res.c_val       = c_val;
    res.mean_curt   = mean_curt;
    res.max_curt    = max(c_val(:));
    res.Q_es_val    = Q_es_val;
    res.total_Qes   = sum(Q_es_val(:));
    res.mean_Qes    = 0;
    if ~isempty(es_sel), res.mean_Qes = mean(Q_es_val(es_sel,:), 'all'); end
    res.V_val       = V_val;
    res.sv_val      = sv_val;
    res.loss_t      = loss_t;
    res.total_loss  = sum(loss_t);
    res.Vmin_t      = Vmin_t;
    res.VminBus_t   = VminBus_t';
    res.Vmin_24h    = Vmin_24h;
    res.worst_hour  = wh;
    res.worst_bus   = VminBus_t(wh);
    res.total_sv    = sum(sv_val(:));
    res.max_sv      = max(sv_val(:));
    res.voltage_ok  = (res.total_sv <= 1e-6);
    res.feasible    = res.solver_ok && res.voltage_ok;

    fprintf('  ES-1: N_e=%d/%d | Vmin=%.4f (h%d,b%d) | Loss=%.5f | Curt=%.1f%% | Qes=%.4f | VoltOK=%d | t=%.1fs\n', ...
        numel(es_sel), N_max, Vmin_24h, wh, VminBus_t(wh), ...
        sum(loss_t), 100*mean_curt, sum(Q_es_val(:)), res.voltage_ok, solve_time);
else
    res.es_buses   = [];  res.n_es      = NaN;
    res.V_val      = NaN(nb,T);
    res.total_loss = NaN; res.Vmin_24h  = NaN;
    res.worst_hour = NaN; res.worst_bus = NaN;
    res.mean_curt  = NaN; res.max_curt  = NaN;
    res.total_Qes  = NaN; res.mean_Qes  = NaN;
    res.total_sv   = NaN; res.max_sv    = NaN;
    res.voltage_ok = false;
    fprintf('  ES-1: INFEASIBLE | Code=%d | t=%.1fs\n', sol.problem, solve_time);
end
end

function v = getf(s, f, d)
if isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
