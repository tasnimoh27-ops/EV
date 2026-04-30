%% plot_voltage_comparison.m
% Comprehensive bus voltage visualization — with vs without ES
%
% Generates 7 publication-quality figures:
%   Fig1 — Bus voltage profile at peak hour h20 (all datasets)
%   Fig2 — System minimum voltage vs hour (24h trace)
%   Fig3 — Side-by-side voltage heatmaps (Module 7 vs best ES)
%   Fig4 — Voltage delta map (best ES minus Module 7)
%   Fig5 — All 5 feasible ES profiles + loss bar chart
%   Fig6 — Module 9F feasibility boundary map
%   Fig7 — Voltage profiles at 3 key hours
%
% Datasets:
%   Module 7   : SOCP OPF + Qg at all buses (no ES) — FEASIBLE reference
%   Module 8   : ES at {18,33} soft Vmin — diagnostic (no hard constraint)
%   Module 9F  : 5 feasible ES-only cases (all 32 buses, rho=0.60–0.80)
%
% Output: ./out_plots/voltage_comparison/  (PNG + PDF)
%
% Requirements: runs standalone — no solver needed

clear; clc; close all;

outDir = './out_plots/voltage_comparison';
if ~exist(outDir,'dir'), mkdir(outDir); end

nb = 33;   T = 24;   buses = (1:nb)';

% =========================================================================
%  LOAD ALL DATA
% =========================================================================

% Inline CSV loader (handles header row automatically)
f7_V   = './out_socp_opf_gurobi/V_bus_by_hour.csv';
f7_sum = './out_socp_opf_gurobi/opf_summary_24h_cost.csv';
f8_V   = './out_socp_opf_gurobi_es/scenario_C_soft_diag/V_bus_by_hour.csv';
f8_sum = './out_socp_opf_gurobi_es/scenario_C_soft_diag/summary_24h.csv';

V7    = readmatrix(f7_V);      sum7  = readtable(f7_sum);
V8c   = readmatrix(f8_V);      sum8c = readtable(f8_sum);
Vmin7 = sum7.Vmin_pu;          loss7_h = sum7.Loss_pu;
Vmin8 = sum8c.Vmin_pu;         loss8_h = sum8c.Loss_pu;

% 9F case directories and metadata
dirs9F = {
    './out_module9/F_feasibility_scan/cases/scan_P5_rho60_umin00';
    './out_module9/F_feasibility_scan/cases/scan_P5_rho70_umin00';
    './out_module9/F_feasibility_scan/cases/scan_P5_rho70_umin20';
    './out_module9/F_feasibility_scan/cases/scan_P5_rho80_umin00';
    './out_module9/F_feasibility_scan/cases/scan_P5_rho80_umin20';
};
tags9F = {
    '9F: \rho=0.60, u_{min}=0.00';
    '9F: \rho=0.70, u_{min}=0.00';
    '9F: \rho=0.70, u_{min}=0.20  [Lowest Loss]';
    '9F: \rho=0.80, u_{min}=0.00';
    '9F: \rho=0.80, u_{min}=0.20';
};
loss_9F = [0.18492, 0.18725, 0.18212, 0.18738, 0.18692];
curt_9F = [19.2,    14.9,    17.4,    12.1,    13.8   ];
nF = numel(dirs9F);

V9F   = cell(nF,1);
Vmin9 = cell(nF,1);
for k = 1:nF
    V9F{k}   = readmatrix(fullfile(dirs9F{k},'V_bus_by_hour.csv'));
    s        = readtable(fullfile(dirs9F{k},'summary_24h.csv'));
    Vmin9{k} = s.Vmin_pu;
end

% =========================================================================
%  COLOUR PALETTE  (accessible, distinct)
% =========================================================================
clr7    = [0.15 0.15 0.15];   % near-black  — Module 7 (no ES)
clr8    = [0.80 0.40 0.00];   % burnt orange — Module 8 soft
clr9F   = [0.12 0.47 0.71;    % blue
           0.20 0.63 0.17;    % green
           0.89 0.10 0.11;    % red   [best]
           0.58 0.40 0.74;    % purple
           0.30 0.75 0.93];   % teal
lsF     = {'-.','--','-',':','-.'};
Vlim    = 0.95;
ylims   = [0.86 1.02];

