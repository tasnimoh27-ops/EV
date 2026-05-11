function plot_placement_comparison_curve(heuristic_results, metric_var, fig_path, ttl)
%PLOT_PLACEMENT_COMPARISON_CURVE  V_min or loss vs ES count per method.

if nargin < 4, ttl = sprintf('%s vs ES count by placement method', metric_var); end

methods = unique(heuristic_results.Method);
fh = figure('Visible','off','Position',[100 100 700 400]);
hold on; grid on;
clr = lines(numel(methods));

for im = 1:numel(methods)
    meth = methods{im};
    sub  = heuristic_results(strcmp(heuristic_results.Method, meth),:);
    [~,ord] = sort(sub.k);
    sub = sub(ord,:);
    y_vals = sub.(metric_var);
    plot(sub.k, y_vals, 'o-','Color',clr(im,:),'LineWidth',1.4, ...
        'MarkerSize',6,'DisplayName',strrep(meth,'_',' '));
end

if strcmp(metric_var,'Vmin_pu')
    plot([0 33],[0.95 0.95],'--r','LineWidth',1.5,'DisplayName','V_{min} limit');
    ylabel('V_{min} (p.u.)');
elseif strcmp(metric_var,'TotalLoss_pu')
    ylabel('Total Loss (p.u.)');
end

xlabel('ES device count (k)');
title(ttl);
legend('Location','best');
hold off;

if nargin >= 3 && ~isempty(fig_path)
    saveas(fh, fig_path);
    [d,n,~]=fileparts(fig_path); saveas(fh,fullfile(d,[n '.fig']));
end
close(fh);
end
