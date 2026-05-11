function final_table = compare_final_ieee33_cases(topo, loads, out_dir, ops)
%COMPARE_FINAL_IEEE33_CASES  Final comparison: C0–C5 cases.
%
% C0: No support (DistFlow)
% C1: Qg-only (SOCP)
% C2: Weak-bus ES {18,33}
% C3: VSI top-7 placement
% C4: MISOCP ES-only (budget unconstrained)
% C5: Hybrid ES + 50% Qg
%
% Every row reports three distinct feasibility fields:
%   SolverOK       — solver returned code 0 (or 4 for MISOCP)
%   VoltageFeasible — all bus voltages >= 0.95 pu at all hours
%   Feasible        — SolverOK AND VoltageFeasible (the definitive flag)
%
% Stage 1 output: table_case_baseline_corrected.csv

if nargin < 4 || isempty(ops)
    ops = sdpsettings('solver','gurobi','verbose',0);
    ops.gurobi.TimeLimit = 300;
end

T     = 24;
price = ones(T,1);
price(1:6)=0.6; price(7:16)=1.0; price(17:21)=1.8; price(22:24)=0.9;
root  = topo.root;

rho   = 0.70;
u_min = 0.20;

rows = {};

%% C0: No support (DistFlow — no solver, BFS only)
fprintf('\n  C0: No support ...\n');
r0 = run_distflow_baseline(topo, loads);
rows{end+1} = make_row('C0_NoSupport', [], 0, 0, 0, rho, u_min, r0);

%% C1: Qg-only
fprintf('  C1: Qg-only ...\n');
p_qg.Vmin=0.95; p_qg.Vmax=1.05; p_qg.price=price; p_qg.Qg_max_pu=0.10;
r1 = solve_socp_opf_qg(topo, loads, p_qg);
rows{end+1} = make_row('C1_QgOnly', [], 0, ...
    nanval(r1.total_Qg, 0), 0.10, rho, u_min, r1);

%% C2: Weak-bus ES {18,33}
fprintf('  C2: Weak-bus ES {18,33} ...\n');
r2 = solve_es_fixed_placement(topo, loads, [18,33], rho, u_min, ops, 'C2_WeakBus');
rows{end+1} = make_row('C2_WeakBus', [18,33], r2.n_es, 0, 0, rho, u_min, r2);

%% C3: VSI placement (top-7)
fprintf('  C3: VSI top-7 ...\n');
vsi     = calculate_voltage_impact_score(topo, loads, rho);
vis_top7 = vsi.rank(1:7)';
vis_top7 = sort(vis_top7(vis_top7 ~= root));
r3 = solve_es_fixed_placement(topo, loads, vis_top7, rho, u_min, ops, 'C3_VSI7');
rows{end+1} = make_row('C3_VSI7', vis_top7, r3.n_es, 0, 0, rho, u_min, r3);

%% C4: MISOCP ES-only
fprintf('  C4: MISOCP ES-only ...\n');
p4.rho=rho; p4.u_min=u_min; p4.N_ES_max=32;
p4.Vmin=0.95; p4.Vmax=1.05; p4.soft_voltage=true;
p4.obj_mode='feasibility'; p4.price=price; p4.time_limit=300;
r4 = solve_es_budget_misocp(topo, loads, p4);
if ~isfield(r4,'solver_ok'), r4.solver_ok = r4.feasible; end
rows{end+1} = make_row('C4_MISOCP_ES', r4.es_buses, r4.n_es, 0, 0, rho, u_min, r4);

%% C5: Hybrid ES + 50% Qg
fprintf('  C5: Hybrid ES + 50%% Qg ...\n');
p5 = p4; p5.Qg_limit_frac = 0.50;
r5 = solve_hybrid_es_qg_misocp(topo, loads, p5);
if ~isfield(r5,'solver_ok'), r5.solver_ok = r5.feasible; end
rows{end+1} = make_row('C5_Hybrid50_ES_Qg', r5.es_buses, r5.n_es, ...
    nanval(r5.total_Qg, 0), 0.50, rho, u_min, r5);

