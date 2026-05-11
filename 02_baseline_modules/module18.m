%% run_optimized_es_placement.m
% MODULE 10 — Optimized ES Placement and Sizing (MISOCP)
%
% Research question:
%   What is the minimum ES deployment (fewest buses, smallest capacity)
%   that restores voltage feasibility under stressed loading?
%
% Decision variables:
%   z(j)      binary  — 1 if ES installed at bus j
%   rho(j)    continuous [0, rho_max]  — ES size factor (relative to S_NCL)
%   u(j,t)    continuous [u_min, 1]    — NCL service factor at ES buses
%   v(j,t)    squared voltage
%   P(k,t), Q(k,t), l(k,t)  branch flows
%
% Objective (weighted sum):
%   min  c_loss * weighted_loss
%      + c_es   * sum(z)           [installation count penalty]
%      + c_rho  * sum(rho*S_NCL)   [sizing cost]
%      + c_curt * sum_j,t (1-u)*P_NCL  [NCL adjustment cost]
%
% Constraints:
%   DistFlow SOCP (power balance, voltage drop, cone)
%   Vmin^2 <= v(j,t) <= Vmax^2
%   u(j,t) >= 1 - z(j)*(1-u_min)   [if z=0 => u=1]
%   u(j,t) <= 1
%   1-u(j,t) <= rho(j)              [ES capacity covers curtailment]
%   rho(j) <= rho_max * z(j)        [no capacity if not installed]
%   sum(z) <= N_ES_max
%
% Output:
%   results/tables/optimized_es_results.csv
%   results/tables/optimized_es_locations.csv
%   results/figures/optimized_es_voltage_profile.png
%   results/figures/optimized_es_locations.png
%
% Requirements: YALMIP + Gurobi (MISOCP)

clear; clc; close all;
addpath(genpath('./02_baseline_modules/shared'));

% =========================================================================
%  CONFIGURATION
% =========================================================================
cfg.load_multiplier = 1.0;   % stress factor applied to base loads
cfg.alpha_ncl       = 0.30;  % NCL share at each candidate bus
cfg.ncl_pf          = 1.00;  % NCL power factor (1.0 = resistive)
cfg.u_min           = 0.20;  % minimum NCL service (20%)
cfg.rho_max         = 0.80;  % maximum ES capacity factor
cfg.N_ES_max_list   = [2, 4, 6, 8, 10, 15, 32]; % budget sweep
cfg.Vmin            = 0.95;
cfg.Vmax            = 1.05;

% Objective weights (tune for sensitivity)
cfg.c_loss = 1.0;    % loss cost weight
cfg.c_es   = 0.10;   % per-ES installation penalty
cfg.c_rho  = 0.05;   % per-unit sizing cost
cfg.c_curt = 0.50;   % NCL curtailment penalty

% Gurobi time limit per solve
cfg.time_limit = 300;  % seconds

% =========================================================================
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

% Apply stress multiplier
loads.P24 = cfg.load_multiplier * loads.P24;
loads.Q24 = cfg.load_multiplier * loads.Q24;

price = ones(T,1);
price(1:6)=0.6; price(7:16)=1.0; price(17:21)=1.8; price(22:24)=0.9;

ops = sdpsettings('solver','gurobi','verbose',0, ...
    'gurobi.MIPGap', 0.01);
ops.gurobi.TimeLimit = cfg.time_limit;

outDir = './results/tables';
figDir = './results/figures';
matDir = './results/mat_files';
for d = {outDir, figDir, matDir}
    if ~exist(d{1},'dir'), mkdir(d{1}); end
end

fprintf('\n=== Module 10: Optimized ES Placement (MISOCP) ===\n');
fprintf('Load multiplier: %.2f\n', cfg.load_multiplier);
fprintf('NCL share: %.0f%%  |  NCL PF: %.2f\n', cfg.alpha_ncl*100, cfg.ncl_pf);

% =========================================================================
%  LOAD DECOMPOSITION
% =========================================================================
all_buses  = setdiff(1:nb, root);
cl_ncl     = split_cl_ncl_load(loads, cfg.alpha_ncl, all_buses, cfg.ncl_pf);

P_CL   = cl_ncl.P_CL;
Q_CL   = cl_ncl.Q_CL;
P_NCL  = cl_ncl.P_NCL;
Q_NCL  = cl_ncl.Q_NCL;

% S_NCL per bus (mean across 24h, used for sizing normalisation)
S_NCL = sqrt(mean(P_NCL,2).^2 + mean(Q_NCL,2).^2);  % nb x 1

% =========================================================================
%  TOPOLOGY HELPERS
% =========================================================================
nl   = topo.nl_tree;
from = topo.from(:);
to   = topo.to(:);
R    = topo.R(:);
X    = topo.X(:);

