function plot_minimum_es_count_vs_rho(min_table, fig_path)
%PLOT_MINIMUM_ES_COUNT_VS_RHO  Min ES count vs rho for each u_min.

umin_vals = unique(min_table.u_min);
fh = figure('Visible','off','Position',[100 100 600 400]);
hold on; grid on;
clr = lines(numel(umin_vals));
markers = {'o-','s-','d-','^-'};

for iu = 1:numel(umin_vals)
    um = umin_vals(iu);
    mask = (min_table.u_min == um);
    sub  = min_table(mask,:);
    [~,ord] = sort(sub.rho);
    sub = sub(ord,:);
    N_vals = sub.MinN_ES_feasible;
    N_vals(isnan(N_vals)) = 33;  % show 33 for infeasible
    plot(sub.rho, N_vals, markers{min(iu,4)}, 'Color',clr(iu,:), ...
        'LineWidth',1.4,'MarkerSize',7,'DisplayName', ...
        sprintf('u_{min}=%.2f',um));
end

xlabel('\rho (NCL fraction)'); ylabel('Minimum ES count');
title('Minimum ES Devices vs NCL Fraction \rho');
legend('Location','best');
ylim([0 35]); hold off;

if nargin >= 2 && ~isempty(fig_path)
    saveas(fh, fig_path);
    [d,n,~]=fileparts(fig_path); saveas(fh,fullfile(d,[n '.fig']));
end
close(fh);
end