% =========================================================================
%  FIG 1 — Voltage profile at peak hour h20 (bus-by-bus)
% =========================================================================
h_pk = 20;
fh1 = figure('Visible','off','Position',[50 50 1000 500]);
hold on; grid on; box on;

fill([1 33 33 1],[ylims(1) ylims(1) Vlim Vlim],[1 0.82 0.82],...
    'FaceAlpha',0.18,'EdgeColor','none','HandleVisibility','off');
text(1.5, 0.873,'V < 0.95 pu violation zone','Color',[0.7 0 0],'FontSize',8);

plot(buses, V7(:,h_pk),  '-o','Color',clr7,'LineWidth',2.2,'MarkerSize',4,...
    'DisplayName','Module 7 — No ES  (Qg, feasible reference)');
plot(buses, V8c(:,h_pk),'--s','Color',clr8,'LineWidth',1.8,'MarkerSize',4,...
    'DisplayName','Module 8 Sc-C — ES\{18,33\} soft (infeasible at hard Vmin)');
ls_arr = {'-^','-v','-d','-p','-h'};
for k = 1:nF
    plot(buses, V9F{k}(:,h_pk), ls_arr{k},'Color',clr9F(k,:),...
        'LineWidth',1.5,'MarkerSize',4,'DisplayName',tags9F{k});
end
plot([1 nb],[Vlim Vlim],'--k','LineWidth',1.3,...
    'DisplayName','V_{min} limit = 0.95 pu');

xline(18,':', 'Color',[0.5 0 0.5],'LineWidth',1.0,'HandleVisibility','off');
xline(30,':', 'Color',[0.5 0 0.5],'LineWidth',1.0,'HandleVisibility','off');
text(18.2,0.878,'Bus18','Color',[0.5 0 0.5],'FontSize',8);
text(30.2,0.878,'Bus30\n(Q/P=3)','Color',[0.5 0 0.5],'FontSize',8);

xlim([1 nb]); ylim(ylims);
set(gca,'XTick',1:2:33,'FontSize',10);
xlabel('Bus Number','FontSize',12,'FontWeight','bold');
ylabel('Voltage Magnitude (p.u.)','FontSize',12,'FontWeight','bold');
title(sprintf('IEEE 33-Bus Voltage Profile — Hour %d (\\alpha=1.20, worst case)',h_pk),...
    'FontSize',13,'FontWeight','bold');
lgd = legend('Location','southwest','FontSize',9,'Box','on','NumColumns',1);
hold off;
saveas(fh1, fullfile(outDir,'Fig1_voltage_profile_h20.png'));
print(fh1, fullfile(outDir,'Fig1_voltage_profile_h20'),'-dpdf','-r300');
close(fh1);
fprintf('Fig1 saved.\n');

% =========================================================================
%  FIG 2 — System Vmin vs hour (24h trace)
% =========================================================================
fh2 = figure('Visible','off','Position',[50 50 1000 470]);
hold on; grid on; box on;

% Shade peak tariff zone
patch([17 21 21 17],[ylims(1) ylims(1) ylims(2) ylims(2)],[1.0 0.95 0.80],...
    'FaceAlpha',0.30,'EdgeColor','none','HandleVisibility','off');
text(17.3, ylims(2)-0.005,'Peak Tariff (x1.8)','FontSize',8,'Color',[0.6 0.3 0]);

plot(1:T, Vmin7, '-o', 'Color',clr7,'LineWidth',2.2,'MarkerSize',5,...
    'DisplayName','Module 7 — No ES (Qg only)');
plot(1:T, Vmin8,'--s','Color',clr8,'LineWidth',1.8,'MarkerSize',5,...
    'DisplayName','Module 8 Sc-C — ES\{18,33\} soft');
for k = 1:nF
    plot(1:T, Vmin9{k}, ls_arr{k},'Color',clr9F(k,:),'LineWidth',1.5,'MarkerSize',4,...
        'DisplayName',tags9F{k});
end
plot([1 T],[Vlim Vlim],'--k','LineWidth',1.3,'DisplayName','V_{min} = 0.95 pu limit');

