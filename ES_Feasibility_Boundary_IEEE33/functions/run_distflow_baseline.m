function res = run_distflow_baseline(topo, loads)
%RUN_DISTFLOW_BASELINE  Run no-support DistFlow baseline (no ES, no Qg).
%
% Uses existing run_distflow_bfs function iteratively for all 24 hours.
% Records voltage violations, losses, worst buses.
%
% INPUTS
%   topo   topology struct
%   loads  loads struct (P24, Q24  nb×24)
%
% OUTPUT
%   res  struct with 24h summary

nb   = topo.nb;
T    = 24;
Vmin = 0.95;
Vmax = 1.05;

V_all      = NaN(nb, T);
loss_t     = NaN(T, 1);
Vmin_t     = NaN(T, 1);
VminBus_t  = NaN(T, 1);
n_viol_t   = NaN(T, 1);

for t = 1:T
    Pd = loads.P24(:, t);
    Qd = loads.Q24(:, t);

    % Flat start: V = 1 pu
    V_init = ones(nb, 1);

    % Call existing DistFlow BFS solver
    try
        [V_t, Pij_t, Qij_t, ell_t] = run_distflow_bfs(topo, Pd, Qd, V_init);
    catch ME
        fprintf('  DistFlow failed at t=%d: %s\n', t, ME.message);
        continue
    end

    V_all(:, t)   = V_t;
    loss_t(t)     = sum(topo.R .* ell_t);
    [Vmin_t(t), VminBus_t(t)] = min(V_t);
    n_viol_t(t)   = sum(V_t < Vmin | V_t > Vmax) - 1;  % exclude slack
end

% Aggregate stats
[Vmin_24h, worst_t]    = min(Vmin_t);
worst_bus              = VminBus_t(worst_t);
total_loss             = nansum(loss_t);

% Violating buses at worst hour
V_peak = V_all(:, worst_t);
viol_buses = find(V_peak < Vmin);
viol_buses = viol_buses(viol_buses ~= topo.root);

res.V_all        = V_all;
res.loss_t       = loss_t;
res.Vmin_t       = Vmin_t;
res.VminBus_t    = VminBus_t;
res.n_viol_t     = n_viol_t;
res.Vmin_24h     = Vmin_24h;
res.worst_hour   = worst_t;
res.worst_bus    = worst_bus;
res.total_loss   = total_loss;
res.viol_buses_peak = viol_buses;
res.n_viol_peak  = numel(viol_buses);

fprintf('  Baseline: Vmin=%.4f (h%d,bus%d) | TotalLoss=%.5f | Violations(peak)=%d\n', ...
    Vmin_24h, worst_t, worst_bus, total_loss, numel(viol_buses));
end
