function plot_ieee33_topology(topo, highlight_buses, fig_path)
%PLOT_IEEE33_TOPOLOGY  Schematic topology of IEEE 33-bus radial feeder.

if nargin < 2, highlight_buses = []; end
if nargin < 3, fig_path = ''; end

nb   = topo.nb;
from = topo.from(:);
to_v = topo.to(:);

% Simple 1D bus layout along feeder main trunk and laterals
% Bus x-positions: trunk (1-18), lateral from 2 (19-22), lateral from 3 (23-25),
%                  lateral from 6 (26-33)
x = zeros(nb,1); y = zeros(nb,1);
% Main trunk
for b = 1:18, x(b)=b; y(b)=0; end
% Lateral 1: bus 2 -> 19->20->21->22
x(19)=2; y(19)=-1; x(20)=3; y(20)=-1; x(21)=4; y(21)=-1; x(22)=5; y(22)=-1;
% Lateral 2: bus 3 -> 23->24->25
x(23)=3; y(23)=1; x(24)=4; y(24)=1; x(25)=5; y(25)=1;
% Lateral 3: bus 6 -> 26->27->28->29->30->31->32->33
for k=1:8, x(25+k)=6+k; y(25+k)=-2; end

fh = figure('Visible','off','Position',[100 100 900 400]);
hold on; grid on;
% Draw branches
for k = 1:topo.nl_tree
    f=from(k); t2=to_v(k);
    plot([x(f) x(t2)],[y(f) y(t2)],'b-','LineWidth',1.2);
end
% Draw buses
scatter(x, y, 80, 'ko', 'filled');
% Highlight buses
if ~isempty(highlight_buses)
    scatter(x(highlight_buses), y(highlight_buses), 150, 'r^', 'filled');
end
% Labels
for b = 1:nb
    text(x(b)+0.1, y(b)+0.15, num2str(b), 'FontSize',7, 'Color','k');
end
xlabel('Position (schematic)'); ylabel('');
title('IEEE 33-Bus Radial Distribution Feeder Topology');
if ~isempty(highlight_buses)
    legend({'Branch','Bus','ES Bus'},'Location','best');
end
hold off;

if ~isempty(fig_path)
    saveas(fh, fig_path);
    [fp,fn,~] = fileparts(fig_path);
    saveas(fh, fullfile(fp,[fn '.fig']));
end
close(fh);
end