line_of_child = zeros(nb,1);
outLines      = cell(nb,1);
for k = 1:nl
    line_of_child(to(k)) = k;
    outLines{from(k)}(end+1) = k;
end

% =========================================================================
%  BUDGET SWEEP
% =========================================================================
nBudget = numel(cfg.N_ES_max_list);
results = struct();

row_Budget    = zeros(nBudget,1);
row_Feasible  = false(nBudget,1);
row_NES       = zeros(nBudget,1);
row_Vmin      = NaN(nBudget,1);
row_Loss      = NaN(nBudget,1);
row_TotRho    = NaN(nBudget,1);
row_MeanCurt  = NaN(nBudget,1);
row_SolCode   = zeros(nBudget,1);
row_SelectedBuses = cell(nBudget,1);

for bi = 1:nBudget
    N_max = cfg.N_ES_max_list(bi);
    fprintf('\n  Budget N_ES_max = %d ...\n', N_max);

    % ===========================================================
    %  YALMIP VARIABLES
    % ===========================================================
    v   = sdpvar(nb, T, 'full');
    Pij = sdpvar(nl, T, 'full');
    Qij = sdpvar(nl, T, 'full');
    ell = sdpvar(nl, T, 'full');
    u   = sdpvar(nb, T, 'full');
    z   = binvar(nb, 1);          % binary placement
    rho = sdpvar(nb, 1);          % ES size factor

    % ===========================================================
    %  CONSTRAINTS
    % ===========================================================
    Con = [];

    % Voltage bounds
    Con = [Con, v >= cfg.Vmin^2, v <= cfg.Vmax^2, ell >= 0];
    Con = [Con, v(root,:) == 1.0];

    % Slack bus has no ES
    Con = [Con, z(root) == 0, rho(root) == 0];

    % rho bounds: only if ES installed
    Con = [Con, rho >= 0, rho <= cfg.rho_max * z];

    % Budget constraint
    Con = [Con, sum(z) <= N_max];

    % u bounds with ES linking constraint:
    %   u(j,t) >= 1 - z(j)*(1-u_min)
    %   u(j,t) <= 1
    %   1 - u(j,t) <= rho(j)  [capacity covers curtailment]
    for j = 1:nb
        if j == root
            Con = [Con, u(j,:) == 1];
            continue
        end
        for t = 1:T
            % If z(j)=0 => u >= 1, combined with u <= 1 => u = 1
            % If z(j)=1 => u >= u_min
            Con = [Con, u(j,t) >= 1 - z(j)*(1 - cfg.u_min)];
            Con = [Con, u(j,t) <= 1];
            % Capacity: curtailment cannot exceed rho(j)
            Con = [Con, 1 - u(j,t) <= rho(j)];
        end
    end

    % DistFlow equations
    for t = 1:T
        for j = 1:nb
            if j == root, continue; end
            kpar = line_of_child(j);
            i    = from(kpar);
            ch   = outLines{j};

            % Effective demand
            Peff = P_CL(j,t) + u(j,t)*P_NCL(j,t);
            Qeff = Q_CL(j,t) + u(j,t)*Q_NCL(j,t);

            if isempty(ch)
                sumP = 0; sumQ = 0;
            else
                sumP = sum(Pij(ch,t));
                sumQ = sum(Qij(ch,t));
            end

            Con = [Con, ...
                Pij(kpar,t) == Peff + sumP + R(kpar)*ell(kpar,t), ...
                Qij(kpar,t) == Qeff + sumQ + X(kpar)*ell(kpar,t)];

            Con = [Con, ...
                v(j,t) == v(i,t) ...
                    - 2*(R(kpar)*Pij(kpar,t) + X(kpar)*Qij(kpar,t)) ...
                    + (R(kpar)^2 + X(kpar)^2)*ell(kpar,t)];

            Con = [Con, cone([2*Pij(kpar,t); 2*Qij(kpar,t); ell(kpar,t)-v(i,t)], ...
                              ell(kpar,t)+v(i,t))];
        end
    end

    % ===========================================================
    %  OBJECTIVE
    % ===========================================================
    loss_cost = 0;
    for t = 1:T
        loss_cost = loss_cost + price(t) * sum(R .* ell(:,t));
    end

    es_count_cost = cfg.c_es * sum(z);

    sizing_cost = cfg.c_rho * sum(rho .* S_NCL);

    curt_cost = 0;
    for j = all_buses
        for t = 1:T
            curt_cost = curt_cost + cfg.c_curt*(1-u(j,t))*P_NCL(j,t);
        end
    end

    Obj = cfg.c_loss*loss_cost + es_count_cost + sizing_cost + curt_cost;

    % ===========================================================
    %  SOLVE
    % ===========================================================
    sol = optimize(Con, Obj, ops);

    row_Budget(bi)   = N_max;
    row_SolCode(bi)  = sol.problem;
    feasible         = (sol.problem == 0);
    row_Feasible(bi) = feasible;

    if feasible
        v_val   = value(v);
        u_val   = value(u);
        ell_val = value(ell);
        z_val   = round(value(z));
        rho_val = value(rho);

        Vmin_h  = min(v_val(:)).^0.5;  % sqrt because v = V^2
        % Properly compute: Vmin = min over all buses and hours of sqrt(v)
        V_mag = sqrt(max(v_val, 0));
        Vmin_h = min(V_mag(:));

        tot_loss = sum(sum(R .* ell_val));
        sel_buses = find(z_val > 0.5)';

        curt_vals = [];
        for j = sel_buses
            curt_vals(end+1) = mean(1 - u_val(j,:)); %#ok<AGROW>
        end

        row_Vmin(bi)     = Vmin_h;
        row_Loss(bi)     = tot_loss;
        row_NES(bi)      = sum(z_val);
        row_TotRho(bi)   = sum(rho_val);
        row_MeanCurt(bi) = mean(curt_vals);
        row_SelectedBuses{bi} = sel_buses;

        fprintf('    FEASIBLE  NES=%d  Vmin=%.4f  Loss=%.5f  SelBuses=%s\n', ...
            sum(z_val), Vmin_h, tot_loss, mat2str(sel_buses));

        % Save results struct for this budget
        results(bi).z_val    = z_val;
        results(bi).rho_val  = rho_val;
        results(bi).u_val    = u_val;
        results(bi).V_val    = V_mag;
        results(bi).N_max    = N_max;

    else
        fprintf('    INFEASIBLE (sol.problem=%d)\n', sol.problem);
        row_SelectedBuses{bi} = [];
    end
