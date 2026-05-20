function fh = plot_stage10_es1_count_vs_pv(T_with_es, out_path)
%PLOT_STAGE10_ES1_COUNT_VS_PV  Minimum ES-1 devices needed vs PV penetration.
%
% For each PV penetration, find minimum N_ES_used that achieves voltage feasibility.

if nargin < 2, out_path = []; end

if isempty(T_with_es)
    warning('No ES-1 results to plot');
    fh = figure();
    return;
end

fh = figure('Position', [100 100 900 500]);

pv_scales = unique(T_with_es.pv_scale);
n_es_min = NaN(size(pv_scales));

for i = 1:length(pv_scales)
    idx = (T_with_es.pv_scale == pv_scales(i));
    T_sub = T_with_es(idx, :);
    % Find minimum N_ES that achieves voltage feasibility
    T_feas = T_sub(T_sub.VoltageFeasible == 1, :);
    if ~isempty(T_feas)
        n_es_min(i) = min(T_feas.N_ES_used);
    end
end

hold on
stem(pv_scales, n_es_min, 'bs-', 'LineWidth', 2, 'MarkerSize', 8);
plot(pv_scales, n_es_min, 'b-', 'LineWidth', 2, 'DisplayName', 'Min N_{ES} for feasibility');

xlabel('PV Penetration Scale', 'FontSize', 12);
ylabel('Minimum Number of ES-1 Devices', 'FontSize', 12);
title('Stage 10: Minimum ES-1 Count Required vs PV Penetration', 'FontSize', 13, 'FontWeight', 'bold');
grid on
legend('FontSize', 11);

if ~isempty(out_path)
    print(fh, out_path, '-dpng', '-r150');
    fprintf('  Saved: %s\n', out_path);
end

end
