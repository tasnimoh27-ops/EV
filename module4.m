%% run_socp_opf_24h_yalmip_gurobi_cost.m
% module 7: 24-hour SOCP OPF using YALMIP + GUROBI
% Objective: loss and cost minimization
% sum_t price(t)*Loss(t)  +  lambda*sum_{j,t} |Qg(j,t)|
% Loss(t) = sum_lines R_ij * ell_ij(t)
% Requirements:
%   - YALMIP
%   - GUROBI
%   existing functions:
%       build_distflow_topology_from_branch_csv.m
%       build_24h_load_profile_from_csv.m

clear; clc; close all;


% Paths to exported CSVs

caseDir   = './mp_export_case33bw';            % change if needed
loadsCsv  = fullfile(caseDir, 'loads_base.csv');
branchCsv = fullfile(caseDir, 'branch.csv');  % prefer full branch.csv (BR_STATUS)

assert(exist(loadsCsv,'file')==2,  "Missing: %s", loadsCsv);
assert(exist(branchCsv,'file')==2, "Missing: %s", branchCsv);


% Build topology (radial tree)

topo = build_distflow_topology_from_branch_csv(branchCsv, 1);
nb   = topo.nb;
nl   = topo.nl_tree;
root = topo.root;

from = topo.from(:);
to   = topo.to(:);
R    = topo.R(:);
X    = topo.X(:);


% Build 24h per-unit loads from CSV

loads = build_24h_load_profile_from_csv(loadsCsv, 'system', true, false);
assert(isfield(loads,'P24') && isfield(loads,'Q24'), "loads must have P24/Q24.");

T  = 24;
Pd = loads.P24;     % nb x 24 (p.u.)
Qd = loads.Q24;     % nb x 24 (p.u.)


% OPF settings

Vslack = 1.0;
Vmin   = 0.95;
Vmax   = 1.05;

% Reactive support capability bounds (p.u.)
% Start by allowing inverter VAR at all buses except slack:
Qg_min = zeros(nb,1);
Qg_max = zeros(nb,1);
Qg_cap = 0.30;              % adjust as needed (p.u.)
Qg_min(2:end) = -Qg_cap;    % allow absorption too
Qg_max(2:end) = +Qg_cap;

% VAR only at selected buses:
% cand = [18 33]; Qg_min(:)=0; Qg_max(:)=0; Qg_min(cand)=-Qg_cap; Qg_max(cand)=+Qg_cap;

% VAR usage penalty weight (tunes "how much VAR will be allowed")
lambda = 0.01;


% Cost / price profile (hourly)

% This is a simple Time-Of-Use (TOU) style example (dimensionless or $/MWh).

price = ones(T,1);
price(1:6)   = 0.6;   % overnight off-peak
price(7:16)  = 1.0;   % shoulder/day
price(17:21) = 1.8;   % evening peak
price(22:24) = 0.9;   % late shoulder


% solver: GUROBI

ops = sdpsettings('solver','gurobi','verbose',1);


% Build YALMIP model


% Decision variables (nb x T, nl x T)
v   = sdpvar(nb, T, 'full');        % squared voltages v = V^2
Pij = sdpvar(nl, T, 'full');        % branch active flow (parent->child)
Qij = sdpvar(nl, T, 'full');        % branch reactive flow (parent->child)
ell = sdpvar(nl, T, 'full');        % squared current
Qg  = sdpvar(nb, T, 'full');        % reactive injections (control)

% Auxiliary for |Qg| (L1 penalty)
uQg = sdpvar(nb, T, 'full');

% Precompute adjacency mapping
outLines = cell(nb,1);     % outgoing lines from each bus
line_of_child = zeros(nb,1);
for k = 1:nl
    outLines{from(k)}(end+1) = k;
    line_of_child(to(k)) = k;      % line index that connects parent to child (child=to)
end

Constraints = [];

% Voltage & current bounds
Constraints = [Constraints, v >= (Vmin^2), v <= (Vmax^2)];
Constraints = [Constraints, ell >= 0];

% Slack voltage fixed
Constraints = [Constraints, v(root,:) == (Vslack^2)];

% Qg bounds and |Qg| epigraph
for t = 1:T
    Constraints = [Constraints, Qg(:,t) >= Qg_min, Qg(:,t) <= Qg_max];
    Constraints = [Constraints, uQg(:,t) >=  Qg(:,t)];
    Constraints = [Constraints, uQg(:,t) >= -Qg(:,t)];
    Constraints = [Constraints, uQg(:,t) >= 0];
end

