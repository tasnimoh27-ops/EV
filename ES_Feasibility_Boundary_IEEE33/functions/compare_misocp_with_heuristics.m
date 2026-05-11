function results = compare_misocp_with_heuristics(topo, loads, ranking, out_dir, ops)
%COMPARE_MISOCP_WITH_HEURISTICS  MISOCP vs heuristic placement comparison.
%
% For selected (rho, u_min) cases, compares MISOCP optimal placement
% against weak-bus, end-feeder, VSI top-k, combined-score top-k, and P1-P5.
% Uses the same N_ES_max as the MISOCP solution for fair heuristic comparison.

if nargin < 5 || isempty(ops)
    ops = sdpsettings('solver','gurobi','verbose',0);
    ops.gurobi.TimeLimit = 300;
end

test_cases = {0.50,0.00; 0.60,0.00; 0.70,0.20; 0.80,0.20};
nb   = topo.nb;
root = topo.root;
P_all = setdiff(1:nb, root);
T     = 24;
price = ones(T,1); price(1:6)=0.6; price(7:16)=1.0; price(17:21)=1.8; price(22:24)=0.9;

rows = {};
for itc = 1:size(test_cases,1)
    rho   = test_cases{itc,1};
    u_min = test_cases{itc,2};

    % 1. MISOCP solution
    params.rho=rho; params.u_min=u_min; params.N_ES_max=32;
    params.Vmin=0.95; params.Vmax=1.05; params.soft_voltage=true;
    params.obj_mode='feasibility'; params.price=price;
    params.time_limit=300;
    r_miso = solve_es_budget_misocp(topo, loads, params);
    N_opt  = r_miso.n_es;
    if isnan(N_opt), N_opt = 32; end

    rows{end+1} = add_row('MISOCP', r_miso.es_buses, N_opt, rho, u_min, r_miso);

    % 2-6. Heuristics at N_opt buses
    heuristics = {'weakest_bus','end_feeder','VSI','combined','P5'};
    rank_lists  = {ranking.rank_weak, ranking.rank_endfeed, ...
                   ranking.rank_vsi,  ranking.rank_combined, P_all};
    for ih = 1:numel(heuristics)
        rk = rank_lists{ih}(:)';
        if N_opt <= numel(rk)
            buses_h = sort(rk(1:N_opt));
        else
            buses_h = sort(rk);
        end
        label = sprintf('%s_r%.0f_u%.0f', heuristics{ih}, rho*100, u_min*100);
        r_h = solve_es_fixed_placement(topo, loads, buses_h, rho, u_min, ops, label);
        rows{end+1} = add_row(heuristics{ih}, buses_h, numel(buses_h), rho, u_min, r_h);
    end

    % P1 and P2 for reference — use indexed loop, NOT for-over-cell-matrix
    ref_buses = {[18,33],       'P1'; ...
                 [9,18,26,33],  'P2'};
    for ip = 1:size(ref_buses, 1)
        buses_p = ref_buses{ip, 1};
        pname   = ref_buses{ip, 2};
        label   = sprintf('%s_r%.0f_u%.0f', pname, rho*100, u_min*100);
        r_p = solve_es_fixed_placement(topo, loads, buses_p, rho, u_min, ops, label);
        rows{end+1} = add_row(pname, buses_p, numel(buses_p), rho, u_min, r_p);
    end
end

results = cell2table(vertcat(rows{:}), 'VariableNames', ...
    {'Method','Buses','N_ES','rho','u_min','Feasible', ...
     'Vmin_pu','WorstBus','TotalLoss_pu','MeanCurt','MaxCurt','SolCode'});

if nargin >= 4 && ~isempty(out_dir)
    if ~exist(out_dir,'dir'), mkdir(out_dir); end
    writetable(results, fullfile(out_dir,'table_misocp_vs_heuristics.csv'));
    fprintf('  MISOCP vs heuristics comparison saved.\n');
end
end

function row = add_row(method, buses, N, rho, u_min, r)
if r.feasible
    if isfield(r,'Vmin_24h'), Vm=r.Vmin_24h; else, Vm=min(r.Vmin_t); end
    if isfield(r,'worst_bus'), wb=r.worst_bus;
    elseif isfield(r,'VminBus_t'), wb=r.VminBus_t(r.worst_hour); else, wb=NaN; end
    Lo = r.total_loss;
    if isfield(r,'mean_curt'), Mc=r.mean_curt; else, Mc=r.mean_curtailment; end
    if isfield(r,'max_curt'), Xc=r.max_curt;
    elseif isfield(r,'u_val'), Xc=max(max(1-r.u_val));  else, Xc=NaN; end
else
    Vm=NaN; wb=NaN; Lo=NaN; Mc=NaN; Xc=NaN;
end
row = {method, mat2str(buses(:)'), N, rho, u_min, ...
    double(r.feasible), Vm, wb, Lo, Mc, Xc, r.sol_code};
end
