function plot_feasibility_heatmap(T_results, x_var, y_var, feas_var, fig_path, ttl)
%PLOT_FEASIBILITY_HEATMAP  2D heatmap of feasibility over (x_var, y_var).
%
% T_results: table with columns x_var, y_var, feas_var (0/1)

x_vals = unique(T_results.(x_var));
y_vals = unique(T_results.(y_var));
nx = numel(x_vals); ny = numel(y_vals);

Z = NaN(ny, nx);
for ix = 1:nx
    for iy = 1:ny
        mask = (T_results.(x_var) == x_vals(ix)) & ...
               (T_results.(y_var) == y_vals(iy));
        if any(mask)
            Z(iy, ix) = mean(T_results.(feas_var)(mask));
        end
    end
end

fh = figure('Visible','off','Position',[100 100 600 400]);
imagesc(x_vals, y_vals, Z);
colormap([1 0.3 0.3; 0.3 1 0.3]);  % red=infeasible, green=feasible
colorbar; caxis([0 1]);
xlabel(strrep(x_var,'_',' ')); ylabel(strrep(y_var,'_',' '));
if nargin >= 6 && ~isempty(ttl), title(ttl);
else, title('Feasibility Map'); end
set(gca,'XTick',x_vals,'YTick',y_vals);
xtickangle(45);

if nargin >= 5 && ~isempty(fig_path)
    saveas(fh, fig_path);
    [d,n,~]=fileparts(fig_path); saveas(fh,fullfile(d,[n '.fig']));
end
close(fh);
end