% DistFlow constraints per hour
for t = 1:T
    for j = 1:nb
        if j == root
            continue;
        end

        kpar = line_of_child(j);   % parent->j line index
        i    = from(kpar);         % parent bus

        % Sum of outgoing flows to children of j
        childLines = outLines{j};
        if isempty(childLines)
            sumPchild = 0;
            sumQchild = 0;
        else
            sumPchild = sum(Pij(childLines, t));
            sumQchild = sum(Qij(childLines, t));
        end

        % Power balance with loss terms (R*ell, X*ell)
        Constraints = [Constraints, ...
            Pij(kpar,t) == Pd(j,t) + sumPchild + R(kpar)*ell(kpar,t)];

        Constraints = [Constraints, ...
            Qij(kpar,t) == (Qd(j,t) - Qg(j,t)) + sumQchild + X(kpar)*ell(kpar,t)];

        % Voltage drop
        Constraints = [Constraints, ...
            v(j,t) == v(i,t) ...
                   - 2*(R(kpar)*Pij(kpar,t) + X(kpar)*Qij(kpar,t)) ...
                   + (R(kpar)^2 + X(kpar)^2)*ell(kpar,t)];

        % SOCP rotated cone: P^2 + Q^2 <= ell * v_parent
        % YALMIP rotated cone form:
        % rcone(x, y, z) enforces ||z||^2 <= 2*x*y, with x>=0, y>=0
        % Set x = 0.5*ell, y = v_parent, z = [P; Q]
        Constraints = [Constraints, ...
    cone([2*Pij(kpar,t); 2*Qij(kpar,t); ell(kpar,t) - v(i,t)], ell(kpar,t) + v(i,t))];

    end
end


% Objective: COST(loss) + VAR penalty

lossCost = 0;
for t = 1:T
    lossCost = lossCost + price(t) * sum(R .* ell(:,t));   % weighted losses
end
varCost = lambda * sum(uQg(:));                             % VAR usage penalty

Objective = lossCost + varCost;


% Solve

sol = optimize(Constraints, Objective, ops);

if sol.problem ~= 0
    disp(sol.info);
    error("OPF failed. YALMIP error code: %d", sol.problem);
end


% Extract and save results

v_val   = value(v);
V_val   = sqrt(max(v_val, 0));
ell_val = value(ell);
Qg_val  = value(Qg);

loss_t = zeros(T,1);
costloss_t = zeros(T,1);
Vmin_t = zeros(T,1);
VminBus_t = zeros(T,1);

for t = 1:T
    loss_t(t)     = sum(R .* ell_val(:,t));          % physical loss (p.u.)
    costloss_t(t) = price(t) * loss_t(t);            % weighted cost
    [Vmin_t(t), VminBus_t(t)] = min(V_val(:,t));
end

[~, worstHour] = min(Vmin_t);

fprintf("\nGUROBI SOCP-OPF solved.\n");
fprintf("Worst hour by Vmin: hour %d (Vmin=%.4f at bus %d)\n", worstHour, Vmin_t(worstHour), VminBus_t(worstHour));
fprintf("Total loss over 24h (sum pu): %.6f\n", sum(loss_t));
fprintf("Total weighted loss-cost (sum): %.6f\n", sum(costloss_t));

outDir = './out_socp_opf_gurobi';
if ~exist(outDir,'dir'), mkdir(outDir); end

summary = table((1:T).', price, Vmin_t, VminBus_t, loss_t, costloss_t, ...
    'VariableNames', {'Hour','Price','Vmin_pu','VminBus','Loss_pu','LossCost'});
writetable(summary, fullfile(outDir,'opf_summary_24h_cost.csv'));

writetable(array2table(V_val,  'VariableNames', compose('h%02d',1:T)), fullfile(outDir,'V_bus_by_hour.csv'));
writetable(array2table(Qg_val, 'VariableNames', compose('h%02d',1:T)), fullfile(outDir,'Qg_bus_by_hour.csv'));

figure; plot(1:T, Vmin_t, '-o'); grid on;
xlabel('Hour'); ylabel('Minimum Voltage (p.u.)');
title('SOCP-OPF (GUROBI): Minimum Voltage vs Hour');
saveas(gcf, fullfile(outDir,'opf_min_voltage_vs_hour.png'));

figure; plot(1:T, loss_t, '-o'); grid on;
xlabel('Hour'); ylabel('Total Loss (p.u.)');
title('SOCP-OPF (GUROBI): Loss vs Hour');
saveas(gcf, fullfile(outDir,'opf_loss_vs_hour.png'));

figure; plot(1:T, costloss_t, '-o'); grid on;
xlabel('Hour'); ylabel('Weighted Loss Cost');
title('SOCP-OPF (GUROBI): Cost of Loss vs Hour');
saveas(gcf, fullfile(outDir,'opf_loss_cost_vs_hour.png'));

figure; plot(1:nb, V_val(:,worstHour), '-o'); grid on;
xlabel('Bus'); ylabel('Voltage (p.u.)');
title(sprintf('SOCP-OPF (GUROBI): Voltage Profile at Worst Hour %d', worstHour));
saveas(gcf, fullfile(outDir, sprintf('opf_voltage_profile_worst_h%02d.png', worstHour)));

fprintf("Saved outputs to: %s\n", outDir);
