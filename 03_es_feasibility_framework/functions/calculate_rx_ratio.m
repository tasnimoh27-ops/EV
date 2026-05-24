function rx_table = calculate_rx_ratio()
    % Calculate R/X ratio for all branches in the network
    % Returns table with branch info and R/X ratio

    % Load branch data
    branch_data = readtable('..\..\01_data\branch_from_to_rx.csv');

    % Extract R and X values
    R = branch_data.BR_R_pu;
    X = branch_data.BR_X_pu;

    % Calculate R/X ratio, handle division by zero
    RX_ratio = R ./ (X + eps);

    % Create output table
    rx_table = table(...
        branch_data.F_BUS, ...
        branch_data.T_BUS, ...
        R, ...
        X, ...
        RX_ratio, ...
        'VariableNames', {'From_Bus', 'To_Bus', 'Resistance_pu', 'Reactance_pu', 'RX_Ratio'});

    % Display summary statistics
    fprintf('\n=== Network R/X Ratio Analysis ===\n');
    fprintf('Total branches: %d\n', height(rx_table));
    fprintf('Mean R/X ratio: %.4f\n', mean(RX_ratio));
    fprintf('Median R/X ratio: %.4f\n', median(RX_ratio));
    fprintf('Min R/X ratio: %.4f\n', min(RX_ratio));
    fprintf('Max R/X ratio: %.4f\n', max(RX_ratio));
    fprintf('Std Dev R/X ratio: %.4f\n\n', std(RX_ratio));

    % Save to CSV
    output_path = '..\..\04_results\es_framework\tables\table_rx_ratio.csv';
    writetable(rx_table, output_path);
    fprintf('Results saved to: %s\n', output_path);
end
