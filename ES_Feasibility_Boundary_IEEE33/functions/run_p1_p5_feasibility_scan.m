function results = run_p1_p5_feasibility_scan(topo, loads, out_dir, ops)
%RUN_P1_P5_FEASIBILITY_SCAN  Reproduce P1–P5 placement feasibility boundary.
%
% Sweeps 5 predefined placement sets × 7 rho values × 2 u_min values = 70 cases.
% Uses hard Vmin=0.95 constraint. Records feasible/infeasible for each case.
%
% INPUTS
%   topo     topology struct
%   loads    loads struct
%   out_dir  output directory for CSV
%   ops      YALMIP sdpsettings (optional)
%
% OUTPUT
%   results  table with one row per (placement, rho, u_min) combination

if nargin < 4 || isempty(ops)
    ops = sdpsettings('solver','gurobi','verbose',0);
    ops.gurobi.TimeLimit = 90;
end

nb   = topo.nb;
root = topo.root;
P_all = setdiff(1:nb, root);

% P3 uses VIS ranking
vis = calculate_voltage_impact_score(topo, loads, 0.30);
vis_top7 = vis.rank(1:7)';
vis_top7 = vis_top7(vis_top7 ~= root);

placements = {
    [18, 33],                                         'P1';
    [9, 18, 26, 33],                                  'P2';
    vis_top7,                                         'P3';
    [3,6,9,12,15,18,21,24,27,30,33],                  'P4';
    P_all,                                            'P5';
};
nP        = size(placements,1);
rho_vals  = [0.20, 0.30, 0.40, 0.50, 0.60, 0.70, 0.80];
umin_vals = [0.00, 0.20];
nTotal    = nP * numel(rho_vals) * numel(umin_vals);

fprintf('  P1–P5 scan: %d cases\n', nTotal);

rows = {};
ct   = 0;
for ip = 1:nP
    buses = placements{ip,1};
    pname = placements{ip,2};
    for rho = rho_vals
        for u_min = umin_vals
            ct = ct + 1;
            label = sprintf('%s_rho%.0f_umin%.0f', pname, rho*100, u_min*100);
            fprintf('  [%d/%d] %s ...\n', ct, nTotal, label);

            r = solve_es_fixed_placement(topo, loads, buses, rho, u_min, ops, label);

            if r.feasible
                Vmin_val = min(r.Vmin_t);
                loss_val = r.total_loss;
                meanC    = r.mean_curtailment;
                maxC     = max(max(1 - r.u_val(buses,:)));
                wbus     = r.VminBus_t(r.worst_hour);
            else
                Vmin_val = NaN; loss_val = NaN;
                meanC    = NaN; maxC     = NaN;
                wbus     = NaN;
            end

            rows{end+1} = {pname, mat2str(buses(:)'), numel(buses), ...
                rho, u_min, double(r.feasible), ...
                Vmin_val, wbus, loss_val, meanC, maxC, ...
                r.sol_code, r.sol_info}; %#ok<AGROW>
        end
    end
end

T_out = cell2table(vertcat(rows{:}), 'VariableNames', ...
    {'Placement','Buses','N_ES','rho','u_min','Feasible',...
     'Vmin_pu','WorstBus','TotalLoss_pu','MeanCurt','MaxCurt',...
     'SolCode','SolInfo'});

if ~isempty(out_dir)
    if ~exist(out_dir,'dir'), mkdir(out_dir); end
    fpath = fullfile(out_dir,'table_p1_p5_feasibility.csv');
    writetable(T_out, fpath);
    fprintf('  Saved: %s\n', fpath);
end

results = T_out;
end
