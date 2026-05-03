function vsi = compute_voltage_sensitivity_index(topo, loads, perturb_frac, out_dir)
%COMPUTE_VOLTAGE_SENSITIVITY_INDEX  Perturbation-based VSI for ES planning.
%
% VSI_i = Delta_Vmin / Delta_P_curtail_i
%
% Procedure: for each load bus i, reduce active load by perturb_frac,
% rerun DistFlow at peak hour, measure the improvement in Vmin.
% Higher VSI => curtailing load at bus i improves system voltage more.
%
% INPUTS
%   topo          topology struct
%   loads         loads struct (P24, Q24)
%   perturb_frac  fractional load reduction per bus (default 0.05)
%   out_dir       output directory (optional)
%
% OUTPUT
%   vsi  struct with per-bus sensitivity data

if nargin < 3 || isempty(perturb_frac), perturb_frac = 0.05; end

nb   = topo.nb;
root = topo.root;

% Find peak hour from baseline
V_init = ones(nb,1);
Vmin_t = zeros(24,1);
for t = 1:24
    try
        [V_t,~,~,~] = run_distflow_bfs(topo, loads.P24(:,t), loads.Q24(:,t), V_init);
        Vmin_t(t) = min(V_t);
    catch
        Vmin_t(t) = NaN;
    end
end
[Vmin_base, peak_t] = min(Vmin_t);

Pd_peak = loads.P24(:, peak_t);
Qd_peak = loads.Q24(:, peak_t);

% Baseline Vmin at peak hour
[V_base, ~, ~, ~] = run_distflow_bfs(topo, Pd_peak, Qd_peak, V_init);
Vmin_base_peak = min(V_base);

% Per-bus sensitivity
delta_Vmin   = zeros(nb, 1);
delta_P_pu   = zeros(nb, 1);
VSI_raw      = zeros(nb, 1);

for i = 1:nb
    if i == root
        delta_Vmin(i) = 0;
        delta_P_pu(i) = 0;
        VSI_raw(i)    = 0;
        continue
    end

    Pd_pert = Pd_peak;
    Qd_pert = Qd_peak;
    dP = perturb_frac * Pd_peak(i);
    dQ = perturb_frac * Qd_peak(i);
    Pd_pert(i) = Pd_pert(i) - dP;
    Qd_pert(i) = Qd_pert(i) - dQ;

    try
        [V_pert,~,~,~] = run_distflow_bfs(topo, Pd_pert, Qd_pert, V_init);
        Vmin_pert = min(V_pert);
    catch
        Vmin_pert = Vmin_base_peak;
    end

    delta_Vmin(i) = Vmin_pert - Vmin_base_peak;   % positive = improvement
    delta_P_pu(i) = dP;

    if dP > 1e-8
        VSI_raw(i) = delta_Vmin(i) / dP;
    else
        VSI_raw(i) = 0;
    end
end

% Normalize to [0,1]
non_slack = setdiff(1:nb, root);
VSI_max = max(VSI_raw(non_slack));
VSI_norm = zeros(nb,1);
if VSI_max > 0
    VSI_norm(non_slack) = VSI_raw(non_slack) / VSI_max;
end

% Ranking (descending)
[~, rank_all] = sort(VSI_raw, 'descend');
rank_non_slack = rank_all(ismember(rank_all, non_slack));

vsi.VSI_raw      = VSI_raw;
vsi.VSI_norm     = VSI_norm;
vsi.delta_Vmin   = delta_Vmin;
vsi.delta_P_pu   = delta_P_pu;
vsi.rank         = rank_non_slack;
vsi.top10        = rank_non_slack(1:min(10, end));
vsi.peak_hour    = peak_t;
vsi.Vmin_base    = Vmin_base_peak;
vsi.perturb_frac = perturb_frac;

% Save CSV
Bus     = (1:nb)';
VSI_R   = VSI_raw;
VSI_N   = VSI_norm;
DeltaV  = delta_Vmin;
DeltaP  = delta_P_pu;
T_out   = table(Bus, VSI_R, VSI_N, DeltaV, DeltaP, ...
    'VariableNames',{'Bus','VSI_raw','VSI_norm','DeltaVmin','DeltaP_pu'});

if nargin >= 4 && ~isempty(out_dir)
    if ~exist(out_dir,'dir'), mkdir(out_dir); end
    writetable(T_out, fullfile(out_dir,'table_voltage_sensitivity.csv'));
    fprintf('  VSI: peak_hour=%d, Vmin_base=%.4f, top bus=%d (VSI=%.4f)\n', ...
        peak_t, Vmin_base_peak, rank_non_slack(1), VSI_raw(rank_non_slack(1)));
end
end
