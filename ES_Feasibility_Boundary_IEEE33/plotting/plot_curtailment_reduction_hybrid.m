function plot_curtailment_reduction_hybrid(hybrid_results, fig_path)
%PLOT_CURTAILMENT_REDUCTION_HYBRID  Mean curtailment reduction with added Qg.

Qg_fracs = unique(hybrid_results.Qg_frac);
rho_vals = unique(hybrid_results.rho);
N_ref    = 16;  % reference ES budget

fh = figure('Visible','off','Position',[100 100 600 400]);
hold on; grid on;
clr = lines(numel(rho_vals));

for ir=1:numel(rho_vals)
    rho  = rho_vals(ir);
    curt_v = NaN(numel(Qg_fracs),1);
    for iq=1:numel(Qg_fracs)
        qf = Qg_fracs(iq);
        mask = (hybrid_results.rho==rho)&(hybrid_results.Qg_frac==qf)&...
               (hybrid_results.N_ES_max==N_ref)&(hybrid_results.Feasible_volt==1);
        if any(mask)
            curt_v(iq) = mean(hybrid_results.MeanCurt(mask),'omitnan')*100;
        end
    end
    plot(Qg_fracs, curt_v,'o-','Color',clr(ir,:),'LineWidth',1.4,'MarkerSize',7,...
        'DisplayName',sprintf('\\rho=%.2f',rho));
end

xlabel('Reactive support fraction'); ylabel('Mean NCL Curtailment (%)');
title(sprintf('Curtailment Reduction via Reactive Support (N_{ES}=%d)',N_ref));
legend('Location','best'); hold off;

if nargin>=2&&~isempty(fig_path)
    saveas(fh,fig_path);
    [d,n,~]=fileparts(fig_path); saveas(fh,fullfile(d,[n '.fig']));
end
close(fh);
end
