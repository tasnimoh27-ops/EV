function plot_misocp_vs_heuristics(comparison_table, fig_path)
%PLOT_MISOCP_VS_HEURISTICS  Bar chart comparing MISOCP vs heuristics.

methods  = comparison_table.Method;
vmin_v   = comparison_table.Vmin_pu;
loss_v   = comparison_table.TotalLoss_pu;
feasible = comparison_table.Feasible;

fh = figure('Visible','off','Position',[100 100 900 450]);
ax1 = subplot(1,2,1);
barh(1:numel(methods), vmin_v, 0.6);
hold on;
plot([0.95 0.95],[0 numel(methods)+1],'--r','LineWidth',1.5);
set(ax1,'YTick',1:numel(methods),'YTickLabel',strrep(methods,'_',' '));
xlabel('V_{min} (p.u.)'); title('Minimum Voltage');
xlim([0.88 1.02]); grid on;

ax2 = subplot(1,2,2);
barh(1:numel(methods), loss_v, 0.6, 'FaceColor',[0.9 0.5 0.2]);
set(ax2,'YTick',1:numel(methods),'YTickLabel',strrep(methods,'_',' '));
xlabel('Total Loss (p.u.)'); title('Total Feeder Loss');
grid on;

sgtitle('MISOCP vs Heuristic Placement Comparison');

if nargin >= 2 && ~isempty(fig_path)
    saveas(fh, fig_path);
    [d,n,~]=fileparts(fig_path); saveas(fh,fullfile(d,[n '.fig']));
end
close(fh);
end
