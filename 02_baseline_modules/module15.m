%% run_module9F_feasibility_scan.m
% MODULE 9F — Feasibility Boundary Scan
%
% Research question:
%   What is the feasibility boundary in the (ES placement density, rho)
%   parameter space?  Where exactly does the system transition from
%   INFEASIBLE to FEASIBLE as we increase ES spatial coverage and NCL
%   fraction?
%
% Approach:
%   Parametric sweep over:
%     - ES bus set (5 placement strategies, increasing coverage)
%     - rho in {0.20, 0.30, 0.40, 0.50, 0.60, 0.70, 0.80}
%     - u_min in {0.00, 0.20}
%   For each combination, solve the SOCP-OPF with hard Vmin=0.95.
%   Record feasible/infeasible.
%
% ES Placement Strategies:
%   P1: {18, 33}               — Module 8 (terminal only, 2 buses)
%   P2: {9, 18, 26, 33}        — Add upstream midpoints (4 buses)
%   P3: {6, 9, 13, 18, 26, 30, 33} — VIS-ranked full set (7 buses)
%   P4: {3,6,9,12,15,18,21,24,27,30,33} — Every 3rd bus (11 buses)
%   P5: all non-slack buses    — Full coverage (32 buses)
%
% Output:
%   ./out_module9/F_feasibility_scan/
%     scan_results.csv          — full result table
%     feasibility_map.png       — 2D feasibility map (placement × rho)
%
% NOTE: This scan runs up to 70 cases.  Each case has TimeLimit=90s.
%       Estimated wall time: 60-90 minutes.
%       Run as background job or overnight.
%
% Requirements: YALMIP + Gurobi, solve_hybrid_opf_case.m

clear; clc; close all;

caseDir   = './01_data';
loadsCsv  = fullfile(caseDir, 'loads_base.csv');
branchCsv = fullfile(caseDir, 'branch.csv');
assert(exist(loadsCsv,'file')==2,  'Missing: %s', loadsCsv);
assert(exist(branchCsv,'file')==2, 'Missing: %s', branchCsv);

topo  = build_distflow_topology_from_branch_csv(branchCsv, 1);
loads = build_24h_load_profile_from_csv(loadsCsv, 'system', true, false);
nb    = topo.nb;

T = 24;
price = ones(T,1);
price(1:6)=0.6; price(7:16)=1.0; price(17:21)=1.8; price(22:24)=0.9;

% Short time limit per case — we only need feasibility yes/no
ops = sdpsettings('solver','gurobi','verbose',0);
ops.gurobi.TimeLimit = 90;

topDir = './out_module9/F_feasibility_scan';
if ~exist(topDir,'dir'), mkdir(topDir); end

fprintf('\n=== Module 9F: Feasibility Boundary Scan ===\n');

% =========================================================================
%  PARAMETER GRID
% =========================================================================

% ES placement strategies
P_all = setdiff(1:nb, topo.root);   % all non-slack buses

placements = {
    [18, 33],                                          'P1: {18,33} — 2 buses';
    [9, 18, 26, 33],                                   'P2: {9,18,26,33} — 4 buses';
    [6, 9, 13, 18, 26, 30, 33],                        'P3: VIS-7 — 7 buses';
    [3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 33],         'P4: Every-3rd — 11 buses';
    P_all,                                             'P5: All — 32 buses';
};
nP = size(placements, 1);

rho_vals  = [0.20, 0.30, 0.40, 0.50, 0.60, 0.70, 0.80];
umin_vals = [0.00, 0.20];

nRho  = numel(rho_vals);
nUmin = numel(umin_vals);
nTotal = nP * nRho * nUmin;

fprintf('Total cases: %d  (expected wall time: ~%d min at 90s/case)\n', ...
    nTotal, ceil(nTotal*90/60));

