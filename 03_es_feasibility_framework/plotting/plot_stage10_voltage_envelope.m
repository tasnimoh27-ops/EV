function fh = plot_stage10_voltage_envelope(T_no_es, T_with_es, out_path)
%PLOT_STAGE10_VOLTAGE_ENVELOPE  Voltage min/max envelope by PV penetration.
%
% For each PV penetration level, plots V_min and V_max.
% Separate subplots for with/without ES-1.

if nargin < 3, out_path = []; end

fh = figure('Position', [100 100 1200 500]);

% Plot without ES-1
ax1 = subplot(1,2,1);
pv_scales = T_no_es.pv_scale;
V_min_no_es = T_no_es.Vmin_24h;
V_max_no_es = T_no_es.Vmax_24h;

h1 = plot(pv_scales, V_min_no_es, 'bs-', 'LineWidth', 2, 'MarkerSize', 6, 'DisplayName', 'V_{min}');
hold on
h2 = plot(pv_scales, V_max_no_es, 'rs-', 'LineWidth', 2, 'MarkerSize', 6, 'DisplayName', 'V_{max}');
yline(0.95, 'k--', 'LineWidth', 1.5, 'DisplayName', 'Lower limit (0.95)');
yline(1.05, 'k--', 'LineWidth', 1.5, 'DisplayName', 'Upper limit (1.05)');

xlabel('PV Penetration Scale', 'FontSize', 11);
ylabel('Voltage [pu]', 'FontSize', 11);
title('Without ES-1', 'FontSize', 12, 'FontWeight', 'bold');
grid on
set(ax1, 'YLim', [0.90 1.10]);
legend('Location', 'best');

% Plot with ES-1 (best case by N_ES)
ax2 = subplot(1,2,2);

if ~isempty(T_with_es)
    pv_scales_es = unique(T_with_es.pv_scale);
    V_min_with_es = NaN(size(pv_scales_es));
    V_max_with_es = NaN(size(pv_scales_es));

    for i = 1:length(pv_scales_es)
        idx = (T_with_es.pv_scale == pv_scales_es(i));
        % Take best (lowest N_ES) that is feasible
        T_sub = T_with_es(idx, :);
        T_feas = T_sub(T_sub.VoltageFeasible == 1, :);
        if ~isempty(T_feas)
            [~, best_idx] = min(T_feas.N_ES_used);
            V_min_with_es(i) = T_feas.Vmin_24h(best_idx);
            V_max_with_es(i) = T_feas.Vmax_24h(best_idx);
        else
            % No feasible solution at this scale
            V_min_with_es(i) = T_sub.Vmin_24h(1);
            V_max_with_es(i) = T_sub.Vmax_24h(1);
        end
    end

    plot(pv_scales_es, V_min_with_es, 'bs-', 'LineWidth', 2, 'MarkerSize', 6, 'DisplayName', 'V_{min}');
    hold on
    plot(pv_scales_es, V_max_with_es, 'rs-', 'LineWidth', 2, 'MarkerSize', 6, 'DisplayName', 'V_{max}');
else
    text(0.5, 0.5, 'No ES-1 results', 'HorizontalAlignment', 'center', 'FontSize', 12);
end

yline(0.95, 'k--', 'LineWidth', 1.5, 'DisplayName', 'Lower limit');
yline(1.05, 'k--', 'LineWidth', 1.5, 'DisplayName', 'Upper limit');

xlabel('PV Penetration Scale', 'FontSize', 11);
ylabel('Voltage [pu]', 'FontSize', 11);
title('With ES-1 (Best Configuration)', 'FontSize', 12, 'FontWeight', 'bold');
grid on
set(ax2, 'YLim', [0.90 1.10]);
legend('Location', 'best');

sgtitle('Stage 10: Voltage Envelope vs PV Penetration', 'FontSize', 13, 'FontWeight', 'bold');

if ~isempty(out_path)
    print(fh, out_path, '-dpng', '-r150');
    fprintf('  Saved: %s\n', out_path);
end

end