xlim([1 T]); ylim(ylims);
set(gca,'XTick',1:2:24,'FontSize',10);
xlabel('Hour of Day','FontSize',12,'FontWeight','bold');
ylabel('System Minimum Voltage (p.u.)','FontSize',12,'FontWeight','bold');
title('System Minimum Voltage vs Hour — With and Without Electric Spring',...
    'FontSize',13,'FontWeight','bold');
legend('Location','southwest','FontSize',9,'Box','on');
hold off;
saveas(fh2, fullfile(outDir,'Fig2_Vmin_vs_hour.png'));
print(fh2, fullfile(outDir,'Fig2_Vmin_vs_hour'),'-dpdf','-r300');
close(fh2);
fprintf('Fig2 saved.\n');

% =========================================================================
%  FIG 3 — Side-by-side heatmaps: Module 7 vs 9F Best (rho=0.70 umin=0.20)
% =========================================================================
V_best = V9F{3};   % rho=0.70, umin=0.20 — best loss
fh3 = figure('Visible','off','Position',[50 50 1200 460]);

ax1 = subplot(1,2,1);
imagesc(1:T, buses, V7); axis xy;
colormap(ax1, parula(128)); clim([0.87 1.00]);
cb1 = colorbar; cb1.Label.String = 'V (p.u.)'; cb1.FontSize = 9;
set(gca,'XTick',1:4:24,'YTick',[1 6 9 13 18 22 26 30 33],'FontSize',9,...
    'YTickLabel',{'1','6','9','13','18','22','26','30','33'});
xlabel('Hour','FontSize',11,'FontWeight','bold');
ylabel('Bus Number','FontSize',11,'FontWeight','bold');
title({'Module 7 — No ES (Qg Support)';'Vmin = 0.9500 pu | Loss = 0.2284 pu'},...
    'FontSize',11,'FontWeight','bold');
hold(ax1,'on');
yline(ax1,18,'--w','LineWidth',1.2,'Label','Bus 18','LabelHorizontalAlignment','right',...
    'FontSize',7,'HandleVisibility','off');
yline(ax1,30,'-.w','LineWidth',1.0,'Label','Bus 30','LabelHorizontalAlignment','right',...
    'FontSize',7,'HandleVisibility','off');
hold(ax1,'off');

ax2 = subplot(1,2,2);
imagesc(1:T, buses, V_best); axis xy;
colormap(ax2, parula(128)); clim([0.87 1.00]);
cb2 = colorbar; cb2.Label.String = 'V (p.u.)'; cb2.FontSize = 9;
set(gca,'XTick',1:4:24,'YTick',[1 6 9 13 18 22 26 30 33],'FontSize',9,...
    'YTickLabel',{'1','6','9','13','18','22','26','30','33'});
xlabel('Hour','FontSize',11,'FontWeight','bold');
ylabel('Bus Number','FontSize',11,'FontWeight','bold');
title({'9F Best ES — \rho=0.70, u_{min}=0.20 (All 32 buses)';...
    'Vmin = 0.9500 pu | Loss = 0.1821 pu (−20.3%)'},...
    'FontSize',11,'FontWeight','bold');
hold(ax2,'on');
yline(ax2,18,'--w','LineWidth',1.2,'Label','Bus 18','LabelHorizontalAlignment','right',...
    'FontSize',7,'HandleVisibility','off');
yline(ax2,30,'-.w','LineWidth',1.0,'Label','Bus 30','LabelHorizontalAlignment','right',...
    'FontSize',7,'HandleVisibility','off');
hold(ax2,'off');

sgtitle('Voltage Heatmap (Bus \times Hour): No-ES Reference vs Best ES Case',...
    'FontSize',13,'FontWeight','bold');
saveas(fh3, fullfile(outDir,'Fig3_voltage_heatmap_comparison.png'));
print(fh3, fullfile(outDir,'Fig3_voltage_heatmap_comparison'),'-dpdf','-r300');
close(fh3);
fprintf('Fig3 saved.\n');

% =========================================================================
%  FIG 4 — Voltage delta map: Best ES minus Module 7
% =========================================================================
dV = V_best - V7;

% Build diverging colourmap: blue–white–red
n2 = 64; half = n2/2;
cmap_bwr = [[linspace(0.17,1,half)'; linspace(1,0.84,half)'],...
            [linspace(0.43,1,half)'; linspace(1,0.19,half)'],...
            [linspace(0.81,1,half)'; linspace(1,0.15,half)']];