%% Build table
final_table = cell2table(vertcat(rows{:}), 'VariableNames', { ...
    'Case', 'ES_Buses', 'N_ES', 'TotalQg_pu', 'Qg_Frac', ...
    'rho', 'u_min', ...
    'SolverOK', 'VoltageFeasible', 'Feasible', ...
    'Vmin_pu', 'WorstBus', 'WorstHour', ...
    'TotalLoss_pu', 'TotalVoltSlack_pu', 'N_ViolBusx24h', ...
    'MeanCurt', 'MaxCurt', 'ReactiveSupport_pu'});

%% Save
if nargin >= 3 && ~isempty(out_dir)
    if ~exist(out_dir,'dir'), mkdir(out_dir); end
    fname = fullfile(out_dir, 'table_case_baseline_corrected.csv');
    writetable(final_table, fname);
    fprintf('\n  Saved: %s\n', fname);
end

%% Print summary
fprintf('\n  ===== STAGE 1 BASELINE — CORRECTED FEASIBILITY LABELS =====\n');
fprintf('  %-22s %4s %5s %5s %5s %8s %8s %8s\n', ...
    'Case','N_ES','SolOK','VoltOK','Feas','Vmin','Loss','MeanCurt');
fmt = '  %-22s %4d %5d %5d %5d %8.4f %8.5f %8.3f\n';
for i = 1:height(final_table)
    T_ = final_table;
    fprintf(fmt, T_.Case{i}, T_.N_ES(i), T_.SolverOK(i), ...
        T_.VoltageFeasible(i), T_.Feasible(i), ...
        T_.Vmin_pu(i), T_.TotalLoss_pu(i), T_.MeanCurt(i));
end
fprintf('  ============================================================\n\n');
end

% -------------------------------------------------------------------------
function row = make_row(name, buses, n_es, qg_total, qg_frac, rho, u_min, r)
% Extract solver/voltage flags — works for all solver types
sol_ok  = double(isfield(r,'solver_ok') && r.solver_ok);
volt_ok = double(isfield(r,'voltage_ok') && r.voltage_ok);
feas    = double(sol_ok && volt_ok);

if volt_ok
    Vm   = getrf(r, 'Vmin_24h',  @() min(getrf(r,'Vmin_t',@()NaN)));
    wb   = getrf(r, 'worst_bus', @() getrf(r,'VminBus_t', ...
               @()NaN, r.worst_hour));
    wh   = getrf(r, 'worst_hour', @()NaN);
    Lo   = getrf(r, 'total_loss', @()NaN);
    sv   = getrf(r, 'total_sv',   @()0);
    nv   = getrf(r, 'n_viol_24h', @()0);
    Mc   = getrf(r, 'mean_curtailment', @() getrf(r,'mean_curt',@()NaN));
    Xc   = getrf(r, 'max_curtailment',  @() getrf(r,'max_curt', @()NaN));
    Qt   = getrf(r, 'total_Qg',   @()qg_total);
else
    Vm=NaN; wb=NaN; wh=NaN; Lo=NaN; sv=NaN; nv=NaN; Mc=NaN; Xc=NaN; Qt=NaN;
end

row = {name, mat2str(buses(:)'), n_es, qg_total, qg_frac, ...
       rho, u_min, ...
       sol_ok, volt_ok, feas, ...
       Vm, wb, wh, Lo, sv, nv, Mc, Xc, Qt};
end

function v = getrf(s, f, dfun, varargin)
% Safe field getter with default function fallback
if isfield(s, f)
    raw = s.(f);
    if ~isempty(varargin)
        % index into array
        idx = varargin{1};
        if ~isnan(idx) && idx >= 1 && idx <= numel(raw)
            v = raw(idx);
        else
            v = NaN;
        end
    else
        v = raw;
    end
else
    try
        v = dfun();
    catch
        v = NaN;
    end
end
end

function v = nanval(x, default)
if isnan(x), v = default; else, v = x; end
end
