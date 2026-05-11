function plot_voltage_sensitivity_bar(vsi, fig_path)
%PLOT_VOLTAGE_SENSITIVITY_BAR  Bar chart of VSI per bus.

nb = numel(vsi.VSI_raw);
fh = figure('Visible','off','Position',[100 100 800 400]);
bar(1:nb, vsi.VSI_norm, 'FaceColor',[0.3 0.6 0.8]);
hold on;
top10 = vsi.top10;
bar(top10, vsi.VSI_norm(top10), 'FaceColor',[1 0.4 0.2]);
grid on;
xlabel('Bus Index'); ylabel('Normalised VSI');
title('Voltage Sensitivity Index — ES Candidate Ranking');
legend({'All buses','Top-10 VSI'},'Location','best');
hold off;

if nargin >= 2 && ~isempty(fig_path)
    saveas(fh, fig_path);
    [d,n,~]=fileparts(fig_path); saveas(fh,fullfile(d,[n '.fig']));
end
close(fh);
end
