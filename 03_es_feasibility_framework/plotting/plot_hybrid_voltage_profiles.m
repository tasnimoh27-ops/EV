function plot_hybrid_voltage_profiles(V_profiles, labels, peak_hour, fig_path)
%PLOT_HYBRID_VOLTAGE_PROFILES  Voltage profiles for hybrid ES+Qg cases.
% Convenience alias for plot_voltage_profile_peak with hybrid-specific title.

fh = figure('Visible','off','Position',[100 100 700 400]);
hold on; grid on;
nb  = numel(V_profiles{1});
clr = lines(numel(V_profiles));
for k = 1:numel(V_profiles)
    plot(1:nb, V_profiles{k},'-o','Color',clr(k,:),'LineWidth',1.4,...
        'MarkerSize',4,'DisplayName',labels{k});
end
plot([1 nb],[0.95 0.95],'--r','LineWidth',1.5,'DisplayName','V_{min}');
xlabel('Bus Index'); ylabel('Voltage (p.u.)');
title(sprintf('Hybrid ES+Qg Voltage Profiles — Hour %d', peak_hour));
legend('Location','best'); ylim([0.88 1.08]); hold off;

if nargin >= 4 && ~isempty(fig_path)
    saveas(fh, fig_path);
    [d,n,~]=fileparts(fig_path); saveas(fh,fullfile(d,[n '.fig']));
end
close(fh);
end
