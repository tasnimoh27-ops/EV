function res = solve_es1_pv_misocp(topo, loads, params)
%SOLVE_ES1_PV_MISOCP  ES-1 MISOCP for PV penetration study.
%
% Extends solve_es1_misocp with:
%   - Bidirectional Q_es (can absorb and inject reactive power)
%   - Voltage upper-limit slack for overvoltage diagnosis
%   - Optional curtailment disabling for PV-only studies
%
% Key changes vs solve_es1_misocp:
%   Q_es can be negative (absorption) or positive (injection)
%   Two voltage slack variables: sv_low (undervoltage), sv_high (overvoltage)
%
% INPUTS
%   topo      topology struct (build_distflow_topology_from_branch_csv)
%   loads     load struct with P24_net, Q24_net (nb×24)
%   params    parameter struct (see solve_es1_misocp for base params)
%
% Additional params for PV:
%   .disable_curtailment    (default false) — if true, set c(i,t)=0
%   .Q_es_abs_max_pu        (default 0.10) — max reactive absorption per device
%   .Q_es_inj_max_pu        (default 0.10) — max reactive injection per device
%
% OUTPUT
%   res       result struct with voltage, loss, Q_es, and feasibility info

T    = 24;
nb   = topo.nb;
nl   = topo.nl_tree;
root = topo.root;
from = topo.from(:);
R    = topo.R(:);
X    = topo.X(:);

% Use net loads (includes PV) or original?
if isfield(loads, 'P24_net')
    Pd = loads.P24_net;
    Qd = loads.Q24_net;
else
    Pd = loads.P24;
    Qd = loads.Q24;
end

