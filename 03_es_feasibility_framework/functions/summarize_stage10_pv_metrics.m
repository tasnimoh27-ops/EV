function row = summarize_stage10_pv_metrics(case_name, case_type, pv_scale, loads, res)
%SUMMARIZE_STAGE10_PV_METRICS  Extract Stage 10 metrics into table row.
%
% INPUTS
%   case_name       string case identifier
%   case_type       string 'no_ES' or 'with_ES'
%   pv_scale        scalar PV penetration level
%   loads           load struct with PV metadata
%   res             result struct from solver
%
% OUTPUT
%   row             cell array with metrics for table

% Extract metadata
total_pv_peak_pu = loads.total_pv_peak_pu;
total_pv_peak_mw = loads.total_pv_peak_mw;

% Solver and voltage status
sol_ok  = double(isfield(res, 'solver_ok') && res.solver_ok);
volt_ok = double(isfield(res, 'voltage_ok') && res.voltage_ok);

% Extract metrics with NaN defaults
Vmin_24h = getrf(res, 'Vmin_24h', NaN);
Vmax_24h = getrf(res, 'Vmax_24h', NaN);
worst_low_bus = getrf(res, 'worst_bus_low', NaN);
worst_low_hour = getrf(res, 'worst_hour_low', NaN);
worst_high_bus = getrf(res, 'worst_bus_high', NaN);
worst_high_hour = getrf(res, 'worst_hour_high', NaN);

total_loss = getrf(res, 'total_loss', NaN);

% Count undervoltage and overvoltage violations (>1e-6)
undervoltage_count = 0;
overvoltage_count = 0;
if isfield(res, 'sv_low_val') && ~isnan(res.sv_low_val(1))
    undervoltage_count = sum(res.sv_low_val(:) > 1e-6, 'all');
end
if isfield(res, 'sv_high_val') && ~isnan(res.sv_high_val(1))
    overvoltage_count = sum(res.sv_high_val(:) > 1e-6, 'all');
end

% Reverse power flow
reverse_flow_count = getrf(res, 'reverse_flow_count', 0);
max_reverse_power = getrf(res, 'max_reverse_power', 0);

% ES-1 metrics
n_es_max = getrf(res, 'N_ES_max', 0);
n_es_used = getrf(res, 'n_es', 0);
es_buses = [];
if isfield(res, 'es_buses') && ~isempty(res.es_buses)
    es_buses = res.es_buses;
end
es_buses_str = mat2str(es_buses);

% Reactive power metrics (for ES cases)
total_Q_es_inj = getrf(res, 'total_Q_es_inj', 0);
total_Q_es_abs = getrf(res, 'total_Q_es_abs', 0);
total_Q_es_abs_val = getrf(res, 'total_Q_es_abs_val', 0);

% Solve time
solve_time = getrf(res, 'solve_time', NaN);

% Build row as cell array
row = {
    case_name, ...              1
    case_type, ...              2
    pv_scale, ...               3
    total_pv_peak_pu, ...        4
    total_pv_peak_mw, ...        5
    Vmin_24h, ...                6
    Vmax_24h, ...                7
    worst_low_bus, ...           8
    worst_low_hour, ...          9
    worst_high_bus, ...          10
    worst_high_hour, ...         11
    total_loss, ...              12
    undervoltage_count, ...      13
    overvoltage_count, ...       14
    reverse_flow_count, ...      15
    max_reverse_power, ...       16
    volt_ok, ...                 17
    n_es_max, ...                18
    n_es_used, ...               19
    es_buses_str, ...            20
    total_Q_es_inj, ...          21
    total_Q_es_abs_val, ...      22
    solve_time, ...              23
    sol_ok ...                   24
};

end

% -------------------------------------------------------------------------
%  HELPER: extract field with default
% -------------------------------------------------------------------------
function v = getrf(s, f, default)
if isfield(s, f)
    raw = s.(f);
    if isnumeric(raw) && ~isempty(raw) && ~isnan(raw(1))
        v = raw(1);
    else
        v = default;
    end
else
    v = default;
end
end
