function res = solve_es1_statcom_misocp(topo, loads, params)
%SOLVE_ES1_STATCOM_MISOCP  Joint ES-1 (Hou) + STATCOM MISOCP.
%
% Extends solve_es_statcom_misocp: ES devices have independent reactive
% injection Q_es (ES-1 model) in addition to active curtailment.
% STATCOM provides supplementary reactive support.
%
% DistFlow effective demand:
%   Peff = P_CL + (1-c)*P_NCL
%   Qeff = Q_CL + (1-c)*Q_NCL - Q_es - Q_s
%
% VARIABLES
%   z_e(i)    in {0,1}                    ES-1 installed at bus i
%   c(i,t)    in [0, (1-u_min)*z_e(i)]   NCL curtailment fraction
%   Q_es(i,t) in [0, Q_es_max*z_e(i)]    ES-1 reactive injection (pu)
%   z_s(i)    in {0,1}                    STATCOM installed at bus i
%   Q_s(i,t)  in [0, Qs_max*z_s(i)]      STATCOM reactive injection (pu)
%   v,Pij,Qij,ell,sv                      DistFlow variables
%
% PARAMS FIELDS
%   .rho / .u_min          NCL fraction / min service level
%   .N_e_max / .N_s_max    ES-1 / STATCOM budgets
%   .Q_es_max_pu           ES-1 reactive capacity per device (default 0.10)
%   .Qs_max_pu             STATCOM reactive capacity per device (default 0.10)
%   .candidate_buses_es / .candidate_buses_s
%   .Vmin/.Vmax / .soft_voltage / .obj_mode / .price / .time_limit / .MIPGap

T    = 24;
nb   = topo.nb;
nl   = topo.nl_tree;
root = topo.root;
from = topo.from(:);
R    = topo.R(:);
X    = topo.X(:);

Pd = loads.P24;
Qd = loads.Q24;