% =========================================================================
%  STORAGE
% =========================================================================
rowPlacementLabel = cell(nTotal,1);
rowPlacementIdx   = zeros(nTotal,1);
rowNbuses         = zeros(nTotal,1);
rowRho            = zeros(nTotal,1);
rowUmin           = zeros(nTotal,1);
rowFeasible       = false(nTotal,1);
rowMinVmin        = NaN(nTotal,1);
rowTotalLoss      = NaN(nTotal,1);
rowMeanCurt       = NaN(nTotal,1);
rowSolCode        = zeros(nTotal,1);

% 3D feasibility matrix for heatmap: [nP x nRho x nUmin]
feas_map = NaN(nP, nRho, nUmin);

caseIdx = 0;
t_start = tic;

% =========================================================================
%  SWEEP
% =========================================================================
for p = 1:nP
    es_b  = placements{p,1};
    plbl  = placements{p,2};

    for ri = 1:nRho
        rho_val = rho_vals(ri);

        for ui = 1:nUmin
            umin_val = umin_vals(ui);
            caseIdx  = caseIdx + 1;

            % Build rho and u_min vectors
            rho_v   = zeros(nb,1);
            umin_v  = ones(nb,1);
            for b = es_b(:)'
                rho_v(b)  = rho_val;
                umin_v(b) = umin_val;
            end

            sc.name         = sprintf('scan_P%d_rho%02d_umin%02d', ...
                                p, round(rho_val*100), round(umin_val*100));
            sc.label        = sprintf('%s  rho=%.2f  umin=%.2f', plbl, rho_val, umin_val);
            sc.es_buses     = es_b;
            sc.rho          = rho_v;
            sc.u_min        = umin_v;
            sc.lambda_u     = 5.0;
            sc.qg_buses     = [];
            sc.Qg_max       = zeros(nb,1);
            sc.lambda_q     = 0;
            sc.second_gen   = false;
            sc.S_rated      = zeros(nb,1);
            sc.Vmin         = 0.95;
            sc.Vmax         = 1.05;
            sc.soft_voltage = false;
            sc.lambda_sv    = 0;
            sc.price        = price;
            sc.out_dir      = fullfile(topDir,'cases', sc.name);

            fprintf('[%3d/%3d] P%d rho=%.2f u_min=%.2f ... ', ...
                caseIdx, nTotal, p, rho_val, umin_val);

            try
                r = solve_hybrid_opf_case(sc, topo, loads, ops);
                rowFeasible(caseIdx) = r.feasible;
                if r.feasible
                    rowMinVmin(caseIdx)   = min(r.Vmin_t);
                    rowTotalLoss(caseIdx) = r.total_loss;
                    rowMeanCurt(caseIdx)  = r.mean_curtailment;
                    feas_map(p, ri, ui)   = 1;
                    fprintf('FEASIBLE  Vmin=%.4f\n', rowMinVmin(caseIdx));
                else
                    feas_map(p, ri, ui) = 0;
                    fprintf('INFEASIBLE\n');
                end
                rowSolCode(caseIdx) = r.sol_code;
            catch ME
                fprintf('ERROR: %s\n', ME.message);
                rowFeasible(caseIdx) = false;
                rowSolCode(caseIdx)  = -99;
                feas_map(p, ri, ui)  = 0;
            end

            rowPlacementLabel{caseIdx} = plbl;
            rowPlacementIdx(caseIdx)   = p;
            rowNbuses(caseIdx)         = numel(es_b);
            rowRho(caseIdx)            = rho_val;
            rowUmin(caseIdx)           = umin_val;

            % Save incremental CSV (protect against crash)
            if mod(caseIdx,5) == 0
                save_scan_csv(topDir, caseIdx, rowPlacementLabel, ...
                    rowPlacementIdx, rowNbuses, rowRho, rowUmin, ...
                    rowFeasible, rowMinVmin, rowTotalLoss, rowMeanCurt, rowSolCode);
            end
        end
    end
end

elapsed = toc(t_start);
fprintf('\nScan complete. %d cases in %.1f min.\n', nTotal, elapsed/60);

