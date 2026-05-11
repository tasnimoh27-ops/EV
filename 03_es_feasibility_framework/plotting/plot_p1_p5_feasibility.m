function plot_p1_p5_feasibility(T_results, umin_filter, fig_path)
%PLOT_P1_P5_FEASIBILITY  Feasibility map for P1-P5 placements.

mask = (T_results.u_min == umin_filter);
sub  = T_results(mask,:);

placements = unique(sub.Placement,'stable');
rho_vals   = unique(sub.rho);
nP = numel(placements); nR = numel(rho_vals);

Z = NaN(nP, nR);
for ip=1:nP
    for ir=1:nR
        m2 = strcmp(sub.Placement,placements{ip}) & (sub.rho==rho_vals(ir));
        if any(m2), Z(ip,ir) = mean(sub.Feasible(m2)); end
    end
end

fh = figure('Visible','off','Position',[100 100 600 350]);
imagesc(rho_vals, 1:nP, Z);
colormap([0.9 0.3 0.3; 0.3 0.8 0.3]);
colorbar; caxis([0 1]);
set(gca,'YTick',1:nP,'YTickLabel',placements);
xlabel('\rho (NCL fraction)');
title(sprintf('P1–P5 Feasibility Map (u_{min}=%.2f)', umin_filter));
grid on;

if nargin >= 3 && ~isempty(fig_path)
    saveas(fh, fig_path);
    [d,n,~]=fileparts(fig_path); saveas(fh,fullfile(d,[n '.fig']));
end
close(fh);
end