rho        = getf(params,'rho',          0.70);
u_min      = getf(params,'u_min',        0.20);
N_e_max    = getf(params,'N_e_max',      32);
N_s_max    = getf(params,'N_s_max',      32);
Q_es_max   = getf(params,'Q_es_max_pu',  0.10);
Qs_max_pu  = getf(params,'Qs_max_pu',    0.10);
Vmin_lim   = getf(params,'Vmin',         0.95);
Vmax_lim   = getf(params,'Vmax',         1.05);
soft_v     = getf(params,'soft_voltage', true);
mode       = getf(params,'obj_mode',     'feasibility');
w_loss     = getf(params,'w_loss',       1.0);
w_e        = getf(params,'w_e',          0.01);
w_s        = getf(params,'w_s',          0.01);
w_curt     = getf(params,'w_curt',       10.0);
w_vio      = getf(params,'w_vio',        1e4);
t_lim      = getf(params,'time_limit',   300);
mip_gap    = getf(params,'MIPGap',       0.01);
price      = getf(params,'price',        ones(T,1)); price = price(:);
cand_e     = getf(params,'candidate_buses_es', setdiff(1:nb,root)');
cand_s     = getf(params,'candidate_buses_s',  setdiff(1:nb,root)');

P_CL  = (1-rho)*Pd;  Q_CL  = (1-rho)*Qd;
P_NCL = rho*Pd;      Q_NCL = rho*Qd;

% -------------------------------------------------------------------------
%  VARIABLES
% -------------------------------------------------------------------------
z_e   = binvar(nb, 1, 'full');
c     = sdpvar(nb, T, 'full');
Q_es  = sdpvar(nb, T, 'full');
z_s   = binvar(nb, 1, 'full');
Q_s   = sdpvar(nb, T, 'full');
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

% ES-1 candidates, budget, curtailment + reactive coupling
non_cand_e = setdiff(1:nb, cand_e(:)');
if ~isempty(non_cand_e), Con = [Con, z_e(non_cand_e) == 0]; end
Con = [Con, sum(z_e) <= N_e_max, c >= 0, Q_es >= 0];
for i = 1:nb
    Con = [Con, c(i,:)    <= (1-u_min) * z_e(i)];
    Con = [Con, Q_es(i,:) <= Q_es_max  * z_e(i)];
end

% STATCOM candidates, budget, reactive bounds
non_cand_s = setdiff(1:nb, cand_s(:)');
if ~isempty(non_cand_s), Con = [Con, z_s(non_cand_s) == 0]; end
Con = [Con, sum(z_s) <= N_s_max, Q_s >= 0];
for i = 1:nb
    Con = [Con, Q_s(i,:) <= Qs_max_pu * z_s(i)];
end

% DistFlow: ES-1 curtails P+Q NCL and injects Q_es; STATCOM injects Q_s
for t = 1:T
    for j = 1:nb
        if j == root, continue; end
        kpar = line_of_child(j); i = from(kpar);
        ch = outLines{j};
        if isempty(ch), sumP = 0; sumQ = 0;
        else,           sumP = sum(Pij(ch,t)); sumQ = sum(Qij(ch,t)); end

        Peff = P_CL(j,t) + (1-c(j,t))*P_NCL(j,t);
        Qeff = Q_CL(j,t) + (1-c(j,t))*Q_NCL(j,t) - Q_es(j,t) - Q_s(j,t);

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
    Obj = w_loss*lossCost + w_e*sum(z_e) + w_s*sum(z_s) + w_curt*curtCost + w_vio*svCost;
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
res.N_e_max = N_e_max; res.N_s_max = N_s_max;

if res.solver_ok
    z_e_val   = round(value(z_e));
    z_s_val   = round(value(z_s));
    c_val     = max(0, value(c));
    Q_es_val  = max(0, value(Q_es));
    Q_s_val   = max(0, value(Q_s));
    v_val     = value(v);
    ell_val   = value(ell);
    V_val     = sqrt(max(v_val, 0));
    sv_val    = zeros(nb, T);
    if soft_v, sv_val = max(0, value(sv)); end

    e_sel  = find(z_e_val > 0.5);
    s_sel  = find(z_s_val > 0.5);
    loss_t = arrayfun(@(t) sum(R.*ell_val(:,t)), 1:T)';
    Vmin_t = min(V_val)';
    [~, VminBus_t] = min(V_val, [], 1);
    [Vmin_24h, wh] = min(Vmin_t);

    mean_curt = 0;
    if ~isempty(e_sel), mean_curt = mean(c_val(e_sel,:), 'all'); end

    res.z_e_val       = z_e_val;
    res.es_buses      = e_sel';
    res.n_es          = numel(e_sel);
    res.c_val         = c_val;
    res.mean_curt     = mean_curt;
    res.max_curt      = max(c_val(:));
    res.Q_es_val      = Q_es_val;
    res.total_Qes     = sum(Q_es_val(:));
    res.z_s_val       = z_s_val;
    res.statcom_buses = s_sel';
    res.n_statcom     = numel(s_sel);
    res.Q_s_val       = Q_s_val;
    res.total_Qs      = sum(Q_s_val(:));
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

    fprintf('  ES1+STATCOM: N_e=%d N_s=%d | Vmin=%.4f (h%d,b%d) | Loss=%.5f | Curt=%.1f%% | Qes=%.4f Qs=%.4f | VoltOK=%d | t=%.1fs\n', ...
        numel(e_sel), numel(s_sel), Vmin_24h, wh, VminBus_t(wh), ...
        sum(loss_t), 100*mean_curt, sum(Q_es_val(:)), sum(Q_s_val(:)), res.voltage_ok, solve_time);
else
    res.es_buses      = [];  res.n_es      = NaN;
    res.statcom_buses = [];  res.n_statcom = NaN;
    res.V_val         = NaN(nb,T);
    res.total_loss    = NaN; res.Vmin_24h  = NaN;
    res.worst_hour    = NaN; res.worst_bus = NaN;
    res.mean_curt     = NaN; res.max_curt  = NaN;
    res.total_Qes     = NaN; res.total_Qs  = NaN;
    res.total_sv      = NaN; res.max_sv    = NaN;
    res.voltage_ok    = false;
    fprintf('  ES1+STATCOM: INFEASIBLE | Code=%d | t=%.1fs\n', sol.problem, solve_time);
end
end

function v = getf(s, f, d)
if isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