end

% =========================================================================
%  SAVE RESULTS
% =========================================================================
% Main table
sel_str = cellfun(@mat2str, row_SelectedBuses, 'UniformOutput', false);
T_out = table(row_Budget, row_Feasible, row_NES, row_Vmin, row_Loss, ...
              row_TotRho, row_MeanCurt, row_SolCode, sel_str, ...
    'VariableNames', {'N_ES_max','Feasible','N_ES_used','Vmin_pu', ...
                      'TotalLoss_pu','SumRho','MeanCurtailment', ...
                      'SolCode','SelectedBuses'});
writetable(T_out, fullfile(outDir, 'optimized_es_results.csv'));
fprintf('\nSaved: results/tables/optimized_es_results.csv\n');

% Save mat
save(fullfile(matDir,'optimized_es_results.mat'), 'results', 'cfg', 'T_out');

% =========================================================================
%  FIGURES
% =========================================================================
% Vmin vs budget
fig1 = figure('Visible','off');
bar(row_Budget, row_Vmin, 'FaceColor',[0.2 0.6 0.4]);
hold on;
yline(0.95,'r--','LineWidth',1.5,'Label','V_{min}=0.95 pu');
hold off;
xlabel('ES Budget (N_{ES,max})'); ylabel('Minimum Voltage (p.u.)');
title('Optimized ES: Minimum Voltage vs Budget');
grid on;
saveas(fig1, fullfile(figDir,'optimized_vmin_vs_budget.png'));
close(fig1);

% Selected ES buses for each budget (first feasible case)
feas_idx = find(row_Feasible, 1);
if ~isempty(feas_idx)
    fig2 = figure('Visible','off');
    sel = row_SelectedBuses{feas_idx};
    bar_data = zeros(nb,1);
    bar_data(sel) = 1;
    bar(1:nb, bar_data, 'FaceColor',[0.8 0.3 0.1]);
    xlabel('Bus Index'); ylabel('ES Installed (1=yes)');
    title(sprintf('Optimized ES Locations (Budget=%d)', cfg.N_ES_max_list(feas_idx)));
    grid on;
    saveas(fig2, fullfile(figDir,'optimized_es_locations.png'));
    close(fig2);

    % Voltage profile for first feasible budget
    V_opt = results(feas_idx).V_val(:, 20);  % peak hour
    fig3 = figure('Visible','off');
    bar(1:nb, V_opt, 'FaceColor',[0.2 0.5 0.8]);
    hold on;
    yline(0.95,'r--','LineWidth',1.5,'Label','V_{min}=0.95 pu');
    % Mark ES buses
    scatter(sel, V_opt(sel), 80, 'r', 'filled', 'DisplayName','ES bus');
    hold off;
    xlabel('Bus Index'); ylabel('Voltage (p.u.)');
    title(sprintf('Optimized ES Voltage Profile — Budget=%d, Peak Hour', ...
        cfg.N_ES_max_list(feas_idx)));
    legend; grid on; ylim([0.88 1.05]);
    saveas(fig3, fullfile(figDir,'optimized_es_voltage_profile.png'));
    close(fig3);
end

fprintf('\nModule 10 complete.\n');
