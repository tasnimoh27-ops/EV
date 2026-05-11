function res = solve_statcom_misocp(topo, loads, params)
%SOLVE_STATCOM_MISOCP  Binary STATCOM placement MISOCP.
%
% Finds minimum-count STATCOM placement that restores voltage feasibility
% via reactive injection only (no active power control).
%
% VARIABLES
%   z_s(i)    in {0,1}                  — STATCOM installed at bus i
%   Q_s(i,t)  in [0, Qs_max_pu*z_s(i)] — reactive injection (pu), injection-only
%   v(i,t)    >= 0                      — squared voltage (pu^2)
%   Pij,Qij,ell                         — DistFlow branch variables
%   sv(i,t)   >= 0                      — voltage slack (soft mode only)
%
% DistFlow Qij balance with STATCOM:
%   Qij(kpar,t) = Qd(j,t) - Q_s(j,t) + sumQ_downstream + X*ell
%
% PARAMS FIELDS
%   .N_s_max        max STATCOM budget (default 32)
%   .Qs_max_pu      per-device reactive capacity in pu (default 0.10)
%   .Vmin / .Vmax   voltage limits (default 0.95 / 1.05)
%   .soft_voltage   soft voltage lower bound (default true)
%   .obj_mode       'feasibility' or 'planning' (default 'feasibility')
%   .w_loss         loss weight — planning mode (default 1.0)
%   .w_s            STATCOM count penalty — planning mode (default 0.01)
%   .w_vio          voltage slack penalty (default 1e4)
%   .candidate_buses eligible buses (default all non-slack)
%   .price          T×1 TOU price vector
%   .time_limit     solver time limit in seconds (default 300)
%   .MIPGap         Gurobi MIP gap (default 0.01)

T    = 24;
nb   = topo.nb;
nl   = topo.nl_tree;
root = topo.root;
from = topo.from(:);
R    = topo.R(:);
X    = topo.X(:);

Pd = loads.P24;
Qd = loads.Q24;

N_s_max      = getf(params, 'N_s_max',       32);
Qs_max_pu    = getf(params, 'Qs_max_pu',     0.10);
Vmin_lim     = getf(params, 'Vmin',          0.95);
Vmax_lim     = getf(params, 'Vmax',          1.05);
soft_v       = getf(params, 'soft_voltage',  true);
mode         = getf(params, 'obj_mode',      'feasibility');
w_loss       = getf(params, 'w_loss',        1.0);
w_s          = getf(params, 'w_s',           0.01);
w_vio        = getf(params, 'w_vio',         1e4);
t_lim        = getf(params, 'time_limit',    300);
mip_gap      = getf(params, 'MIPGap',        0.01);
price        = getf(params, 'price',         ones(T,1)); price = price(:);
cand_buses   = getf(params, 'candidate_buses', setdiff(1:nb, root)');

% -------------------------------------------------------------------------
%  VARIABLES
% -------------------------------------------------------------------------
z_s  = binvar(nb, 1, 'full');
Q_s  = sdpvar(nb, T, 'full');
v    = sdpvar(nb, T, 'full');
Pij  = sdpvar(nl, T, 'full');
Qij  = sdpvar(nl, T, 'full');
ell  = sdpvar(nl, T, 'full');
if soft_v, sv = sdpvar(nb, T, 'full'); end

% -------------------------------------------------------------------------
%  ADJACENCY
% -------------------------------------------------------------------------
outLines      = cell(nb, 1);
line_of_child = zeros(nb, 1);
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

% z_s only at candidates
non_cand = setdiff(1:nb, cand_buses(:)');
if ~isempty(non_cand), Con = [Con, z_s(non_cand) == 0]; end
Con = [Con, sum(z_s) <= N_s_max];

% Reactive injection: injection-only, bounded by installed capacity
% Q_s(i,t) in [0, Qs_max_pu] if z_s(i)=1, else Q_s(i,t)=0
Con = [Con, Q_s >= 0];
for i = 1:nb
    Con = [Con, Q_s(i,:) <= Qs_max_pu * z_s(i)];
end

% DistFlow: full load (no ES), STATCOM reduces effective reactive demand
for t = 1:T
    for j = 1:nb
        if j == root, continue; end
        kpar = line_of_child(j); i = from(kpar);
        ch = outLines{j};
        if isempty(ch), sumP = 0; sumQ = 0;
        else,           sumP = sum(Pij(ch,t)); sumQ = sum(Qij(ch,t)); end

        Peff = Pd(j,t);
        Qeff = Qd(j,t) - Q_s(j,t);

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
svCost = 0;
if soft_v, svCost = sum(sum(sv)); end

if strcmp(mode, 'feasibility')
    Obj = svCost + 1e-4*lossCost;
else
    Obj = w_loss*lossCost + w_s*sum(z_s) + w_vio*svCost;
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
res.N_s_max    = N_s_max;
res.Qs_max_pu  = Qs_max_pu;

if res.solver_ok
    z_s_val = round(value(z_s));
    Q_s_val = max(0, value(Q_s));
    v_val   = value(v);
    ell_val = value(ell);
    V_val   = sqrt(max(v_val, 0));
    sv_val  = zeros(nb, T);
    if soft_v, sv_val = max(0, value(sv)); end

    s_sel  = find(z_s_val > 0.5);
    loss_t = arrayfun(@(t) sum(R.*ell_val(:,t)), 1:T)';
    Vmin_t = min(V_val)';
    [~, VminBus_t] = min(V_val, [], 1);
    [Vmin_24h, wh] = min(Vmin_t);

    res.z_s_val       = z_s_val;
    res.statcom_buses = s_sel';
    res.n_statcom     = numel(s_sel);
    res.Q_s_val       = Q_s_val;
    res.total_Qs      = sum(Q_s_val(:));
    res.mean_Qs       = mean(Q_s_val(s_sel, :), 'all');
    if isempty(s_sel), res.mean_Qs = 0; end
    res.V_val         = V_val;
    res.sv_val        = sv_val;
    res.loss_t        = loss_t;
    res.total_loss    = sum(loss_t);
    res.Vmin_t        = Vmin_t;
    res.VminBus_t     = VminBus_t';
    res.Vmin_24h      = Vmin_24h;
    res.worst_hour    = wh;
    res.worst_bus     = VminBus_t(wh);
    res.total_sv      = sum(sv_val(:));
    res.max_sv        = max(sv_val(:));
    res.voltage_ok    = (res.total_sv <= 1e-6);
    res.feasible      = res.solver_ok && res.voltage_ok;

    fprintf('  STATCOM: N_s=%d/%d | Qs_max=%.3f | Vmin=%.4f (h%d,b%d) | Loss=%.5f | Qs=%.4f | VoltOK=%d | t=%.1fs\n', ...
        numel(s_sel), N_s_max, Qs_max_pu, Vmin_24h, wh, VminBus_t(wh), ...
        sum(loss_t), sum(Q_s_val(:)), res.voltage_ok, solve_time);
else
    res.statcom_buses = [];
    res.n_statcom     = NaN;
    res.V_val         = NaN(nb, T);
    res.total_loss    = NaN;
    res.Vmin_24h      = NaN;
    res.worst_hour    = NaN;
    res.worst_bus     = NaN;
    res.total_Qs      = NaN;
    res.total_sv      = NaN;
    res.max_sv        = NaN;
    res.voltage_ok    = false;
    fprintf('  STATCOM: INFEASIBLE | Code=%d | t=%.1fs\n', sol.problem, solve_time);
end
end

function v = getf(s, f, d)
if isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
