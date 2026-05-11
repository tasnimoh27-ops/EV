function fig = plot_voltage_profiles(V_mat, labels, hour, nb, es_buses, title_str)
%PLOT_VOLTAGE_PROFILES  Plot voltage profiles for multiple scenarios.
%
% INPUTS
%   V_mat      nb x nScen  voltage magnitude matrix (p.u.)
%   labels     1 x nScen   cell array of scenario names
%   hour       scalar      hour index for title (e.g. 20 for peak)
%   nb         scalar      number of buses
%   es_buses   vector      ES bus indices to highlight (optional, [] for none)
%   title_str  char        figure title string

if nargin < 5, es_buses = []; end
if nargin < 6, title_str = 'Voltage Profiles'; end

nScen = size(V_mat, 2);
colors = lines(nScen);
styles = {'-o','-s','-d','-^','-v','->','-<','-p','-h'};

fig = figure('Visible','off');
hold on;
for s = 1:nScen
    if ~any(isnan(V_mat(:,s)))
        st = styles{mod(s-1, numel(styles)) + 1};
        plot(1:nb, V_mat(:,s), st, 'Color', colors(s,:), 'LineWidth', 1.2, ...
            'MarkerSize', 4, 'DisplayName', labels{s});
    end
end

yline(0.95, 'k--', 'LineWidth', 1.5, 'HandleVisibility', 'off');
text(1, 0.948, 'V_{min}=0.95 pu', 'Color','k','FontSize',9);

if ~isempty(es_buses)
    xline(es_buses, 'Color', [0.7 0.2 0.1], 'LineStyle', ':', 'Alpha', 0.5, ...
        'HandleVisibility', 'off');
end

hold off;
xlabel('Bus Index'); ylabel('Voltage (p.u.)');
title(sprintf('%s — Hour %d', title_str, hour));
legend('Location','southwest','FontSize',8);
grid on; ylim([0.85 1.05]);
end
