function res = solve_ess_misocp(topo, loads, params)
%SOLVE_ESS_MISOCP  Binary ESS placement MISOCP with SOC dynamics.
%
% Models grid-tied battery storage with active power time-shifting and
% inverter-based reactive injection. Key advantage over STATCOM: ESS
% provides both P and Q support while respecting energy balance.
%
% VARIABLES
%   z_b(i)     in {0,1}                      — ESS installed at bus i
%   P_ch(i,t)  in [0, P_ch_max*z_b(i)]       — charging power (pu)
%   P_dis(i,t) in [0, P_dis_max*z_b(i)]      — discharging power (pu)
%   E(i,t)     in [SOC_min*E_cap*z_b(i),
%                  E_cap*z_b(i)]              — state of charge (pu·h)
%   Q_b(i,t)   in [0, Q_b_max*z_b(i)]        — reactive injection (pu)
%   v,Pij,Qij,ell,sv                          — DistFlow variables
%
% SOC dynamics (Δt=1h):
%   E(i,1) = SOC_init*E_cap*z_b(i) + η_ch*P_ch(i,1) - P_dis(i,1)/η_dis
%   E(i,t) = E(i,t-1) + η_ch*P_ch(i,t) - P_dis(i,t)/η_dis,  t=2..T
%   E(i,T) = SOC_init*E_cap*z_b(i)    [daily cyclic constraint]
%
% DistFlow effective demand:
%   Peff(j,t) = P_load(j,t) + P_ch(j,t) - P_dis(j,t)
%   Qeff(j,t) = Q_load(j,t) - Q_b(j,t)
%
% PARAMS FIELDS
%   .N_b_max       max ESS budget (default 32)
%   .E_cap_pu      energy capacity per unit in pu·h (default 1.0)
%   .P_ch_max_pu   max charging power per unit (default 0.5)
%   .P_dis_max_pu  max discharging power per unit (default 0.5)
%   .Q_b_max_pu    max reactive injection per unit (default 0.10)
%   .eta_ch        charging efficiency (default 0.95)
%   .eta_dis       discharging efficiency (default 0.95)
%   .SOC_init      initial/final SOC fraction (default 0.50)
%   .SOC_min       minimum SOC fraction (default 0.10)
%   .Vmin/.Vmax    voltage limits (default 0.95/1.05)
%   .soft_voltage  soft voltage lower bound (default true)
%   .obj_mode      'feasibility' or 'planning' (default 'feasibility')
%   .w_loss / .w_b / .w_vio   objective weights
%   .candidate_buses  eligible buses (default all non-slack)
%   .price         T×1 TOU price vector
%   .time_limit    solver time limit s (default 300)
%   .MIPGap        Gurobi MIP gap (default 0.01)

T    = 24;
nb   = topo.nb;
nl   = topo.nl_tree;
root = topo.root;
from = topo.from(:);
R    = topo.R(:);
X    = topo.X(:);

Pd = loads.P24;
Qd = loads.Q24;

