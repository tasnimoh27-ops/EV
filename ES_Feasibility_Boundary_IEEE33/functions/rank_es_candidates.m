function ranking = rank_es_candidates(topo, loads, vsi)
%RANK_ES_CANDIDATES  Rank buses by multiple ES placement criteria.
%
% Generates 5 rankings:
%   1. Weakest voltage (lowest Vmin at peak hour)
%   2. End-feeder (electrical distance from root — longest path)
%   3. Highest load (largest mean P_load)
%   4. VSI (perturbation-based voltage sensitivity)
%   5. Combined score = 0.6*VSI_norm + 0.2*Load_norm + 0.2*ElecDist_norm
%
% INPUTS
%   topo   topology struct
%   loads  loads struct (P24, Q24)
%   vsi    struct from compute_voltage_sensitivity_index
%
% OUTPUT
%   ranking  struct with per-method ranked bus lists and scores

nb   = topo.nb;
root = topo.root;
non_slack = setdiff(1:nb, root);

% --- Criterion 1: Weakest voltage (run DistFlow at peak hour) ---
V_init = ones(nb,1);
peak_t = vsi.peak_hour;
try
    [V_peak,~,~,~] = run_distflow_bfs(topo, loads.P24(:,peak_t), ...
                                       loads.Q24(:,peak_t), V_init);
catch
    V_peak = ones(nb,1);
end
% Lower voltage = higher priority; invert for sorting
[~, rank_weak] = sort(V_peak, 'ascend');
rank_weak = rank_weak(ismember(rank_weak, non_slack));

% --- Criterion 2: Electrical distance (path resistance sum) ---
from_v = topo.from(:);
to_v   = topo.to(:);
R_v    = topo.R(:);
X_v    = topo.X(:);
nl     = topo.nl_tree;

line_of_child = zeros(nb,1);
for k = 1:nl, line_of_child(to_v(k)) = k; end

sum_R = zeros(nb,1);
sum_X = zeros(nb,1);
queue = root; visited = false(nb,1); visited(root)=true;
while ~isempty(queue)
    cur=queue(1); queue(1)=[];
    for k=1:nl
        if from_v(k)==cur && ~visited(to_v(k))
            c=to_v(k); sum_R(c)=sum_R(cur)+R_v(k); sum_X(c)=sum_X(cur)+X_v(k);
            visited(c)=true; queue(end+1)=c;
        end
    end
end
elec_dist = sum_R + sum_X;
[~, rank_endfeed] = sort(elec_dist, 'descend');
rank_endfeed = rank_endfeed(ismember(rank_endfeed, non_slack));

% --- Criterion 3: Highest load ---
P_mean = mean(loads.P24, 2);
[~, rank_load] = sort(P_mean, 'descend');
rank_load = rank_load(ismember(rank_load, non_slack));

% --- Criterion 4: VSI ---
rank_vsi = vsi.rank;

% --- Criterion 5: Combined score ---
% Normalize each criterion to [0,1] on non-slack buses
norm_fn = @(x) (x - min(x(non_slack))) / max(1e-8, max(x(non_slack)) - min(x(non_slack)));

VSI_n   = norm_fn(vsi.VSI_norm);
Load_n  = norm_fn(P_mean);
Dist_n  = norm_fn(elec_dist);

combined = zeros(nb,1);
combined(non_slack) = 0.6*VSI_n(non_slack) + ...
                      0.2*Load_n(non_slack) + ...
                      0.2*Dist_n(non_slack);

[~, rank_combined] = sort(combined, 'descend');
rank_combined = rank_combined(ismember(rank_combined, non_slack));

% Package output
ranking.rank_weak     = rank_weak;
ranking.rank_endfeed  = rank_endfeed;
ranking.rank_load     = rank_load;
ranking.rank_vsi      = rank_vsi;
ranking.rank_combined = rank_combined;
ranking.score_vsi     = vsi.VSI_norm;
ranking.score_load    = P_mean;
ranking.score_dist    = elec_dist;
ranking.score_combined = combined;
ranking.V_peak        = V_peak;
ranking.non_slack     = non_slack;

fprintf('  Candidate ranking done. Top-5 combined: %s\n', ...
    mat2str(rank_combined(1:5)'));
end
