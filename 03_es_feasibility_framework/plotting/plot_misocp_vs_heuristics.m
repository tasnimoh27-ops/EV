function plot_misocp_vs_heuristics(comparison_table, fig_path)
%PLOT_MISOCP_VS_HEURISTICS  Bar chart comparing MISOCP vs heuristics.
%   Shows feasible solutions clearly, marks infeasible as gray.

methods  = comparison_table.Method;
vmin_v   = comparison_table.Vmin_pu;
loss_v   = comparison_table.TotalLoss_pu;
feasible = comparison_table.Feasible;

% Replace NaN (infeasible) with 0 for plotting, track feasibility
vmin_plot = vmin_v;
loss_plot = loss_v;
vmin_plot(isnan(vmin_v)) = 0;
loss_plot(isnan(loss_v)) = 0;

fh = figure('Visible','off','Position',[100 100 1000 500]);
ax1 = subplot(1,2,1);
b1 = barh(1:numel(methods), vmin_plot, 0.6);
% Color by feasibility
for i = 1:numel(methods)
    if feasible(i) == 1
        b1(1).CData(i,:) = [0.2 0.6 0.9];  % blue for feasible
    else
        b1(1).CData(i,:) = [0.7 0.7 0.7];  % gray for infeasible
    end
end
hold on;
plot([0.95 0.95],[0 numel(methods)+1],'--r','LineWidth',1.5,'DisplayName','Limit');
% Add text annotations for infeasible
for i = 1:numel(methods)
    if feasible(i) ~= 1
        text(0.05, i, 'INFEASIBLE', 'FontSize',8, 'Color',[0.5 0.5 0.5]);
    end
end
set(ax1,'YTick',1:numel(methods),'YTickLabel',strrep(methods,'_',' '));
xlabel('V_{min} (p.u.)'); title('Minimum Voltage');
xlim([0 1.05]); grid on;

ax2 = subplot(1,2,2);
b2 = barh(1:numel(methods), loss_plot, 0.6);
% Color by feasibility
for i = 1:numel(methods)
    if feasible(i) == 1
        b2(1).CData(i,:) = [0.9 0.5 0.2];  % orange for feasible
    else
        b2(1).CData(i,:) = [0.7 0.7 0.7];  % gray for infeasible
    end
end
set(ax2,'YTick',1:numel(methods),'YTickLabel',strrep(methods,'_',' '));
xlabel('Total Loss (p.u.)'); title('Total Feeder Loss');
grid on; xlim([0 max(loss_plot)*1.2]);

sgtitle('MISOCP vs Heuristic Placement Comparison (Blue/Orange=Feasible, Gray=Infeasible)');

if nargin >= 2 && ~isempty(fig_path)
    saveas(fh, fig_path);
    [d,n,~]=fileparts(fig_path); saveas(fh,fullfile(d,[n '.fig']));
    fprintf('  Saved: %s\n', fig_path);
end
close(fh);
end
