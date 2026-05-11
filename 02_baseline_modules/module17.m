%% run_greedy_es_placement.m
% MODULE 9 — Greedy ES Placement Algorithm
%
% Iteratively adds ES at the bus that gives the largest Vmin improvement
% until all voltages are feasible or the budget is exhausted.
%
% Algorithm:
%   1. Start: no ES, run soft-constrained OPF, record Vmin.
%   2. For each candidate bus j not yet selected:
%        Temporarily add j to ES set, solve OPF, record Vmin.
%   3. Select bus with highest Vmin improvement.
%   4. Add to permanent ES set, repeat until feasible or N_max reached.
%
% Output:
%   results/tables/greedy_es_selection_steps.csv
%   results/figures/greedy_min_voltage_progress.png
%   results/figures/greedy_selected_buses.png
%
% Requirements: YALMIP + Gurobi

clear; clc; close all;
addpath(genpath('./02_baseline_modules/shared'));

% =========================================================================
%  CONFIGURATION
% =========================================================================
cfg.load_multiplier = 1.0;
cfg.alpha_ncl       = 0.30;
cfg.ncl_pf          = 1.00;
cfg.u_min           = 0.20;
cfg.rho_val         = 0.60;   % fixed ES capacity for greedy (not optimized)
cfg.Vmin            = 0.95;
cfg.Vmax            = 1.05;
cfg.N_max_greedy    = 20;     % stop after this many ES units
cfg.lambda_u        = 2.0;

caseDir   = './01_data';
branchCsv = fullfile(caseDir, 'branch.csv');
loadsCsv  = fullfile(caseDir, 'loads_base.csv');
assert(exist(branchCsv,'file')==2, 'Missing: %s', branchCsv);
assert(exist(loadsCsv, 'file')==2, 'Missing: %s', loadsCsv);

topo  = build_distflow_topology_from_branch_csv(branchCsv, 1);
loads = build_24h_load_profile_from_csv(loadsCsv, 'system', true, false);
nb    = topo.nb;
T     = 24;
root  = topo.root;

loads.P24 = cfg.load_multiplier * loads.P24;
loads.Q24 = cfg.load_multiplier * loads.Q24;

price = ones(T,1);
price(1:6)=0.6; price(7:16)=1.0; price(17:21)=1.8; price(22:24)=0.9;

ops = sdpsettings('solver','gurobi','verbose',0);
ops.gurobi.TimeLimit = 120;

outDir = './results/tables';
figDir = './results/figures';
if ~exist(outDir,'dir'), mkdir(outDir); end
if ~exist(figDir,'dir'), mkdir(figDir); end

fprintf('\n=== Module 9: Greedy ES Placement ===\n');

% Candidate buses (all non-slack)
candidates = setdiff(1:nb, root);

selected_buses = [];
step_bus   = zeros(cfg.N_max_greedy, 1);
step_Vmin  = zeros(cfg.N_max_greedy, 1);
step_Loss  = zeros(cfg.N_max_greedy, 1);
step_Feas  = false(cfg.N_max_greedy, 1);
n_steps    = 0;

% ---- Step 0: no ES ----
params0.name        = 'greedy_step0';
params0.label       = 'No ES';
params0.es_buses    = [];
params0.rho_val     = 0;
params0.u_min_val   = 1;
params0.lambda_u    = 0;
params0.Vmin        = cfg.Vmin;
params0.Vmax        = cfg.Vmax;
params0.soft_voltage = true;
params0.lambda_sv   = 1000;
params0.price       = price;
params0.out_dir     = '';

res0 = solve_es_socp_opf_case(params0, topo, loads, ops);
current_Vmin = min(res0.Vmin_t);
fprintf('  Step 0 (no ES): Vmin=%.4f\n', current_Vmin);

% ---- Greedy iterations ----
for step = 1:cfg.N_max_greedy
    best_Vmin = current_Vmin;
    best_bus  = -1;
    best_loss = NaN;

    remaining = setdiff(candidates, selected_buses);
    if isempty(remaining), break; end

    for j = remaining
        trial_buses = [selected_buses, j];

        p.name        = sprintf('greedy_trial_bus%d', j);
        p.label       = sprintf('Trial bus %d', j);
        p.es_buses    = trial_buses;
        p.rho_val     = cfg.rho_val;
        p.u_min_val   = cfg.u_min;
        p.lambda_u    = cfg.lambda_u;
        p.Vmin        = cfg.Vmin;
        p.Vmax        = cfg.Vmax;
        p.soft_voltage = true;
        p.lambda_sv   = 1000;
        p.price       = price;
        p.out_dir     = '';

        r = solve_es_socp_opf_case(p, topo, loads, ops);
        trial_Vmin = min(r.Vmin_t);
        if trial_Vmin > best_Vmin
            best_Vmin = trial_Vmin;
            best_bus  = j;
            best_loss = r.total_loss;
        end
    end

    if best_bus < 0
        fprintf('  Step %d: No improvement possible. Stopping.\n', step);
        break
    end

    selected_buses(end+1) = best_bus; %#ok<AGROW>
    current_Vmin = best_Vmin;
    n_steps = step;

    step_bus(step)  = best_bus;
    step_Vmin(step) = best_Vmin;
    step_Loss(step) = best_loss;
    step_Feas(step) = (best_Vmin >= cfg.Vmin - 1e-4);

    fprintf('  Step %d: add bus %2d  =>  Vmin=%.4f  Feasible=%d\n', ...
        step, best_bus, best_Vmin, step_Feas(step));

    if step_Feas(step)
        fprintf('  Feasibility restored at step %d with %d ES units.\n', ...
            step, numel(selected_buses));
        break
    end
end

% Save table
Step      = (1:n_steps)';
SelectedBus = step_bus(1:n_steps);
Vmin_pu     = step_Vmin(1:n_steps);
TotalLoss   = step_Loss(1:n_steps);
Feasible    = step_Feas(1:n_steps);
T_out = table(Step, SelectedBus, Vmin_pu, TotalLoss, Feasible);
writetable(T_out, fullfile(outDir,'greedy_es_selection_steps.csv'));
fprintf('Saved: results/tables/greedy_es_selection_steps.csv\n');

% Figure 1: Vmin progress
fig1 = figure('Visible','off');
plot(1:n_steps, step_Vmin(1:n_steps), '-o','LineWidth',1.5,'MarkerSize',7);
hold on;
yline(0.95,'r--','LineWidth',1.5,'Label','V_{min}=0.95 pu');
hold off;
xlabel('Greedy Step (# ES units added)'); ylabel('Minimum Voltage (p.u.)');
title('Greedy ES Placement: Vmin Progress');
grid on;
saveas(fig1, fullfile(figDir,'greedy_min_voltage_progress.png'));
close(fig1);

% Figure 2: selected bus locations
fig2 = figure('Visible','off');
ind = zeros(nb,1); ind(selected_buses(1:n_steps)) = 1;
bar(1:nb, ind,'FaceColor',[0.8 0.3 0.1]);
xlabel('Bus Index'); ylabel('ES Selected (1=yes)');
title(sprintf('Greedy ES Selection — %d buses selected',n_steps));
grid on;
saveas(fig2, fullfile(figDir,'greedy_selected_buses.png'));
close(fig2);

fprintf('\nModule 9 (Greedy) complete. Final selection: %s\n', mat2str(selected_buses));
