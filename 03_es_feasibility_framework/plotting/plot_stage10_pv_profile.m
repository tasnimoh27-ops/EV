function fh = plot_stage10_pv_profile(loads_base, pv_prof, out_path)
%PLOT_STAGE10_PV_PROFILE  Plot 24-hour load and PV profiles.
%
% Shows existing EV-stress load profile overlaid with normalized PV profile,
% demonstrating that the base load multiplier is preserved.

if nargin < 3, out_path = []; end

hours = 1:24;
T = 24;

% Get load multiplier from base loads
if isfield(loads_base, 'profile_mult')
    load_mult = loads_base.profile_mult;
else
    % Fallback: compute from loads
    load_mult = mean(loads_base.P24, 1) ./ mean(loads_base.Pbase);
end

fh = figure('Position', [100 100 1000 600]);

% Plot 1: Load multiplier
ax1 = subplot(1,2,1);
plot(hours, load_mult, 'b-', 'LineWidth', 2, 'DisplayName', 'Load multiplier');
hold on
ax1_2 = ax1;  % save axis handle
xlabel('Hour', 'FontSize', 12);
ylabel('Load Multiplier', 'FontSize', 12);
title('Existing 24h EV-Stress Load Profile', 'FontSize', 12);
grid on
legend('Location', 'best');
set(ax1, 'XLim', [0.5 24.5], 'YLim', [0 2]);

% Plot 2: PV profile
ax2 = subplot(1,2,2);
plot(hours, pv_prof.profile_24h, 'y-', 'LineWidth', 2, 'DisplayName', 'PV profile (normalized)');
hold on
plot(hours, zeros(T,1), 'k--', 'LineWidth', 1);
xlabel('Hour', 'FontSize', 12);
ylabel('Normalized PV Generation', 'FontSize', 12);
title('Hou-Style Solar Profile', 'FontSize', 12);
grid on
legend('Location', 'best');
set(ax2, 'XLim', [0.5 24.5], 'YLim', [-0.1 1.1]);

sgtitle('Stage 10: Existing Load Profile + PV Profile', 'FontSize', 14, 'FontWeight', 'bold');

if ~isempty(out_path)
    print(fh, out_path, '-dpng', '-r150');
    fprintf('  Saved: %s\n', out_path);
end

end
