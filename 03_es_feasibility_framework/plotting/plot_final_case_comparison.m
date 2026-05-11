function plot_final_case_comparison(final_table, fig_dir)
%PLOT_FINAL_CASE_COMPARISON  Multi-metric bar chart for final C0-C5 cases.

cases    = final_table.Case;
vmin_v   = final_table.Vmin_pu;
loss_v   = final_table.TotalLoss_pu;
curt_v   = final_table.MeanCurt;
n_es_v   = final_table.N_ES;
nc = numel(cases);
x  = 1:nc;
lbls = strrep(cases,'_',' ');

fh = figure('Visible','off','Position',[100 100 1100 500]);

% Panel 1: Vmin
subplot(1,4,1);
bar(x, vmin_v, 0.7, 'FaceColor',[0.3 0.6 0.9]);
hold on;
plot([0 nc+1],[0.95 0.95],'--r','LineWidth',1.5);
set(gca,'XTick',x,'XTickLabel',lbls,'XTickLabelRotation',45);
ylabel('V_{min} (p.u.)'); title('Min Voltage'); grid on; ylim([0.88 1.02]);

% Panel 2: Loss
subplot(1,4,2);
bar(x, loss_v, 0.7, 'FaceColor',[0.9 0.6 0.2]);
set(gca,'XTick',x,'XTickLabel',lbls,'XTickLabelRotation',45);
ylabel('Total Loss (p.u.)'); title('Feeder Loss'); grid on;

% Panel 3: Curtailment
subplot(1,4,3);
bar(x, curt_v*100, 0.7, 'FaceColor',[0.6 0.4 0.8]);
set(gca,'XTick',x,'XTickLabel',lbls,'XTickLabelRotation',45);
ylabel('Mean NCL Curtailment (%)'); title('Curtailment'); grid on;

% Panel 4: ES count
subplot(1,4,4);
bar(x, n_es_v, 0.7, 'FaceColor',[0.4 0.8 0.6]);
set(gca,'XTick',x,'XTickLabel',lbls,'XTickLabelRotation',45);
ylabel('ES device count'); title('ES Count'); grid on;

sgtitle('Final IEEE 33-Bus Case Comparison (C0–C5)');

if nargin >= 2 && ~isempty(fig_dir)
    fp = fullfile(fig_dir,'fig_final_case_comparison.png');
    saveas(fh, fp);
    saveas(fh, fullfile(fig_dir,'fig_final_case_comparison.fig'));
end
close(fh);
end
