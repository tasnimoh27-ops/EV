function plot_voltage_slack_vs_es_budget(sweep_results, fig_path)
%PLOT_VOLTAGE_SLACK_VS_ES_BUDGET  Voltage slack vs N_ES_max for each rho.

rho_vals = unique(sweep_results.rho);
fh = figure('Visible','off','Position',[100 100 700 400]);
hold on; grid on;
clr = lines(numel(rho_vals));

for ir = 1:numel(rho_vals)
    rho = rho_vals(ir);
    mask = (sweep_results.rho == rho) & (sweep_results.u_min == 0.20);
    sub  = sweep_results(mask,:);
    [~,ord] = sort(sub.N_ES_max);
    sub = sub(ord,:);
    semilogy(sub.N_ES_max, max(sub.TotalVoltSlack, 1e-8), ...
        'o-','Color',clr(ir,:),'LineWidth',1.4,'MarkerSize',6, ...
        'DisplayName',sprintf('\\rho=%.2f',rho));
end

plot([0 33],[1e-6 1e-6],'--k','LineWidth',1.2,'DisplayName','Feasibility threshold');
xlabel('N_{ES,max}'); ylabel('Total Voltage Slack (log scale)');
title('Voltage Slack vs ES Budget (u_{min}=0.20)');
legend('Location','best'); hold off;

if nargin >= 2 && ~isempty(fig_path)
    saveas(fh, fig_path);
    [d,n,~]=fileparts(fig_path); saveas(fh,fullfile(d,[n '.fig']));
end
close(fh);
end
