function plot_selected_es_buses_topology(topo, es_buses, label, fig_path)
%PLOT_SELECTED_ES_BUSES_TOPOLOGY  Show MISOCP-selected ES buses on topology.
plot_ieee33_topology(topo, es_buses, '');
fh = gcf;
if ~isempty(label)
    t = get(gca,'Title'); t.String = [t.String ' — ' label];
end
if nargin >= 4 && ~isempty(fig_path)
    saveas(fh, fig_path);
    [d,n,~]=fileparts(fig_path); saveas(fh,fullfile(d,[n '.fig']));
end
close(fh);
end
