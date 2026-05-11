function vis = calculate_voltage_impact_score(topo, loads, alpha_ncl)
%CALCULATE_VOLTAGE_IMPACT_SCORE  Rank buses by expected ES voltage impact.
%
% Score for bus j:
%   VIS(j) = P_NCL(j) * sum_R_path(j) + Q_NCL(j) * sum_X_path(j)
%
% Higher score = ES at this bus has greater potential voltage lift.
%
% INPUTS
%   topo       topology struct from build_distflow_topology_from_branch_csv
%   loads      loads struct from build_24h_load_profile_from_csv
%   alpha_ncl  NCL fraction scalar
%
% OUTPUTS
%   vis   struct with fields:
%     .score        nb x 1  raw VIS score per bus
%     .rank         nb x 1  bus indices sorted descending by score
%     .sum_R_path   nb x 1  total resistance from slack to each bus
%     .sum_X_path   nb x 1  total reactance from slack to each bus
%     .P_NCL_mean   nb x 1  mean NCL active power across 24h
%     .Q_NCL_mean   nb x 1  mean NCL reactive power across 24h

nb   = topo.nb;
root = topo.root;
from = topo.from(:);
to   = topo.to(:);
R    = topo.R(:);
X    = topo.X(:);
nl   = topo.nl_tree;

% Build parent map via BFS
line_of_child = zeros(nb, 1);
for k = 1:nl
    line_of_child(to(k)) = k;
end

% Accumulate path R and X from root to each bus (BFS order)
sum_R = zeros(nb, 1);
sum_X = zeros(nb, 1);

queue = root;
visited = false(nb, 1);
visited(root) = true;

while ~isempty(queue)
    cur = queue(1);
    queue(1) = [];
    for k = 1:nl
        if from(k) == cur && ~visited(to(k))
            child = to(k);
            sum_R(child) = sum_R(cur) + R(k);
            sum_X(child) = sum_X(cur) + X(k);
            visited(child) = true;
            queue(end+1) = child; %#ok<AGROW>
        end
    end
end

% Mean load (across 24h) as proxy for sizing
P_mean = mean(loads.P24, 2);  % nb x 1
Q_mean = mean(loads.Q24, 2);

P_NCL_mean = alpha_ncl * P_mean;
Q_NCL_mean = alpha_ncl * Q_mean;

score = P_NCL_mean .* sum_R + Q_NCL_mean .* sum_X;
score(root) = 0;  % slack bus never gets ES

[~, rank_idx] = sort(score, 'descend');

vis.score       = score;
vis.rank        = rank_idx;
vis.sum_R_path  = sum_R;
vis.sum_X_path  = sum_X;
vis.P_NCL_mean  = P_NCL_mean;
vis.Q_NCL_mean  = Q_NCL_mean;
end
