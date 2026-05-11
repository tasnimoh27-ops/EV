function fig = plot_feasibility_heatmap(feas_mat, x_vals, y_vals, x_label, y_label, title_str)
%PLOT_FEASIBILITY_HEATMAP  2D heatmap of feasibility over two parameters.
%
% INPUTS
%   feas_mat   nY x nX  matrix of 1=feasible, 0=infeasible
%   x_vals     1 x nX   x-axis parameter values
%   y_vals     1 x nY   y-axis parameter values
%   x_label    x-axis label string
%   y_label    y-axis label string
%   title_str  figure title

fig = figure('Visible','off');
imagesc(x_vals, y_vals, double(feas_mat));
colormap([0.85 0.2 0.2; 0.2 0.7 0.2]);  % red=infeasible, green=feasible
colorbar('Ticks',[0.25 0.75],'TickLabels',{'INFEASIBLE','FEASIBLE'});
xlabel(x_label); ylabel(y_label);
title(title_str);
set(gca,'YDir','normal');
xticks(x_vals); yticks(y_vals);
grid on;
end
