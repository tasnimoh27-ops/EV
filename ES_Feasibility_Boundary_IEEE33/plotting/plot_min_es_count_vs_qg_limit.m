function plot_min_es_count_vs_qg_limit(hybrid_results, fig_path)
%PLOT_MIN_ES_COUNT_VS_QG_LIMIT  Minimum ES count vs Qg fraction.

Qg_fracs = unique(hybrid_results.Qg_frac);
rho_vals = unique(hybrid_results.rho);

fh = figure('Visible','off','Position',[100 100 600 400]);
hold on; grid on;
clr = lines(numel(rho_vals));

for ir = 1:numel(rho_vals)
    rho = rho_vals(ir);
    N_min = zeros(numel(Qg_fracs),1);
    for iq = 1:numel(Qg_fracs)
        qf = Qg_fracs(iq);
        mask = (hybrid_results.rho==rho) & (hybrid_results.Qg_frac==qf) & ...
               (hybrid_results.Feasible_volt==1);
        if any(mask)
            sub = hybrid_results(mask,:);
            N_min(iq) = min(sub.N_ES_max);
        else
            N_min(iq) = 33;
        end
    end
    plot(Qg_fracs, N_min,'o-','Color',clr(ir,:),'LineWidth',1.4,...
        'MarkerSize',7,'DisplayName',sprintf('\\rho=%.2f',rho));
end

xlabel('Reactive support fraction (Q_g limit / Q_{g,ref})');
ylabel('Minimum ES device count');
title('ES Count Reduction via Reactive Support');
legend('Location','best'); hold off;

if nargin >= 2 && ~isempty(fig_path)
    saveas(fh, fig_path);
    [d,n,~]=fileparts(fig_path); saveas(fh,fullfile(d,[n '.fig']));
end
close(fh);
end
