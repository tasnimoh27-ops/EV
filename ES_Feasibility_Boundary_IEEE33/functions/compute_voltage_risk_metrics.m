function risk = compute_voltage_risk_metrics(robustness_table, out_dir)
%COMPUTE_VOLTAGE_RISK_METRICS  Compute CVaR, VaR, feasibility probability.
%
% Voltage violation loss for scenario s:
%   loss_s = sum over buses and hours of max(0, Vmin_limit - V_i_t_s)
%
% Metrics per solution:
%   - Feasibility probability  = fraction of scenarios with Vmin >= 0.95
%   - Expected voltage violation (EV)
%   - Worst-case violation
%   - VaR_95  = 95th percentile violation
%   - CVaR_95 = mean of worst 5% scenario losses

Vmin_limit = 0.95;

solutions = unique(robustness_table.Solution);
rows = {};

for is = 1:numel(solutions)
    sol_name = solutions{is};
    sub = robustness_table(strcmp(robustness_table.Solution, sol_name), :);
    n_s = height(sub);

    % Proxy for voltage violation loss: use Vmin shortfall
    violation_loss = zeros(n_s, 1);
    for i = 1:n_s
        Vm = sub.Vmin_pu(i);
        if isnan(Vm) || ~sub.Feasible(i)
            % Infeasible: use large loss proxy
            violation_loss(i) = 1.0;
        else
            violation_loss(i) = max(0, Vmin_limit - Vm);
        end
    end

    feas_prob  = mean(sub.Feasible == 1);
    exp_vio    = mean(violation_loss);
    wc_vio     = max(violation_loss);

    % VaR and CVaR at 95% confidence
    sorted_loss = sort(violation_loss, 'ascend');
    var95_idx   = ceil(0.95 * n_s);
    var95_idx   = min(var95_idx, n_s);
    VaR_95      = sorted_loss(var95_idx);

    cvar_tail   = sorted_loss(var95_idx:end);
    CVaR_95     = mean(cvar_tail);

    rows{end+1} = {sol_name, n_s, feas_prob, exp_vio, wc_vio, VaR_95, CVaR_95}; %#ok<AGROW>
end

risk = cell2table(rows, 'VariableNames', ...
    {'Solution','N_Scenarios','FeasProb','ExpViolation', ...
     'WorstCaseViol','VaR_95','CVaR_95'});

if nargin >= 2 && ~isempty(out_dir)
    if ~exist(out_dir,'dir'), mkdir(out_dir); end
    writetable(risk, fullfile(out_dir,'table_voltage_risk_metrics.csv'));
    fprintf('  Voltage risk metrics saved.\n');
end

fprintf('\n  Risk Summary:\n');
fprintf('  %-20s %8s %8s %8s %8s\n','Solution','FeasProb','ExpViol','VaR95','CVaR95');
for i = 1:height(risk)
    fprintf('  %-20s %8.3f %8.4f %8.4f %8.4f\n', ...
        risk.Solution{i}, risk.FeasProb(i), risk.ExpViolation(i), ...
        risk.VaR_95(i), risk.CVaR_95(i));
end
end
