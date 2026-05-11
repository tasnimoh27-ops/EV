function plot_minimum_es_count_vs_umin(min_table, fig_path)
%PLOT_MINIMUM_ES_COUNT_VS_UMIN  Min ES count vs u_min for each rho.

rho_vals = unique(min_table.rho);
fh = figure('Visible','off','Position',[100 100 600 400]);
hold on; grid on;
clr = lines(numel(rho_vals));

for ir = 1:numel(rho_vals)
    rho  = rho_vals(ir);
    mask = (min_table.rho == rho);
    sub  = min_table(mask,:);
    [~,ord] = sort(sub.u_min);
    sub = sub(ord,:);
    N_vals = sub.MinN_ES_feasible;
    N_vals(isnan(N_vals)) = 33;
    plot(sub.u_min, N_vals, 'o-','Color',clr(ir,:),'LineWidth',1.4, ...
        'MarkerSize',7,'DisplayName',sprintf('\\rho=%.2f',rho));
end

xlabel('u_{min} (minimum NCL service level)'); ylabel('Minimum ES count');
title('Minimum ES Devices vs Minimum NCL Service Level');
legend('Location','best');
ylim([0 35]); hold off;

if nargin >= 2 && ~isempty(fig_path)
    saveas(fh, fig_path);
    [d,n,~]=fileparts(fig_path); saveas(fh,fullfile(d,[n '.fig']));
end
close(fh);
end
