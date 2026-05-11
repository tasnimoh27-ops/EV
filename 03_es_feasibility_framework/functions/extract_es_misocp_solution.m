function sol_struct = extract_es_misocp_solution(res, topo)
%EXTRACT_ES_MISOCP_SOLUTION  Extract key metrics from MISOCP result struct.
%
% Organises results into a clean publication-ready struct.

nb = topo.nb;
T  = 24;

sol_struct.feasible      = res.feasible;
sol_struct.voltage_ok    = isfield(res,'voltage_ok') && res.voltage_ok;
sol_struct.n_es          = res.n_es;
sol_struct.es_buses      = res.es_buses;
sol_struct.rho           = res.rho;
sol_struct.u_min         = res.u_min;
sol_struct.N_ES_max      = res.N_ES_max;
sol_struct.Vmin_24h      = res.Vmin_24h;
sol_struct.worst_hour    = res.worst_hour;
sol_struct.worst_bus     = res.worst_bus;
sol_struct.total_loss    = res.total_loss;
sol_struct.mean_curt     = res.mean_curt;
sol_struct.max_curt      = res.max_curt;
sol_struct.total_sv      = res.total_sv;
sol_struct.max_sv        = res.max_sv;
sol_struct.solve_time    = res.solve_time;
sol_struct.sol_code      = res.sol_code;

% Voltage profile at worst hour
if ~isnan(res.Vmin_24h) && isfield(res,'V_val') && ~all(isnan(res.V_val(:)))
    sol_struct.V_profile_worst = res.V_val(:, res.worst_hour);
    sol_struct.V_min_per_bus   = min(res.V_val, [], 2);
    sol_struct.n_viol_24h      = sum(min(res.V_val(2:end,:),[],2) < 0.95);
else
    sol_struct.V_profile_worst = NaN(nb,1);
    sol_struct.V_min_per_bus   = NaN(nb,1);
    sol_struct.n_viol_24h      = NaN;
end

% NCL curtailment at ES buses
if ~isempty(res.es_buses) && isfield(res,'c_val') && ~all(isnan(res.c_val(:)))
    sol_struct.curt_at_es = res.c_val(res.es_buses, :);
    sol_struct.mean_curt_per_es = mean(res.c_val(res.es_buses,:), 2);
else
    sol_struct.curt_at_es = [];
    sol_struct.mean_curt_per_es = [];
end
end
