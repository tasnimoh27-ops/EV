function fh = plot_stage10_vmax_vs_pv(T_no_es, T_with_es, out_path)
%PLOT_STAGE10_VMAX_VS_PV  Maximum voltage vs PV penetration.
%
% Shows overvoltage risk and how ES-1 mitigates it.

if nargin < 3, out_path = []; end

fh = figure('Position', [100 100 900 500]);

hold on
plot(T_no_es.pv_scale, T_no_es.Vmax_24h, 'r^-', 'LineWidth', 2, 'MarkerSize', 7, ...
    'DisplayName', 'No ES-1');

if ~isempty(T_with_es)
    % Best ES-1 case per penetration level
    pv_scales_es = unique(T_with_es.pv_scale);
    Vmax_best = NaN(size(pv_scales_es));
    for i = 1:length(pv_scales_es)
        idx = (T_with_es.pv_scale == pv_scales_es(i));
        T_sub = T_with_es(idx, :);
        [~, best_idx] = min(T_sub.N_ES_used);
        Vmax_best(i) = T_sub.Vmax_24h(best_idx);
    end
    plot(pv_scales_es, Vmax_best, 'b^-', 'LineWidth', 2, 'MarkerSize', 7, ...
        'DisplayName', 'With ES-1 (best)');
end

yline(1.05, 'k--', 'LineWidth', 2, 'DisplayName', 'Upper limit (1.05)');

xlabel('PV Penetration Scale', 'FontSize', 12);
ylabel('Maximum Voltage [pu]', 'FontSize', 12);
title('Stage 10: Overvoltage Risk vs PV Penetration', 'FontSize', 13, 'FontWeight', 'bold');
grid on
legend('FontSize', 11);
set(gca, 'YLim', [0.95 1.15]);

if ~isempty(out_path)
    print(fh, out_path, '-dpng', '-r150');
    fprintf('  Saved: %s\n', out_path);
end

end
