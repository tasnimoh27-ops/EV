%% run_module9_master.m
% MODULE 9 — Master Cross-Comparison Script
%
% Loads saved results from all Module 9 sub-modules (9A-9F) and generates
% a unified cross-module comparison.  Run this AFTER all sub-modules have
% completed.
%
% What this script does:
%   1. Read the *_comparison.csv from each sub-module output directory
%   2. Merge into one master table
%   3. Print ranked summary (by MinVmin, then TotalLoss)
%   4. Generate cross-module figures:
%        - Feasibility count per module (bar)
%        - MinVmin vs TotalLoss scatter (all feasible scenarios)
%        - Loss reduction vs Module 7 baseline (bar, feasible only)
%   5. Save master_comparison.csv and all figures to ./out_module9/
%
% Requirements: Module 9A-9F must have been run first.

clear; clc; close all;

outRoot = './out_module9';
if ~exist(outRoot,'dir'), mkdir(outRoot); end

fprintf('\n=== MODULE 9 MASTER COMPARISON ===\n\n');

% =========================================================================
%  MODULE 7 BASELINE
% =========================================================================
base7file = './out_socp_opf_gurobi/opf_summary_24h_cost.csv';
has_base7 = exist(base7file,'file') == 2;
if has_base7
    base7 = readtable(base7file);
    base7_loss  = sum(base7.Loss_pu);
    base7_vmin  = min(base7.Vmin_pu);
    fprintf('Module 7 baseline: MinVmin=%.4f  TotalLoss=%.5f pu\n', base7_vmin, base7_loss);
else
    base7_loss = NaN;
    base7_vmin = NaN;
    fprintf('Module 7 baseline file not found — skipping baseline comparison.\n');
end

% =========================================================================
%  COLLECT SUB-MODULE CSV FILES
% =========================================================================
submodule_info = {
    'A', 'A_distributed',   '9A_comparison.csv',   'Distributed ES';
    'B', 'B_hybrid_qg',     '9B_comparison.csv',   'Hybrid ES+Qg';
    'C', 'C_hetero_rho',    '9C_comparison.csv',   'Hetero-rho';
    'D', 'D_second_gen_es', '9D_comparison.csv',   '2nd-Gen ES';
    'E', 'E_full_hybrid',   '9E_comparison.csv',   'Full Hybrid';
    'F', 'F_feasibility_scan', 'scan_results.csv', 'Feasibility Scan';
};
nMod = size(submodule_info, 1);

all_rows = table();   % will accumulate all rows

for m = 1:nMod
    modTag   = submodule_info{m,1};
    modDir   = submodule_info{m,2};
    csvName  = submodule_info{m,3};
    modLabel = submodule_info{m,4};

    % CSV can be in <topDir>/comparison/ or directly in <topDir>/
    cmpFile1 = fullfile(outRoot, modDir, 'comparison', csvName);
    cmpFile2 = fullfile(outRoot, modDir, csvName);

    if exist(cmpFile1,'file')
        cmpFile = cmpFile1;
    elseif exist(cmpFile2,'file')
        cmpFile = cmpFile2;
    else
        fprintf('  [SKIP] Module 9%s: CSV not found (%s)\n', modTag, csvName);
        continue;
    end

    T_sub = readtable(cmpFile);

    % Normalise column names — sub-modules use slightly different schemas
    % Expected minimum: Status, MinVmin_pu, TotalLoss_pu
    if ~ismember('Module', T_sub.Properties.VariableNames)
        T_sub.Module = repmat({['9' modTag ' ' modLabel]}, height(T_sub), 1);
    end

    % Keep only the columns we need; fill missing with NaN / empty
    req_cols = {'Module','Status','MinVmin_pu','TotalLoss_pu','MeanCurt_pct'};
    for c = req_cols
        if ~ismember(c{1}, T_sub.Properties.VariableNames)
            if strcmp(c{1},'Status')
                T_sub.(c{1}) = repmat({'N/A'}, height(T_sub), 1);
            else
                T_sub.(c{1}) = NaN(height(T_sub),1);
            end
        end
    end

    % Add Label column if present under different names
    if ismember('Label', T_sub.Properties.VariableNames)
        lbl_col = T_sub.Label;
    elseif ismember('PlacementLabel', T_sub.Properties.VariableNames)
        lbl_col = T_sub.PlacementLabel;
    elseif ismember('label', T_sub.Properties.VariableNames)
        lbl_col = T_sub.label;
    else
        lbl_col = repmat({''}, height(T_sub),1);
    end
    T_sub.Label = lbl_col;

    sub_out = T_sub(:, {'Module','Label','Status','MinVmin_pu','TotalLoss_pu','MeanCurt_pct'});
    all_rows = [all_rows; sub_out]; %#ok<AGROW>

    nFeas = sum(strcmpi(T_sub.Status,'FEASIBLE'));
    fprintf('  Module 9%s (%s): %d rows, %d FEASIBLE\n', modTag, modLabel, height(T_sub), nFeas);
end

if isempty(all_rows)
    fprintf('\nNo sub-module results found. Run 9A-9F first.\n');
    return;
end

fprintf('\nTotal rows collected: %d\n', height(all_rows));

% =========================================================================
%  MASTER CSV
% =========================================================================
writetable(all_rows, fullfile(outRoot,'master_comparison.csv'));
fprintf('Saved: %s/master_comparison.csv\n', outRoot);

% =========================================================================
%  RANKED SUMMARY TABLE (feasible only, sorted by MinVmin desc, then Loss asc)
% =========================================================================
isFeas = strcmpi(all_rows.Status,'FEASIBLE');
feas_rows = all_rows(isFeas,:);

