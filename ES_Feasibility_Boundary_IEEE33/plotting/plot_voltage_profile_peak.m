function plot_voltage_profile_peak(V_profiles, labels, peak_hour, fig_path)
%PLOT_VOLTAGE_PROFILE_PEAK  Voltage profiles vs bus at peak hour.
%
% V_profiles: cell array of nb×1 voltage vectors
% labels:     cell array of string labels

nb = numel(V_profiles{1});
fh = figure('Visible','off','Position',[100 100 700 400]);
hold on; grid on;
clr = lines(numel(V_profiles));
for k = 1:numel(V_profiles)
    plot(1:nb, V_profiles{k}, '-o','Color',clr(k,:),'LineWidth',1.4, ...
        'MarkerSize',4,'DisplayName',labels{k});
end
plot([1 nb],[0.95 0.95],'--r','LineWidth',1.5,'DisplayName','V_{min}=0.95');
plot([1 nb],[1.05 1.05],'--g','LineWidth',1.2,'DisplayName','V_{max}=1.05');
xlabel('Bus Index'); ylabel('Voltage (p.u.)');
title(sprintf('Voltage Profile — Peak Hour %d', peak_hour));
legend('Location','best'); ylim([0.88 1.08]); hold off;

if nargin >= 4 && ~isempty(fig_path)
    saveas(fh, fig_path);
    [d,n,~]=fileparts(fig_path); saveas(fh,fullfile(d,[n '.fig']));
end
close(fh);
end