fh4 = figure('Visible','off','Position',[50 50 900 430]);
imagesc(1:T, buses, dV); axis xy;
colormap(fh4, cmap_bwr);
cmax = max(abs(dV(:)));  clim([-cmax cmax]);
cb = colorbar; cb.Label.String = '\DeltaV = V_{ES} - V_{no-ES}  (p.u.)'; cb.FontSize=10;
set(gca,'XTick',1:4:24,'YTick',[1 6 9 13 18 22 26 30 33],'FontSize',10,...
    'YTickLabel',{'1','6','9','13','18','22','26','30','33'});
xlabel('Hour','FontSize',12,'FontWeight','bold');
ylabel('Bus Number','FontSize',12,'FontWeight','bold');
title({'\DeltaVoltage Map — Best ES (\rho=0.70, u_{min}=0.20) minus Module 7 (No ES)';...
    'Blue = ES lower than No-ES  |  Red = ES higher than No-ES'},...
    'FontSize',11,'FontWeight','bold');
hold on;
yline(18,'--k','LineWidth',1.0,'HandleVisibility','off');
yline(30,'-.k','LineWidth',0.8,'HandleVisibility','off');
text(1.3, 19.3,'Bus 18','FontSize',8,'Color','k');
text(1.3, 31.0,'Bus 30 (Q/P=3.0)','FontSize',8,'Color','k');
hold off;
saveas(fh4, fullfile(outDir,'Fig4_voltage_delta_map.png'));
print(fh4, fullfile(outDir,'Fig4_voltage_delta_map'),'-dpdf','-r300');
close(fh4);
fprintf('Fig4 saved.\n');

% =========================================================================
%  FIG 5 — Multi-panel: all 5 feasible ES profiles at h20 + loss bar
% =========================================================================
panel_titles = {
    '\rho=0.60, u_{min}=0.00';
    '\rho=0.70, u_{min}=0.00';
    '\rho=0.70, u_{min}=0.20  [Lowest Loss]';
    '\rho=0.80, u_{min}=0.00';
    '\rho=0.80, u_{min}=0.20';
};

fh5 = figure('Visible','off','Position',[50 50 1260 680]);
for k = 1:nF
    subplot(2,3,k);
    hold on; grid on; box on;
    fill([1 33 33 1],[ylims(1) ylims(1) Vlim Vlim],[1 0.82 0.82],...
        'FaceAlpha',0.12,'EdgeColor','none','HandleVisibility','off');
    plot(buses, V7(:,h_pk), '-','Color',[0.65 0.65 0.65],'LineWidth',1.8,...
        'DisplayName','No ES (Mod7)');
    plot(buses, V9F{k}(:,h_pk),'-','Color',clr9F(k,:),'LineWidth',2.2,...
        'DisplayName','With ES (9F)');
    plot([1 nb],[Vlim Vlim],'--k','LineWidth',0.9,'HandleVisibility','off');
    xlim([1 nb]); ylim(ylims);
    set(gca,'XTick',[1 6 9 12 15 18 21 24 27 30 33],'FontSize',8.5,'XTickLabelRotation',45);
    xlabel('Bus','FontSize',10); ylabel('V (p.u.)','FontSize',10);
    sub = sprintf('Loss=%.4f pu  |  Curt=%.1f%%',loss_9F(k),curt_9F(k));
    title({panel_titles{k}; sub},'FontSize',9,'FontWeight','bold');
    if k==1
        legend('Location','southwest','FontSize',8.5,'Box','off');
    end
    hold off;
end

% 6th panel: grouped bar — total 24h loss
ax6 = subplot(2,3,6);
hold on; grid on; box on;
bar_vals = [sum(loss7_h); sum(loss8_h); loss_9F(:)];
bar_lbl  = {'No-ES\n(Mod7)','Soft-ES\n(Mod8)','9F\nrho0.60','9F\nrho0.70','9F\nrho0.70','9F\nrho0.80','9F\nrho0.80'};
bar_c    = [clr7; clr8; clr9F];
bh = bar(1:7, bar_vals, 0.65, 'FaceColor','flat');
for b = 1:7, bh.CData(b,:) = bar_c(b,:); end
% Reference line = Module 7
plot([0.5 7.5],[sum(loss7_h) sum(loss7_h)],'--k','LineWidth',1.0);
text(5.5, sum(loss7_h)+0.003,'No-ES baseline','FontSize',7,'Color','k');
set(ax6,'XTick',1:7,...
    'XTickLabel',{'NoES','SoftES','r0.60\nu0.00','r0.70\nu0.00','r0.70\nu0.20',...
                  'r0.80\nu0.00','r0.80\nu0.20'},...
    'XTickLabelRotation',35,'FontSize',7.5);
