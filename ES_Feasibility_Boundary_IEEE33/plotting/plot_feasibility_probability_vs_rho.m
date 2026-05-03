function plot_feasibility_probability_vs_rho(risk_table, robustness_table, fig_path)
%PLOT_FEASIBILITY_PROBABILITY_VS_RHO  Feasibility prob vs rho per solution.

solutions = unique(robustness_table.Solution);
rho_vals  = unique(robustness_table.EV_Mult);   % using EV_Mult as x-axis stress

fh = figure('Visible','off','Position',[100 100 600 400]);
hold on; grid on;
clr = lines(numel(solutions));

for is = 1:numel(solutions)
    sol_name = solutions{is};
    feas_p   = zeros(numel(rho_vals),1);
    for ir = 1:numel(rho_vals)
        mask = strcmp(robustness_table.Solution, sol_name) & ...
               (robustness_table.EV_Mult == rho_vals(ir));
        if any(mask)
            feas_p(ir) = mean(robustness_table.Feasible(mask));
        end
    end
    plot(rho_vals, feas_p,'o-','Color',clr(is,:),'LineWidth',1.4,...
        'MarkerSize',7,'DisplayName',strrep(sol_name,'_',' '));
end

xlabel('EV stress multiplier'); ylabel('Feasibility probability');
title('Feasibility Under EV Stress Scenarios');
legend('Location','best'); ylim([-0.05 1.05]); hold off;

if nargin >= 3 && ~isempty(fig_path)
    saveas(fh, fig_path);
    [d,n,~]=fileparts(fig_path); saveas(fh,fullfile(d,[n '.fig']));
end
close(fh);
end
