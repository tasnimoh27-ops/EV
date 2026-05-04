function results = evaluate_solution_under_ev_stress(topo, scenarios, loads_cell, solutions, out_dir, ops)
%EVALUATE_SOLUTION_UNDER_EV_STRESS  Test selected solutions over EV scenarios.
%
% solutions is a struct array with fields:
%   .name       string label
%   .es_buses   ES bus indices (empty if no ES)
%   .rho        NCL fraction
%   .u_min      min NCL service
%   .Qg_frac    reactive support fraction (0 if ES-only)
%
% For each solution × scenario: solve and record feasibility + metrics.

if nargin < 6 || isempty(ops)
    ops = sdpsettings('solver','gurobi','verbose',0);
    ops.gurobi.TimeLimit = 120;
end

T = 24;
price = ones(T,1); price(1:6)=0.6; price(7:16)=1.0; price(17:21)=1.8; price(22:24)=0.9;
n_scen = scenarios.n_total;
n_sol  = numel(solutions);

rows = {};
for is = 1:n_scen
    loads_s = loads_cell{is};
    sname   = scenarios.names{is};
    ev_mult = scenarios.mults(is);

    for isol = 1:n_sol
        sol = solutions(isol);
        fprintf('  %s × %s ...\n', sol.name, sname);

        if isempty(sol.es_buses) && sol.Qg_frac == 0
            % No-support baseline: run DistFlow
            r_base = run_distflow_baseline(topo, loads_s);
            feasible = double(r_base.Vmin_24h >= 0.95);
            rows{end+1} = {sol.name, sname, ev_mult, feasible, ...
                r_base.Vmin_24h, r_base.worst_bus, r_base.total_loss, ...
                0, 0, 0, 0}; %#ok<AGROW>
            continue
        end

        if isempty(sol.es_buses) && sol.Qg_frac > 0
            % Qg-only
            p_qg.Vmin=0.95; p_qg.Vmax=1.05; p_qg.price=price;
            p_qg.Qg_max_pu=0.10*sol.Qg_frac; p_qg.soft_voltage=false;
            r = solve_socp_opf_qg(topo, loads_s, p_qg);
            feasible = double(r.feasible);
            Vm = r.Vmin_24h; wb=r.worst_hour; Lo=r.total_loss;
            rows{end+1} = {sol.name,sname,ev_mult,feasible,Vm,wb,Lo,0,0,0,sum(r.Qg_val(:))}; %#ok<AGROW>
            continue
        end

        % ES (fixed placement) — solve with given buses at given rho/u_min
        N = numel(sol.es_buses);
        if sol.Qg_frac > 0
            params.rho=sol.rho; params.u_min=sol.u_min; params.N_ES_max=N;
            params.Qg_limit_frac=sol.Qg_frac; params.price=price;
            params.Vmin=0.95; params.Vmax=1.05;
            params.soft_voltage=false; params.obj_mode='planning';
            params.time_limit=120;
            % Fix ES buses (no budget variable needed — z fixed to 1)
            params.candidate_buses = sol.es_buses;
            r = solve_hybrid_es_qg_misocp(topo, loads_s, params);
        else
            r = solve_es_fixed_placement(topo, loads_s, sol.es_buses, ...
                sol.rho, sol.u_min, ops, [sol.name '_' sname]);
        end

        feasible = double(isfield(r,'feasible')&&r.feasible);
        if feasible
            if isfield(r,'Vmin_24h'), Vm=r.Vmin_24h; else, Vm=min(r.Vmin_t); end
            if isfield(r,'worst_bus'), wb=r.worst_bus; else, wb=NaN; end
            Lo = r.total_loss;
            if isfield(r,'mean_curt'), Mc=r.mean_curt; else, Mc=r.mean_curtailment; end
            if isfield(r,'max_curt'), Xc=r.max_curt; else, Xc=max(max(1-r.u_val)); end
            vslack = 0;
            if isfield(r,'total_sv'), vslack=r.total_sv; end
            Qg_tot = 0;
            if isfield(r,'total_Qg'), Qg_tot=r.total_Qg; end
        else
            Vm=NaN; wb=NaN; Lo=NaN; Mc=NaN; Xc=NaN; vslack=NaN; Qg_tot=NaN;
        end
        rows{end+1} = {sol.name,sname,ev_mult,feasible,Vm,wb,Lo,Mc,Xc,vslack,Qg_tot}; %#ok<AGROW>
    end
end

results = cell2table(vertcat(rows{:}),'VariableNames', ...
    {'Solution','Scenario','EV_Mult','Feasible', ...
     'Vmin_pu','WorstBus','TotalLoss_pu', ...
     'MeanCurt','MaxCurt','VoltSlack','TotalQg_pu'});

if nargin >= 5 && ~isempty(out_dir)
    if ~exist(out_dir,'dir'), mkdir(out_dir); end
    writetable(results, fullfile(out_dir,'table_ev_stress_robustness.csv'));
    fprintf('  EV stress robustness table saved.\n');
end
end
