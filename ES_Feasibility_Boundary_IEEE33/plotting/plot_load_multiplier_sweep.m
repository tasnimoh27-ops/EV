function plot_load_multiplier_sweep(sweep_table, fig_path)
%PLOT_LOAD_MULTIPLIER_SWEEP  Vmin and loss vs load multiplier.

fh = figure('Visible','off','Position',[100 100 800 400]);
subplot(1,2,1);
plot(sweep_table.Multiplier, sweep_table.Vmin_pu,'o-b','LineWidth',1.4,'MarkerSize',7);
hold on;
plot([min(sweep_table.Multiplier) max(sweep_table.Multiplier)],[0.95 0.95],'--r','LineWidth',1.5);
grid on; xlabel('Load multiplier'); ylabel('V_{min} (p.u.)');
title('Voltage Degradation vs Load Stress');

subplot(1,2,2);
plot(sweep_table.Multiplier, sweep_table.TotalLoss_pu,'o-r','LineWidth',1.4,'MarkerSize',7);
grid on; xlabel('Load multiplier'); ylabel('Total Loss (p.u.)');
title('Loss vs Load Stress');

if nargin >= 2 && ~isempty(fig_path)
    saveas(fh, fig_path);
    [d,n,~]=fileparts(fig_path); saveas(fh,fullfile(d,[n '.fig']));
end
close(fh);
end
