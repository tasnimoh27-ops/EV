function plot_hybrid_cost_tradeoff(hybrid_results, fig_path)
%PLOT_HYBRID_COST_TRADEOFF  ES count vs curtailment tradeoff at each Qg level.

Qg_fracs = unique(hybrid_results.Qg_frac);
rho_ref  = 0.50;
umin_ref = 0.00;

mask = (hybrid_results.rho == rho_ref) & (hybrid_results.u_min == umin_ref) & ...
       (hybrid_results.Feasible_volt == 1);
if ~any(mask)
    fprintf('  No feasible cases for reference (rho=%.2f umin=%.2f)\n',rho_ref,umin_ref);
    return
end

sub = hybrid_results(mask,:);
fh  = figure('Visible','off','Position',[100 100 600 450]);
hold on; grid on;

for iq = 1:numel(Qg_fracs)
    qf   = Qg_fracs(iq);
    sub2 = sub(sub.Qg_frac == qf,:);
    if isempty(sub2), continue; end
    [mN,idx] = min(sub2.N_ES_max);
    mc = sub2.MeanCurt(idx);
    scatter(mN, mc*100, 120, 'filled', 'DisplayName', ...
        sprintf('Q_g=%.0f%%',qf*100));
    text(mN+0.3, mc*100, sprintf('Q_g=%.0f%%',qf*100),'FontSize',9);
end

xlabel('Minimum ES count'); ylabel('Mean NCL Curtailment (%)');
title(sprintf('ES Count vs Curtailment Trade-off (\\rho=%.2f)', rho_ref));
legend('Location','best'); hold off;

if nargin >= 2 && ~isempty(fig_path)
    saveas(fh, fig_path);
    [d,n,~]=fileparts(fig_path); saveas(fh,fullfile(d,[n '.fig']));
end
close(fh);
end
