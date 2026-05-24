function plot_worst_voltage_deficit_vs_rho(feasibility_table, varargin)
%PLOT_WORST_VOLTAGE_DEFICIT_VS_RHO  Worst voltage deficit vs rho parameter.
%
%   plot_worst_voltage_deficit_vs_rho(table, fig_path)
%   plot_worst_voltage_deficit_vs_rho(table, u_min_filter, fig_path)
%
% Inputs:
%   feasibility_table : table with columns: rho, u_min, Placement, Vmin_pu, Feasible
%   u_min_filter : (optional) filter to specific u_min value, default = 0.20
%   fig_path : (optional) path to save PNG, also saves .fig
%
% Uses: Vmin_pu to calculate VoltageDeficit = max(0, 0.95 - Vmin_pu)

    % Parse inputs
    fig_path = [];
    u_min_filter = 0.20;

    if nargin >= 2
        if isnumeric(varargin{1})
            u_min_filter = varargin{1};
        end
    end
    if nargin >= 3
        fig_path = varargin{2};
    elseif nargin >= 2 && ischar(varargin{1})
        fig_path = varargin{1};
    end

    % Filter by feasibility and u_min
    mask_feas = feasibility_table.Feasible == 1;
    mask_umin = feasibility_table.u_min == u_min_filter;
    mask = mask_feas & mask_umin;

    if ~any(mask)
        % Fall back: try any feasible with u_min = 0.20
        mask = (feasibility_table.Feasible == 1) & ...
               (feasibility_table.u_min == 0.20);
    end

    if ~any(mask)
        % Last resort: any feasible
        mask = feasibility_table.Feasible == 1;
    end

    subset = feasibility_table(mask, :);

    if height(subset) == 0
        warning('No feasible solutions found.');
        return;
    end

    % Calculate voltage deficit
    Vmin_threshold = 0.95;
    subset.VoltageDeficit = max(0, Vmin_threshold - subset.Vmin_pu);

    % Get unique placements
    placements = unique(subset.Placement, 'stable');

    % Create figure
    fh = figure('Visible','off','Position',[100 100 700 500]);
    hold on; grid on;
    clr = lines(numel(placements));

    % Plot each placement strategy
    for ip = 1:numel(placements)
        pname = placements{ip};
        mask_p = strcmp(subset.Placement, pname);
        sub_p = subset(mask_p, :);
        [rho_sort, ord] = sort(sub_p.rho);
        deficit_sort = sub_p.VoltageDeficit(ord);

        plot(rho_sort, deficit_sort, 'o-', ...
            'Color', clr(ip,:), 'LineWidth', 1.4, 'MarkerSize', 6, ...
            'DisplayName', pname);
    end

    xlabel('\rho (non-critical load fraction)', 'FontSize', 11);
    ylabel('Worst Voltage Deficit [pu below 0.95 V_{min}]', 'FontSize', 11);
    title(sprintf('Worst Voltage Deficit vs \\rho (u_{min}=%.2f)', u_min_filter), ...
        'FontSize', 12);
    legend('Location', 'best');
    hold off;

    % Save if path provided
    if ~isempty(fig_path)
        saveas(fh, fig_path);
        [d,n,~] = fileparts(fig_path);
        saveas(fh, fullfile(d, [n '.fig']));
        fprintf('  Saved: %s\n', fig_path);
    end

    close(fh);
end
