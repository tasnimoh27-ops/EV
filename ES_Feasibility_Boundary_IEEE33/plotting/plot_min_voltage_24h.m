function plot_min_voltage_24h(Vmin_t_cell, labels, fig_path)
%PLOT_MIN_VOLTAGE_24H  Min voltage vs hour for multiple cases.

T = 24;
fh = figure('Visible','off','Position',[100 100 700 400]);
hold on; grid on;
clr = lines(numel(Vmin_t_cell));
for k = 1:numel(Vmin_t_cell)
    plot(1:T, Vmin_t_cell{k}, '-o','Color',clr(k,:),'LineWidth',1.4,...
        'MarkerSize',4,'DisplayName',labels{k});
end
plot([1 T],[0.95 0.95],'--r','LineWidth',1.5,'DisplayName','V_{min} limit');
xlabel('Hour'); ylabel('Min Voltage (p.u.)');
title('Minimum System Voltage — 24-Hour Profile');
legend('Location','best'); ylim([0.88 1.02]); hold off;

if nargin >= 3 && ~isempty(fig_path)
    saveas(fh, fig_path);
    [d,n,~]=fileparts(fig_path); saveas(fh,fullfile(d,[n '.fig']));
end
close(fh);
end
