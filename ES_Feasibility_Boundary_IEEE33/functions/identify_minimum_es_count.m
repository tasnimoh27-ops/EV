function [min_table, detail] = identify_minimum_es_count(sweep_results, out_dir)
%IDENTIFY_MINIMUM_ES_COUNT  Find minimum N_ES for feasibility per (rho, u_min).
%
% Reads budget sweep results table and identifies the minimum ES count
% that achieves voltage feasibility for each (rho, u_min) pair.
%
% INPUTS
%   sweep_results  table from run_es_budget_sweep
%   out_dir        output directory
%
% OUTPUTS
%   min_table  table: one row per (rho, u_min) with minimum N_ES and stats
%   detail     cell array of best-case result structs

rho_vals  = unique(sweep_results.rho);
umin_vals = unique(sweep_results.u_min);

rows   = {};
detail = {};

for ir = 1:numel(rho_vals)
    rho = rho_vals(ir);
    for iu = 1:numel(umin_vals)
        u_min = umin_vals(iu);

        mask = (sweep_results.rho == rho) & (sweep_results.u_min == u_min) & ...
               (sweep_results.Feasible_volt == 1);
        if ~any(mask)
            % No feasible case found
            rows{end+1} = {rho, u_min, NaN, NaN, '[]', NaN, NaN, NaN, NaN, NaN}; %#ok<AGROW>
            continue
        end

        sub = sweep_results(mask, :);
        [min_N, idx] = min(sub.N_ES_max);
        row = sub(idx,:);

        rows{end+1} = {rho, u_min, min_N, ...
            row.N_ES_selected, row.ES_Buses{1}, ...
            row.Vmin_pu, row.WorstBus, ...
            row.TotalLoss_pu, row.MeanCurt, row.SolveTime_s}; %#ok<AGROW>

        detail{end+1} = row; %#ok<AGROW>
    end
end

min_table = cell2table(rows, 'VariableNames', ...
    {'rho','u_min','MinN_ES_feasible','N_ES_selected','ES_Buses', ...
     'Vmin_pu','WorstBus','TotalLoss_pu','MeanCurt','SolveTime_s'});

if nargin >= 2 && ~isempty(out_dir)
    if ~exist(out_dir,'dir'), mkdir(out_dir); end
    writetable(min_table, fullfile(out_dir,'table_minimum_es_count.csv'));
    fprintf('  Min ES count table saved.\n');
end

% Print summary
fprintf('\n  Minimum ES count summary:\n');
fprintf('  %-6s %-6s %-8s %-8s\n','rho','u_min','MinN_ES','Vmin');
for i = 1:height(min_table)
    fprintf('  %-6.2f %-6.2f %-8s %-8s\n', ...
        min_table.rho(i), min_table.u_min(i), ...
        num2str(min_table.MinN_ES_feasible(i)), ...
        num2str(min_table.Vmin_pu(i),'%.4f'));
end
end
