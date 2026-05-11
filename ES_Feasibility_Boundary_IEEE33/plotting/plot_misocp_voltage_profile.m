function plot_misocp_voltage_profile(res_misocp, topo, fig_path)
%PLOT_MISOCP_VOLTAGE_PROFILE  Voltage profile for MISOCP solution.

if ~res_misocp.feasible, fprintf('  Cannot plot — infeasible\n'); return; end
nb = topo.nb;
V  = res_misocp.V_val(:, res_misocp.worst_hour);

fh = figure('Visible','off','Position',[100 100 700 400]);
bar(1:nb, V, 0.7, 'FaceColor',[0.3 0.6 0.9]);
hold on;
plot([1 nb],[0.95 0.95],'--r','LineWidth',1.5,'DisplayName','V_{min}');
plot([1 nb],[1.05 1.05],'--g','LineWidth',1.2,'DisplayName','V_{max}');
if ~isempty(res_misocp.es_buses)
    scatter(res_misocp.es_buses, V(res_misocp.es_buses)+0.003, ...
        80,'r^','filled','DisplayName','ES bus');
end
xlabel('Bus Index'); ylabel('Voltage (p.u.)');
title(sprintf('MISOCP Solution — Voltage Profile (Worst Hour %d)', res_misocp.worst_hour));
legend('Location','best'); ylim([0.88 1.08]); hold off;

if nargin >= 3 && ~isempty(fig_path)
    saveas(fh, fig_path);
    [d,n,~]=fileparts(fig_path); saveas(fh,fullfile(d,[n '.fig']));
end
close(fh);
end