fprintf('\n%s\n  ALL FEASIBLE SCENARIOS (sorted: MinVmin desc, Loss asc)\n%s\n', ...
    repmat('=',1,95), repmat('=',1,95));
fmt = '  %-25s  %-38s  %-8s  %-12s  %-10s\n';
fprintf(fmt,'Module','Label','MinVmin','TotalLoss_pu','MeanCurt%');
fprintf('  %s\n', repmat('-',1,95));

if ~isempty(feas_rows)
    [~, idx] = sortrows([feas_rows.MinVmin_pu, feas_rows.TotalLoss_pu], [-1, 2]);
    feas_sorted = feas_rows(idx,:);
    for i = 1:height(feas_sorted)
        row = feas_sorted(i,:);
        lbl = ''; if iscell(row.Label), lbl=row.Label{1}; else, lbl=row.Label; end
        mod = ''; if iscell(row.Module), mod=row.Module{1}; else, mod=row.Module; end
        fprintf(fmt, mod(1:min(end,25)), lbl(1:min(end,38)), ...
            fmt_v(row.MinVmin_pu), fmt_v(row.TotalLoss_pu), fmt_v(row.MeanCurt_pct));
    end
else
    fprintf('  (no feasible scenarios found)\n');
end
fprintf('%s\n', repmat('=',1,95));

% =========================================================================
%  CROSS-MODULE PLOTS
% =========================================================================

% 1. Feasibility count per module
mod_tags_found = {};
feas_counts = [];
infeas_counts = [];
for m = 1:nMod
    tag = ['9' submodule_info{m,1} ' ' submodule_info{m,4}];
    mask = strcmp(all_rows.Module, tag);
    if ~any(mask), continue; end
    mod_tags_found{end+1} = tag; %#ok<AGROW>
    feas_counts(end+1)   = sum(strcmpi(all_rows.Status(mask),'FEASIBLE')); %#ok<AGROW>
    infeas_counts(end+1) = sum(strcmpi(all_rows.Status(mask),'INFEASIBLE')); %#ok<AGROW>
end

if ~isempty(feas_counts)
    fh = figure('Visible','off');
    bar_data = [feas_counts(:), infeas_counts(:)];
    bar(bar_data,'stacked');
    set(gca,'XTickLabel', strrep(mod_tags_found,'_',' '), ...
        'XTick',1:numel(mod_tags_found),'XTickLabelRotation',20);
    legend({'Feasible','Infeasible'},'Location','northeastoutside');
    ylabel('Number of Scenarios');
    title('Module 9: Feasibility Count per Sub-Module');
    grid on;
    saveas(fh, fullfile(outRoot,'master_feasibility_counts.png')); close(fh);
end

% 2. MinVmin vs TotalLoss scatter (feasible only)
if ~isempty(feas_rows) && height(feas_rows) >= 2
    fh = figure('Visible','off'); hold on; grid on;
    clr = lines(numel(mod_tags_found)+1);
    k_clr = 1;
    for m = 1:nMod
        tag = ['9' submodule_info{m,1} ' ' submodule_info{m,4}];
        mask = strcmp(feas_rows.Module, tag);
        if ~any(mask), continue; end
        scatter(feas_rows.TotalLoss_pu(mask), feas_rows.MinVmin_pu(mask), 60, ...
            clr(k_clr,:), 'filled', 'DisplayName', strrep(tag,'_',' '));
        k_clr = k_clr + 1;
    end
    if has_base7
        scatter(base7_loss, base7_vmin, 120, 'k', '^', 'filled', ...
            'DisplayName','Module 7 Baseline');
    end
    plot(xlim, [0.95 0.95], '--r', 'LineWidth', 1.2, 'DisplayName','Vmin limit');
    xlabel('Total 24h Feeder Loss (p.u.)');
    ylabel('Minimum Bus Voltage (p.u.)');
    title('Module 9: Pareto Map — Loss vs Voltage for All Feasible Scenarios');
    legend('Location','best'); hold off;
    saveas(fh, fullfile(outRoot,'master_pareto_loss_vs_vmin.png')); close(fh);
end

% 3. Loss reduction vs Module 7 baseline (feasible only, sorted)
if ~isempty(feas_rows) && has_base7
    loss_vals = feas_rows.TotalLoss_pu;
    loss_redux = (base7_loss - loss_vals) / base7_loss * 100;  % % reduction

    [~, sidx] = sort(loss_redux, 'descend');
    top_n = min(20, numel(sidx));
    sidx = sidx(1:top_n);

    lbl_short = cell(top_n,1);
    for i=1:top_n
        lbl = ''; if iscell(feas_rows.Label(sidx(i))), lbl=feas_rows.Label{sidx(i)}; else, lbl=feas_rows.Label(sidx(i)); end
        lbl_short{i} = lbl(1:min(end,18));
    end

    fh = figure('Visible','off');
    barh(loss_redux(sidx));
    set(gca,'YTick',1:top_n,'YTickLabel',lbl_short);
    xlabel('Loss Reduction vs Module 7 Baseline (%)');
    title(sprintf('Module 9: Top %d Scenarios by Loss Reduction', top_n));
    grid on; xlim([0, max(max(loss_redux(sidx))*1.15, 5)]);
    saveas(fh, fullfile(outRoot,'master_loss_reduction.png')); close(fh);
end

fprintf('\n=== Master comparison complete. Outputs: %s ===\n', outRoot);
fprintf('  master_comparison.csv\n');
fprintf('  master_feasibility_counts.png\n');
fprintf('  master_pareto_loss_vs_vmin.png\n');
fprintf('  master_loss_reduction.png\n');


function s = fmt_v(x)
    if isnan(x) || isempty(x), s='N/A'; else, s=sprintf('%.5f',x); end
end