rho          = getf(params, 'rho',                   0.70);
u_min        = getf(params, 'u_min',                 0.20);
N_max        = getf(params, 'N_ES_max',              32);
Q_es_abs_max = getf(params, 'Q_es_abs_max_pu',      0.10);
Q_es_inj_max = getf(params, 'Q_es_inj_max_pu',      0.10);
Vmin_lim     = getf(params, 'Vmin',                  0.95);
Vmax_lim     = getf(params, 'Vmax',                  1.05);
soft_v       = getf(params, 'soft_voltage',          true);
mode         = getf(params, 'obj_mode',              'feasibility');
w_loss       = getf(params, 'w_loss',                1.0);
w_ES         = getf(params, 'w_ES',                  0.01);
w_curt       = getf(params, 'w_curt',                10.0);
w_vio        = getf(params, 'w_vio',                 1e4);
t_lim        = getf(params, 'time_limit',            300);
mip_gap      = getf(params, 'MIPGap',                0.01);
price        = getf(params, 'price',                 ones(T,1)); price = price(:);
cand_buses   = getf(params, 'candidate_buses',       setdiff(1:nb, root)');
disable_curt = getf(params, 'disable_curtailment',   false);

cand_buses = cand_buses(:)';

P_CL  = (1-rho)*Pd;  Q_CL  = (1-rho)*Qd;
P_NCL = rho*Pd;      Q_NCL = rho*Qd;

% -------------------------------------------------------------------------
%  VARIABLES
% -------------------------------------------------------------------------
z     = binvar(nb, 1, 'full');
c     = sdpvar(nb, T, 'full');
Q_es  = sdpvar(nb, T, 'full');     % can be negative (absorb) or positive (inject)
v     = sdpvar(nb, T, 'full');
Pij   = sdpvar(nl, T, 'full');
Qij   = sdpvar(nl, T, 'full');
ell   = sdpvar(nl, T, 'full');

sv_low  = sdpvar(nb, T, 'full');   % slack for undervoltage
sv_high = sdpvar(nb, T, 'full');   % slack for overvoltage

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

% Voltage bounds with slack
Con = [Con, sv_low >= 0, sv_high >= 0];
Con = [Con, v + sv_low  >= Vmin_lim^2];      % v >= Vmin^2 - sv_low
Con = [Con, v - sv_high <= Vmax_lim^2];      % v <= Vmax^2 + sv_high
Con = [Con, v <= Vmax_lim^2 + sv_high];      % redundant but explicit
Con = [Con, ell >= 0, v(root,:) == 1.0];

% Candidates and budget
non_cand = setdiff(1:nb, cand_buses);
if ~isempty(non_cand), Con = [Con, z(non_cand) == 0]; end
Con = [Con, sum(z) <= N_max];

% ES: curtailment + bidirectional reactive
if disable_curt
    % No curtailment: c = 0
    Con = [Con, c == 0];
    P_NCL_eff = P_NCL;  % all NCL remains
else
    % Standard curtailment
    Con = [Con, c >= 0];
    for i = 1:nb
        Con = [Con, c(i,:) <= (1-u_min) * z(i)];
    end
    P_NCL_eff = P_NCL;  % curtailment reduces P_NCL in DistFlow
end

% Bidirectional Q_es: -Q_es_abs_max*z <= Q_es <= Q_es_inj_max*z
for i = 1:nb
    Con = [Con, Q_es(i,:) >= -Q_es_abs_max * z(i)];
    Con = [Con, Q_es(i,:) <=  Q_es_inj_max * z(i)];
end

% DistFlow: ES curtails P+Q NCL; independently adjusts Q_es
for t = 1:T
    for j = 1:nb
        if j == root, continue; end
        kpar = line_of_child(j);
        i = from(kpar);
        ch = outLines{j};
        if isempty(ch), sumP = 0; sumQ = 0;
        else,           sumP = sum(Pij(ch,t)); sumQ = sum(Qij(ch,t)); end

        Peff = P_CL(j,t) + (1-c(j,t))*P_NCL_eff(j,t);
        % Q_es > 0: ES injects (helps undervoltage)
        % Q_es < 0: ES absorbs (helps overvoltage)
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
%  OBJECTIVE: minimize both under- and over-voltage slack + loss
% -------------------------------------------------------------------------
lossCost = 0;
for t = 1:T, lossCost = lossCost + price(t)*sum(R.*ell(:,t)); end

curtCost = 0;
if ~disable_curt
    for t = 1:T, curtCost = curtCost + sum(c(:,t).*P_NCL_eff(:,t)); end
end

svCost = sum(sum(sv_low)) + sum(sum(sv_high));

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
res.rho        = rho;
res.u_min      = u_min;
res.N_ES_max   = N_max;
res.Q_es_abs_max = Q_es_abs_max;
res.Q_es_inj_max = Q_es_inj_max;
res.disable_curtailment = disable_curt;

if res.solver_ok
    z_val    = round(value(z));
    c_val    = max(0, value(c));
    Q_es_val = value(Q_es);      % can be negative
    v_val    = value(v);
    ell_val  = value(ell);
    V_val    = sqrt(max(v_val, 0));
    sv_low_val  = max(0, value(sv_low));
    sv_high_val = max(0, value(sv_high));

    es_sel = find(z_val > 0.5);

    % Voltage metrics
    loss_t  = arrayfun(@(t) sum(R.*ell_val(:,t)), 1:T)';
    Vmin_t  = min(V_val)';
    Vmax_t  = max(V_val)';
    [Vmin_24h, wh_min] = min(Vmin_t);
    [Vmax_24h, wh_max] = max(Vmax_t);
    [~, wb_min] = min(V_val(:, wh_min));
    [~, wb_max] = max(V_val(:, wh_max));

    % Reactive metrics
    Q_es_inj = Q_es_val;
    Q_es_inj(Q_es_inj < 0) = 0;  % injection only
    Q_es_abs = -Q_es_val;
    Q_es_abs(Q_es_abs < 0) = 0;  % absorption only

    mean_curt = 0;
    if ~isempty(es_sel), mean_curt = mean(c_val(es_sel,:), 'all'); end

    % Reverse power flow (positive from upstream to downstream)
    % Reverse = Pij < -1e-5
    Pij_val = value(Pij);
    reverse_mask = (Pij_val < -1e-5);
    reverse_count = sum(reverse_mask(:));
    max_reverse = 0;
    if reverse_count > 0
        max_reverse = -min(Pij_val(:));
    end

    res.z_val       = z_val;
    res.es_buses    = es_sel';
    res.n_es        = numel(es_sel);
    res.c_val       = c_val;
    res.mean_curt   = mean_curt;
    res.max_curt    = max(c_val(:));
    res.Q_es_val    = Q_es_val;
    res.total_Q_es_inj   = sum(Q_es_inj(:));
    res.total_Q_es_abs   = sum(Q_es_abs(:));
    res.total_Q_es_abs_val = sum(abs(Q_es_val(Q_es_val < 0)));
    res.total_Qes   = res.total_Q_es_inj - res.total_Q_es_abs_val;  % net
    res.mean_Qes    = 0;
    if ~isempty(es_sel)
        res.mean_Qes = mean(abs(Q_es_val(es_sel,:)), 'all');
    end

    res.V_val       = V_val;
    res.sv_low_val  = sv_low_val;
    res.sv_high_val = sv_high_val;
    res.loss_t      = loss_t;
    res.total_loss  = sum(loss_t);
    res.Vmin_t      = Vmin_t;
    res.Vmax_t      = Vmax_t;
    res.Vmin_24h    = Vmin_24h;
    res.Vmax_24h    = Vmax_24h;
    res.worst_hour_low  = wh_min;
    res.worst_bus_low   = wb_min;
    res.worst_hour_high = wh_max;
    res.worst_bus_high  = wb_max;
    res.reverse_flow_count = reverse_count;
    res.max_reverse_power  = max_reverse;

    res.total_sv_low   = sum(sv_low_val(:));
    res.total_sv_high  = sum(sv_high_val(:));
    res.total_sv       = res.total_sv_low + res.total_sv_high;
    res.max_sv         = max([sv_low_val(:); sv_high_val(:)]);

    % Voltage feasibility: both Vmin and Vmax in limits
    volt_feasible_low  = (res.total_sv_low <= 1e-6);
    volt_feasible_high = (res.total_sv_high <= 1e-6);
    res.voltage_ok  = volt_feasible_low && volt_feasible_high;
    res.feasible    = res.solver_ok && res.voltage_ok;

    fprintf('  ES1-PV: N_e=%d/%d | Vmin=%.4f (h%d,b%d) | Vmax=%.4f (h%d,b%d) | Loss=%.5f | Qes_inj=%.4f | Qes_abs=%.4f | ReverseFlow=%d | VoltOK=%d | t=%.1fs\n', ...
        numel(es_sel), N_max, Vmin_24h, wh_min, wb_min, Vmax_24h, wh_max, wb_max, ...
        sum(loss_t), res.total_Q_es_inj, res.total_Q_es_abs_val, reverse_count, res.voltage_ok, solve_time);
else
    res.es_buses   = [];  res.n_es      = NaN;
    res.V_val      = NaN(nb,T);
    res.total_loss = NaN; res.Vmin_24h  = NaN; res.Vmax_24h = NaN;
    res.worst_hour_low = NaN; res.worst_bus_low = NaN;
    res.worst_hour_high = NaN; res.worst_bus_high = NaN;
    res.mean_curt  = NaN; res.max_curt  = NaN;
    res.total_Qes  = NaN; res.mean_Qes  = NaN;
    res.total_Q_es_inj = NaN; res.total_Q_es_abs = NaN;
    res.total_sv   = NaN; res.max_sv    = NaN;
    res.voltage_ok = false;
    res.reverse_flow_count = NaN;
    res.max_reverse_power = NaN;
    fprintf('  ES1-PV: INFEASIBLE | Code=%d | t=%.1fs\n', sol.problem, solve_time);
end

end

% -------------------------------------------------------------------------
%  HELPER
% -------------------------------------------------------------------------
function v = getf(s, f, d)
if isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
