function final_table = compare_final_ieee33_cases(topo, loads, out_dir, ops)
%COMPARE_FINAL_IEEE33_CASES  Final comparison: C0–C5 cases.
%
% C0: No support
% C1: Qg-only
% C2: Weak-bus ES {18,33}
% C3: VSI placement
% C4: MISOCP ES-only
% C5: Hybrid ES + limited Qg
%
% Uses best rho=0.70, u_min=0.20 from existing findings.

if nargin < 4 || isempty(ops)
    ops = sdpsettings('solver','gurobi','verbose',0);
    ops.gurobi.TimeLimit = 300;
end

T = 24;
price = ones(T,1); price(1:6)=0.6; price(7:16)=1.0; price(17:21)=1.8; price(22:24)=0.9;
nb   = topo.nb;
root = topo.root;

rho   = 0.70;
u_min = 0.20;

rows = {};

%% C0: No support (DistFlow)
fprintf('\n  C0: No support ...\n');
r0 = run_distflow_baseline(topo, loads);
rows{end+1} = {'C0_NoSupport', '[]', 0, 0, 0, ...
    rho, u_min, ...
    double(r0.Vmin_24h >= 0.95), r0.Vmin_24h, r0.worst_bus, ...
    r0.total_loss, 0, 0, 0, NaN, NaN};

%% C1: Qg-only
fprintf('  C1: Qg-only ...\n');
p_qg.Vmin=0.95; p_qg.Vmax=1.05; p_qg.price=price; p_qg.Qg_max_pu=0.10;
r1 = solve_socp_opf_qg(topo, loads, p_qg);
rows{end+1} = {'C1_QgOnly', '[]', 0, sum(r1.Qg_val(:),'omitnan'), 0.10, ...
    rho, u_min, ...
    double(r1.feasible), r1.Vmin_24h, ...
    r1.VminBus_t(max(1,r1.worst_hour)), r1.total_loss, 0, 0, ...
    sum(r1.Qg_val(:),'omitnan'), NaN, NaN};

%% C2: Weak-bus ES {18,33}
fprintf('  C2: Weak-bus ES {18,33} ...\n');
r2 = solve_es_fixed_placement(topo, loads, [18,33], rho, u_min, ops, 'C2_WeakBus');
rows{end+1} = make_row('C2_WeakBus', [18,33], rho, u_min, r2, 0);

%% C3: VSI placement (top-7)
fprintf('  C3: VSI top-7 ...\n');
vsi = calculate_voltage_impact_score(topo, loads, rho);
vis_top7 = vsi.rank(1:7)'; vis_top7 = sort(vis_top7(vis_top7 ~= root));
r3 = solve_es_fixed_placement(topo, loads, vis_top7, rho, u_min, ops, 'C3_VSI7');
rows{end+1} = make_row('C3_VSI7', vis_top7, rho, u_min, r3, 0);

%% C4: MISOCP ES-only
fprintf('  C4: MISOCP ES-only ...\n');
params4.rho=rho; params4.u_min=u_min; params4.N_ES_max=32;
params4.Vmin=0.95; params4.Vmax=1.05; params4.soft_voltage=true;
params4.obj_mode='feasibility'; params4.price=price; params4.time_limit=300;
r4 = solve_es_budget_misocp(topo, loads, params4);
rows{end+1} = make_row('C4_MISOCP', r4.es_buses, rho, u_min, r4, 0);

%% C5: Hybrid ES + 50% Qg
fprintf('  C5: Hybrid ES + 50%% Qg ...\n');
params5 = params4;
params5.Qg_limit_frac = 0.50;
r5 = solve_hybrid_es_qg_misocp(topo, loads, params5);
rows{end+1} = make_row('C5_Hybrid50', r5.es_buses, rho, u_min, r5, 0.50);

final_table = cell2table(rows, 'VariableNames', ...
    {'Case','ES_Buses','N_ES','TotalQg_pu','Qg_Frac', ...
     'rho','u_min','Feasible', ...
     'Vmin_pu','WorstBus','TotalLoss_pu', ...
     'MeanCurt','MaxCurt','ReactiveSupport_pu', ...
     'FeasProb','CVaR95'});

if nargin >= 3 && ~isempty(out_dir)
    if ~exist(out_dir,'dir'), mkdir(out_dir); end
    writetable(final_table, fullfile(out_dir,'table_final_case_comparison.csv'));
    fprintf('  Final comparison table saved.\n');
end

fprintf('\n  === FINAL CASE COMPARISON (rho=%.2f, u_min=%.2f) ===\n', rho, u_min);
fprintf('  %-18s %4s %8s %8s %8s %8s\n','Case','N_ES','Vmin','Loss','MeanCurt','Feasible');
for i = 1:height(final_table)
    fprintf('  %-18s %4s %8.4f %8.5f %8.3f %8.0f\n', ...
        final_table.Case{i}, num2str(final_table.N_ES(i)), ...
        final_table.Vmin_pu(i), final_table.TotalLoss_pu(i), ...
        final_table.MeanCurt(i), final_table.Feasible(i));
end
end

function row = make_row(name, buses, rho, u_min, r, qf)
if r.feasible
    if isfield(r,'Vmin_24h'), Vm=r.Vmin_24h; else, Vm=min(r.Vmin_t); end
    if isfield(r,'worst_bus'), wb=r.worst_bus;
    elseif isfield(r,'VminBus_t'), wb=r.VminBus_t(r.worst_hour); else, wb=NaN; end
    Lo=r.total_loss;
    if isfield(r,'mean_curt'), Mc=r.mean_curt; else, Mc=r.mean_curtailment; end
    if isfield(r,'max_curt'), Xc=r.max_curt;
    elseif isfield(r,'u_val')&&~isempty(buses), Xc=max(max(1-r.u_val(buses,:))); else, Xc=NaN; end
    Qg_tot=0;
    if isfield(r,'total_Qg'), Qg_tot=r.total_Qg; end
else
    Vm=NaN; wb=NaN; Lo=NaN; Mc=NaN; Xc=NaN; Qg_tot=NaN;
end
row = {name, mat2str(buses(:)'), numel(buses), Qg_tot, qf, ...
    rho, u_min, double(r.feasible), Vm, wb, Lo, Mc, Xc, Qg_tot, NaN, NaN};
end