N_b_max    = getf(params,'N_b_max',      32);
E_cap      = getf(params,'E_cap_pu',     1.0);
P_ch_max   = getf(params,'P_ch_max_pu',  0.5);
P_dis_max  = getf(params,'P_dis_max_pu', 0.5);
Q_b_max    = getf(params,'Q_b_max_pu',   0.10);
eta_ch     = getf(params,'eta_ch',       0.95);
eta_dis    = getf(params,'eta_dis',      0.95);
SOC_init   = getf(params,'SOC_init',     0.50);
SOC_min    = getf(params,'SOC_min',      0.10);
Vmin_lim   = getf(params,'Vmin',         0.95);
Vmax_lim   = getf(params,'Vmax',         1.05);
soft_v     = getf(params,'soft_voltage', true);
mode       = getf(params,'obj_mode',     'feasibility');
w_loss     = getf(params,'w_loss',       1.0);
w_b        = getf(params,'w_b',          0.01);
w_vio      = getf(params,'w_vio',        1e4);
t_lim      = getf(params,'time_limit',   300);
mip_gap    = getf(params,'MIPGap',       0.01);
price      = getf(params,'price',        ones(T,1)); price = price(:);
cand_buses = getf(params,'candidate_buses', setdiff(1:nb,root)');

E0 = SOC_init * E_cap;   % initial/final stored energy (scalar per unit)

% -------------------------------------------------------------------------
%  VARIABLES
% -------------------------------------------------------------------------
z_b   = binvar(nb, 1, 'full');
P_ch  = sdpvar(nb, T, 'full');
P_dis = sdpvar(nb, T, 'full');
E     = sdpvar(nb, T, 'full');
Q_b   = sdpvar(nb, T, 'full');
v     = sdpvar(nb, T, 'full');
Pij   = sdpvar(nl, T, 'full');
Qij   = sdpvar(nl, T, 'full');
ell   = sdpvar(nl, T, 'full');
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

% Candidates and budget
non_cand = setdiff(1:nb, cand_buses(:)');
if ~isempty(non_cand), Con = [Con, z_b(non_cand) == 0]; end
Con = [Con, sum(z_b) <= N_b_max];

% Power / reactive / energy bounds (big-M coupling with z_b)
Con = [Con, P_ch >= 0, P_dis >= 0, Q_b >= 0, E >= 0];
for i = 1:nb
    Con = [Con, ...
        P_ch(i,:)  <= P_ch_max          * z_b(i), ...
        P_dis(i,:) <= P_dis_max         * z_b(i), ...
        Q_b(i,:)   <= Q_b_max           * z_b(i), ...
        E(i,:)     <= E_cap             * z_b(i), ...
        E(i,:)     >= SOC_min * E_cap   * z_b(i)];
end

% SOC dynamics + daily cyclic constraint
for i = 1:nb
    Con = [Con, E(i,1) == E0*z_b(i) + eta_ch*P_ch(i,1) - (1/eta_dis)*P_dis(i,1)];
    for t = 2:T
        Con = [Con, E(i,t) == E(i,t-1) + eta_ch*P_ch(i,t) - (1/eta_dis)*P_dis(i,t)];
    end
    Con = [Con, E(i,T) == E0 * z_b(i)];   % end SOC = initial SOC
end

% DistFlow: ESS shifts active load and injects reactive power
for t = 1:T
    for j = 1:nb
        if j == root, continue; end
        kpar = line_of_child(j); i = from(kpar);
        ch = outLines{j};
        if isempty(ch), sumP = 0; sumQ = 0;
        else,           sumP = sum(Pij(ch,t)); sumQ = sum(Qij(ch,t)); end

        Peff = Pd(j,t) + P_ch(j,t) - P_dis(j,t);
        Qeff = Qd(j,t) - Q_b(j,t);

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
    Obj = w_loss*lossCost + w_b*sum(z_b) + w_vio*svCost;
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
res.N_b_max    = N_b_max;
res.E_cap      = E_cap;
res.Q_b_max    = Q_b_max;

if res.solver_ok
    z_b_val   = round(value(z_b));
    P_ch_val  = max(0, value(P_ch));
    P_dis_val = max(0, value(P_dis));
    E_val     = value(E);
    Q_b_val   = max(0, value(Q_b));
    v_val     = value(v);
    ell_val   = value(ell);
    V_val     = sqrt(max(v_val, 0));
    sv_val    = zeros(nb, T);
    if soft_v, sv_val = max(0, value(sv)); end

    b_sel  = find(z_b_val > 0.5);
    loss_t = arrayfun(@(t) sum(R.*ell_val(:,t)), 1:T)';
    Vmin_t = min(V_val)';
    [~, VminBus_t] = min(V_val, [], 1);
    [Vmin_24h, wh] = min(Vmin_t);

    res.z_b_val     = z_b_val;
    res.ess_buses   = b_sel';
    res.n_ess       = numel(b_sel);
    res.P_ch_val    = P_ch_val;
    res.P_dis_val   = P_dis_val;
    res.E_val       = E_val;
    res.Q_b_val     = Q_b_val;
    res.net_dis     = sum(P_dis_val(:)) - sum(P_ch_val(:));
    res.total_Qb    = sum(Q_b_val(:));
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

    fprintf('  ESS: N_b=%d/%d | Vmin=%.4f (h%d,b%d) | Loss=%.5f | Qb=%.4f | VoltOK=%d | t=%.1fs\n', ...
        numel(b_sel), N_b_max, Vmin_24h, wh, VminBus_t(wh), ...
        sum(loss_t), sum(Q_b_val(:)), res.voltage_ok, solve_time);
else
    res.ess_buses  = [];
    res.n_ess      = NaN;
    res.V_val      = NaN(nb, T);
    res.total_loss = NaN;
    res.Vmin_24h   = NaN;
    res.worst_hour = NaN;
    res.worst_bus  = NaN;
    res.net_dis    = NaN;
    res.total_Qb   = NaN;
    res.total_sv   = NaN;
    res.max_sv     = NaN;
    res.voltage_ok = false;
    fprintf('  ESS: INFEASIBLE | Code=%d | t=%.1fs\n', sol.problem, solve_time);
end
end

function v = getf(s, f, d)
if isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