ylabel('Total 24h Loss (p.u.)','FontSize',9);
title({'Total Feeder Loss'; 'ES cases < No-ES by 18–20%'},'FontSize',9,'FontWeight','bold');
ylim([0.15 0.37]);
hold off;

sgtitle(sprintf('Bus Voltage at Peak Hour (h%d) — All 5 Feasible ES Cases vs No-ES',h_pk),...
    'FontSize',13,'FontWeight','bold');
saveas(fh5, fullfile(outDir,'Fig5_all_feasible_ES_profiles.png'));
print(fh5, fullfile(outDir,'Fig5_all_feasible_ES_profiles'),'-dpdf','-r300');
close(fh5);
fprintf('Fig5 saved.\n');

% =========================================================================
%  FIG 6 — 9F Feasibility Boundary Map
% =========================================================================
scan = readtable('./out_module9/F_feasibility_scan/scan_results.csv');

rho_v = [0.20 0.30 0.40 0.50 0.60 0.70 0.80];
umin_v = [0.00 0.20];
feas_map = NaN(5, numel(rho_v), 2);
loss_map = NaN(5, numel(rho_v), 2);

for row = 1:height(scan)
    pi  = scan.PlacementIdx(row);
    ri  = find(abs(rho_v - scan.rho(row)) < 1e-4);
    ui  = find(abs(umin_v - scan.u_min(row)) < 1e-4);
    if isempty(ri)||isempty(ui)||isempty(pi), continue; end
    feas_map(pi,ri,ui) = strcmpi(scan.Status{row},'FEASIBLE');
    if feas_map(pi,ri,ui)==1
        loss_map(pi,ri,ui) = scan.TotalLoss_pu(row);
    end
end

cmap_feas = [0.91 0.24 0.20; 0.22 0.66 0.29];  % red/green
plbl = {'P1: \{18,33\}  2 buses','P2: 4 buses','P3: VIS-7  7 buses',...
        'P4: 11 buses','P5: All 32 buses'};
uml  = {'u_{min} = 0.00','u_{min} = 0.20'};

fh6 = figure('Visible','off','Position',[50 50 1120 400]);
for ui = 1:2
    ax = subplot(1,2,ui);
    sl = feas_map(:,:,ui);
    imagesc(sl); axis xy;
    colormap(ax, cmap_feas); clim([0 1]);
    set(ax,'XTick',1:7,'XTickLabel',arrayfun(@(r) sprintf('%.2f',r),rho_v,'uni',false),...
        'YTick',1:5,'YTickLabel',plbl,'FontSize',9.5,'TickLength',[0 0]);
    xlabel('NCL Fraction \rho','FontSize',11,'FontWeight','bold');
    if ui==1, ylabel('ES Placement Strategy','FontSize',11,'FontWeight','bold'); end
    title(uml{ui},'FontSize',12,'FontWeight','bold');

    for pi = 1:5
        for ri = 1:7
            v = sl(pi,ri);
            if isnan(v), continue; end
            if v == 1
                if ~isnan(loss_map(pi,ri,ui))
                    txt = sprintf('F\n%.4f pu', loss_map(pi,ri,ui));
                else
                    txt = 'F';
                end
                fs = 7.5; fw = 'bold';
            else
                txt = '✗'; fs = 13; fw = 'normal';
            end
            text(ri, pi, txt,'HorizontalAlignment','center',...
                'VerticalAlignment','middle','Color','w',...
                'FontSize',fs,'FontWeight',fw);
        end
    end
end

% Shared colourbar
annot_ax = axes('Position',[0.92 0.15 0.01 0.70],'Visible','off');
colormap(annot_ax, cmap_feas); clim([0 1]);
cb6 = colorbar(annot_ax,'Position',[0.93 0.15 0.025 0.70]);
cb6.Ticks = [0.25 0.75]; cb6.TickLabels = {'Infeasible','Feasible'}; cb6.FontSize = 10;

