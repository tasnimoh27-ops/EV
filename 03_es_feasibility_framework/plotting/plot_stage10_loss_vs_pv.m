function fh = plot_stage10_loss_vs_pv(T_no_es, T_with_es, out_path)
%PLOT_STAGE10_LOSS_VS_PV  Feeder loss vs PV penetration.
%
% Expected pattern: losses may decrease at moderate PV (local generation),
% but can increase at high PV due to reverse power flow.

if nargin < 3, out_path = []; end

fh = figure('Position', [100 100 900 500]);

hold on
plot(T_no_es.pv_scale, T_no_es.TotalLoss_pu, 'ko-', 'LineWidth', 2, 'MarkerSize', 6, ...
    'DisplayName', 'No ES-1');

if ~isempty(T_with_es)
    % Average loss across ES budgets per penetration level
    pv_scales_es = unique(T_with_es.pv_scale);
    loss_avg = NaN(size(pv_scales_es));
    for i = 1:length(pv_scales_es)
        idx = (T_with_es.pv_scale == pv_scales_es(i));
        loss_avg(i) = mean(T_with_es.TotalLoss_pu(idx), 'omitnan');
    end
    plot(pv_scales_es, loss_avg, 'bs-', 'LineWidth', 2, 'MarkerSize', 6, ...
        'DisplayName', 'With ES-1 (avg)');
end

xlabel('PV Penetration Scale', 'FontSize', 12);
ylabel('Total Feeder Loss [pu]', 'FontSize', 12);
title('Stage 10: Feeder Losses vs PV Penetration', 'FontSize', 13, 'FontWeight', 'bold');
grid on
legend('FontSize', 11);

if ~isempty(out_path)
    print(fh, out_path, '-dpng', '-r150');
    fprintf('  Saved: %s\n', out_path);
end

end
