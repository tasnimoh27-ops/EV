function results = compare_candidate_placement_sets(topo, loads, ranking, out_dir, ops)
%COMPARE_CANDIDATE_PLACEMENT_SETS  Compare heuristic ES placement strategies.
%
% Tests multiple placement methods at varying budget k for selected (rho, u_min).
%
% Methods: weak-bus, end-feeder, highest-load, VSI, combined-score, P1-P5.

if nargin < 5 || isempty(ops)
    ops = sdpsettings('solver','gurobi','verbose',0);
    ops.gurobi.TimeLimit = 120;
end

k_vals    = [2, 4, 7, 11, 16, 20, 24, 32];
test_cases = {0.50, 0.00; 0.60, 0.00; 0.70, 0.20};
nTC        = size(test_cases,1);

methods = {'weakest_bus','end_feeder','highest_load','VSI','combined'};
ranks   = {ranking.rank_weak, ranking.rank_endfeed, ranking.rank_load, ...
           ranking.rank_vsi,  ranking.rank_combined};

nb   = topo.nb;
root = topo.root;
non_slack = setdiff(1:nb, root);
T   = 24;
price = ones(T,1);
price(1:6)=0.6; price(7:16)=1.0; price(17:21)=1.8; price(22:24)=0.9;

rows = {};
ct   = 0;
nTotal = nTC * numel(k_vals) * numel(methods);

for itc = 1:nTC
    rho   = test_cases{itc,1};
    u_min = test_cases{itc,2};

    for ik = 1:numel(k_vals)
        k = k_vals(ik);

        for im = 1:numel(methods)
            ct = ct + 1;
            mname = methods{im};
            rank_v = ranks{im};

            if k > numel(rank_v)
                buses = rank_v(:)';
            else
                buses = rank_v(1:k)';
            end
            buses = sort(buses);

            fprintf('  [%d/%d] %s k=%d rho=%.2f umin=%.2f ...\n', ...
                ct, nTotal, mname, k, rho, u_min);

            label = sprintf('%s_k%d_r%.0f_u%.0f', mname, k, rho*100, u_min*100);
            r = solve_es_fixed_placement(topo, loads, buses, rho, u_min, ops, label);

            if r.feasible
                Vmin_v = min(r.Vmin_t);
                loss_v = r.total_loss;
                meanC  = r.mean_curtailment;
                maxC   = max(max(1 - r.u_val(buses,:)));
                wbus   = r.VminBus_t(r.worst_hour);
            else
                Vmin_v=NaN; loss_v=NaN; meanC=NaN; maxC=NaN; wbus=NaN;
            end

            rows{end+1} = {mname, mat2str(buses), k, rho, u_min, ...
                double(r.feasible), Vmin_v, wbus, loss_v, meanC, maxC, ...
                r.sol_code}; %#ok<AGROW>
        end
    end
end

results = cell2table(vertcat(rows{:}), 'VariableNames', ...
    {'Method','Buses','k','rho','u_min','Feasible', ...
     'Vmin_pu','WorstBus','TotalLoss_pu','MeanCurt','MaxCurt','SolCode'});

if nargin >= 4 && ~isempty(out_dir)
    if ~exist(out_dir,'dir'), mkdir(out_dir); end
    writetable(results, fullfile(out_dir,'table_heuristic_placement_comparison.csv'));
    fprintf('  Heuristic comparison saved.\n');
end
end
