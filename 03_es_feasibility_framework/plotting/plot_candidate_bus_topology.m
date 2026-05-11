function plot_candidate_bus_topology(topo, ranking, fig_path)
%PLOT_CANDIDATE_BUS_TOPOLOGY  Topology coloured by combined VSI score.

nb   = topo.nb;
root = topo.root;
from = topo.from(:);
to_v = topo.to(:);
x = zeros(nb,1); y = zeros(nb,1);
for b=1:18, x(b)=b; y(b)=0; end
x(19)=2;y(19)=-1; x(20)=3;y(20)=-1; x(21)=4;y(21)=-1; x(22)=5;y(22)=-1;
x(23)=3;y(23)=1; x(24)=4;y(24)=1; x(25)=5;y(25)=1;
for k=1:8, x(25+k)=6+k; y(25+k)=-2; end

score = ranking.score_combined;
s_norm = (score - min(score)) / max(1e-8, max(score)-min(score));

fh = figure('Visible','off','Position',[100 100 900 400]);
hold on; grid on;
for k=1:topo.nl_tree
    f=from(k); t2=to_v(k);
    plot([x(f) x(t2)],[y(f) y(t2)],'b-','LineWidth',1.0);
end
scatter(x, y, 80+60*s_norm, s_norm, 'filled');
colormap('jet'); colorbar; caxis([0 1]);
xlabel('Position (schematic)'); ylabel('');
title('IEEE 33-Bus: Bus Score (Combined VSI+Load+Distance)');
hold off;

if nargin >= 3 && ~isempty(fig_path)
    saveas(fh, fig_path);
    [d,n,~]=fileparts(fig_path); saveas(fh,fullfile(d,[n '.fig']));
end
close(fh);
end