% =========================================================================
%  FINAL CSV
% =========================================================================
save_scan_csv(topDir, nTotal, rowPlacementLabel, rowPlacementIdx, ...
    rowNbuses, rowRho, rowUmin, rowFeasible, rowMinVmin, ...
    rowTotalLoss, rowMeanCurt, rowSolCode);

% =========================================================================
%  FEASIBILITY MAP PLOTS
% =========================================================================

% For each u_min, plot a heatmap: rows=placement, cols=rho
placement_short = {'P1:{18,33}','P2:4bus','P3:VIS7','P4:11bus','P5:All'};
umin_labels     = {'u\_min=0.00','u\_min=0.20'};

for ui = 1:nUmin
    feas_slice = feas_map(:,:,ui);   % nP × nRho

    fh = figure('Visible','off');
    imagesc(feas_slice); colormap([0.9 0.2 0.2; 0.2 0.8 0.2]);
    colorbar('Ticks',[0 1],'TickLabels',{'Infeasible','Feasible'});
    set(gca,'XTick',1:nRho,'XTickLabel',arrayfun(@(r) sprintf('%.2f',r), ...
        rho_vals,'UniformOutput',false));
    set(gca,'YTick',1:nP,'YTickLabel',placement_short);
    xlabel('NCL Fraction \rho');
    ylabel('ES Placement Strategy');
    title(sprintf('Feasibility Map — %s  (Hard Vmin=0.95)', umin_labels{ui}));
    % Overlay text labels
    for pi=1:nP
        for ri=1:nRho
            v = feas_slice(pi,ri);
            if ~isnan(v)
                txt = ternary(v==1,'F','X');
                text(ri, pi, txt, 'HorizontalAlignment','center', ...
                    'FontSize',10,'FontWeight','bold','Color','w');
            end
        end
    end
    saveas(fh, fullfile(topDir, sprintf('feasibility_map_umin%02d.png', ...
        round(umin_vals(ui)*100)))); close(fh);
end

% Combined: show min voltage for feasible cases (u_min=0 only)
vmin_slice = NaN(nP, nRho);
for pi=1:nP
    for ri=1:nRho
        idx = (pi-1)*nRho*nUmin + (ri-1)*nUmin + 1;  % u_min=0 row
        if rowFeasible(idx)
            vmin_slice(pi,ri) = rowMinVmin(idx);
        end
    end
end
fh = figure('Visible','off');
imagesc(vmin_slice,[0.88 1.00]);
colormap(hot(64)); cb=colorbar; cb.Label.String='Min Voltage (p.u.)';
set(gca,'XTick',1:nRho,'XTickLabel',arrayfun(@(r) sprintf('%.2f',r), ...
    rho_vals,'UniformOutput',false));
set(gca,'YTick',1:nP,'YTickLabel',placement_short);
xlabel('NCL Fraction \rho');
ylabel('ES Placement Strategy');
title('Min Voltage at Optimal — u\_min=0.00 (NaN = Infeasible)');
saveas(fh, fullfile(topDir,'Vmin_heatmap_umin0.png')); close(fh);

fprintf('Outputs saved to: %s\n', topDir);


% =========================================================================
%  LOCAL HELPERS
% =========================================================================
function save_scan_csv(topDir, n, plabel, pidx, nbus, rho, umin, feas, vmin, loss, curt, code)
    isFeasStr = cell(n,1);
    for i=1:n
        if feas(i), isFeasStr{i}='FEASIBLE'; else, isFeasStr{i}='INFEASIBLE'; end
    end
    T_out = table(plabel(1:n), pidx(1:n), nbus(1:n), rho(1:n), umin(1:n), ...
        isFeasStr, vmin(1:n), loss(1:n), curt(1:n)*100, code(1:n), ...
        'VariableNames',{'PlacementLabel','PlacementIdx','N_ES_buses', ...
            'rho','u_min','Status','MinVmin_pu','TotalLoss_pu', ...
            'MeanCurt_pct','SolCode'});
    writetable(T_out, fullfile(topDir,'scan_results.csv'));
end

function out = ternary(cond, a, b)
    if cond, out=a; else, out=b; end
end
