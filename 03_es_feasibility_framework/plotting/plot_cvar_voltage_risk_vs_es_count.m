function plot_cvar_voltage_risk_vs_es_count(risk_table, fig_path)
%PLOT_CVAR_VOLTAGE_RISK_VS_ES_COUNT  CVaR_95 voltage risk per solution.

solutions = risk_table.Solution;
cvar_v    = risk_table.CVaR_95;
feas_p    = risk_table.FeasProb;

[~,ord] = sort(cvar_v,'ascend');
solutions = solutions(ord);
cvar_v    = cvar_v(ord);
feas_p    = feas_p(ord);

fh = figure('Visible','off','Position',[100 100 700 450]);
subplot(2,1,1);
barh(1:numel(solutions), cvar_v, 0.6, 'FaceColor',[0.8 0.3 0.3]);
set(gca,'YTick',1:numel(solutions),'YTickLabel',strrep(solutions,'_',' '));
xlabel('CVaR_{95} Voltage Deficit (p.u.)');
title('Voltage Risk (CVaR_{95}) by Solution');
grid on;

subplot(2,1,2);
barh(1:numel(solutions), feas_p*100, 0.6, 'FaceColor',[0.3 0.7 0.4]);
set(gca,'YTick',1:numel(solutions),'YTickLabel',strrep(solutions,'_',' '));
xlabel('Feasibility Probability (%)');
title('Feasibility Probability by Solution');
grid on;

if nargin >= 2 && ~isempty(fig_path)
    saveas(fh, fig_path);
    [d,n,~]=fileparts(fig_path); saveas(fh,fullfile(d,[n '.fig']));
end
close(fh);
end