sgtitle({'Module 9F — Feasibility Boundary: ES Placement \times NCL Fraction';...
    'F = Feasible (loss shown in p.u.)  |  \times = Infeasible'},...
    'FontSize',12,'FontWeight','bold');
saveas(fh6, fullfile(outDir,'Fig6_9F_feasibility_map.png'));
print(fh6, fullfile(outDir,'Fig6_9F_feasibility_map'),'-dpdf','-r300');
close(fh6);
fprintf('Fig6 saved.\n');

% =========================================================================
%  FIG 7 — Voltage profiles at 3 key hours
% =========================================================================
key_hrs = [8 17 20];
hr_lbl  = {'Hour 8 — Daytime  (\alpha=0.82)','Hour 17 — Peak Ramp  (\alpha=1.00)',...
    'Hour 20 — Worst Case  (\alpha=1.20)'};

fh7 = figure('Visible','off','Position',[50 50 1280 430]);
for hi = 1:3
    h = key_hrs(hi);
    subplot(1,3,hi);
    hold on; grid on; box on;
    fill([1 33 33 1],[ylims(1) ylims(1) Vlim Vlim],[1 0.82 0.82],...
        'FaceAlpha',0.12,'EdgeColor','none','HandleVisibility','off');
    plot(buses, V7(:,h),  '-o','Color',clr7,'LineWidth',2.0,'MarkerSize',4,...
        'DisplayName','Mod7 — No ES (Qg)');
    plot(buses, V8c(:,h),'--s','Color',clr8,'LineWidth',1.6,'MarkerSize',4,...
        'DisplayName','Mod8 Sc-C — soft ES');
    plot(buses, V9F{3}(:,h),'-d','Color',clr9F(3,:),'LineWidth',2.0,'MarkerSize',4,...
        'DisplayName','9F Best (\rho=0.70, u=0.20)');
    plot([1 nb],[Vlim Vlim],'--k','LineWidth',1.0,'HandleVisibility','off');
    xlim([1 nb]); ylim(ylims);
    set(gca,'XTick',1:4:33,'FontSize',9);
    xlabel('Bus Number','FontSize',11,'FontWeight','bold');
    ylabel('Voltage (p.u.)','FontSize',11,'FontWeight','bold');
    title(hr_lbl{hi},'FontSize',10,'FontWeight','bold');
    if hi==1
        legend('Location','southwest','FontSize',9,'Box','on');
    end
    hold off;
end
sgtitle('Voltage Profile at 3 Key Hours — No ES vs Soft ES vs Best Feasible ES',...
    'FontSize',13,'FontWeight','bold');
saveas(fh7, fullfile(outDir,'Fig7_voltage_key_hours.png'));
print(fh7, fullfile(outDir,'Fig7_voltage_key_hours'),'-dpdf','-r300');
close(fh7);
fprintf('Fig7 saved.\n');

% =========================================================================
%  CONSOLE SUMMARY
% =========================================================================
loss_m7 = sum(loss7_h);
fprintf('\n%s\n  VOLTAGE COMPARISON SUMMARY\n%s\n',repmat('=',1,78),repmat('=',1,78));
fmt = '  %-42s  %-9s  %-10s  %-8s\n';
fprintf(fmt,'Case','Vmin@h20','TotalLoss','vs Mod7');
fprintf('  %s\n',repmat('-',1,74));
fprintf(fmt,'Module 7 — No ES (Qg only)', ...
    sprintf('%.4f',min(V7(:,20))), sprintf('%.4f',loss_m7),'baseline');
fprintf(fmt,'Module 8 Sc-C — ES{18,33} soft', ...
    sprintf('%.4f',min(V8c(:,20))), sprintf('%.4f',sum(loss8_h)),...
    sprintf('%+.3f',sum(loss8_h)-loss_m7));
for k = 1:nF
    fprintf(fmt, sprintf('9F %s',strrep(tags9F{k},'\','')), ...
        sprintf('%.4f',min(V9F{k}(:,20))), sprintf('%.4f',loss_9F(k)),...
        sprintf('%+.3f',loss_9F(k)-loss_m7));
end
fprintf('%s\n',repmat('=',1,78));
fprintf('\nAll figures saved to: %s\n', outDir);
