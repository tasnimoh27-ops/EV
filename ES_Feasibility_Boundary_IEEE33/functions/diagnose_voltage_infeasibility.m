function diag = diagnose_voltage_infeasibility(topo, loads, sweep_results, out_dir)
%DIAGNOSE_VOLTAGE_INFEASIBILITY  Analyse infeasible MISOCP cases.
%
% For each infeasible case: reports total voltage slack, violating buses,
% estimated additional flexibility required to reach feasibility.
%
% INPUTS
%   topo          topology struct
%   loads         loads struct
%   sweep_results table from run_es_budget_sweep
%   out_dir       output directory

infeas_mask = sweep_results.Feasible_volt == 0;
if ~any(infeas_mask)
    fprintf('  No infeasible cases found.\n');
    diag = table();
    return
end

sub = sweep_results(infeas_mask, :);
nb  = topo.nb;
T   = 24;
Vmin_lim = 0.95;

price = ones(T,1);
price(1:6)=0.6; price(7:16)=1.0; price(17:21)=1.8; price(22:24)=0.9;

rows = {};
for i = 1:height(sub)
    rho   = sub.rho(i);
    u_min = sub.u_min(i);
    N     = sub.N_ES_max(i);

    % Re-solve with soft voltage to get voltage slack magnitude
    params.rho          = rho;
    params.u_min        = u_min;
    params.N_ES_max     = N;
    params.Vmin         = Vmin_lim;
    params.Vmax         = 1.05;
    params.soft_voltage = true;
    params.obj_mode     = 'feasibility';
    params.price        = price;
    params.time_limit   = 120;

    try
        r = solve_es_budget_misocp(topo, loads, params);
        if ~isnan(r.total_sv)
            total_sv  = r.total_sv;
            max_sv    = r.max_sv;
            Vmin_soft = r.Vmin_24h;
            worst_bus = r.worst_bus;
            % Voltage deficit = sqrt(V^2 + sv) - sqrt(V^2) ≈ sv / (2*Vmin)
            volt_deficit = max_sv / (2 * max(Vmin_soft, 0.5));
        else
            total_sv=NaN; max_sv=NaN; Vmin_soft=NaN; worst_bus=NaN; volt_deficit=NaN;
        end
    catch
        total_sv=NaN; max_sv=NaN; Vmin_soft=NaN; worst_bus=NaN; volt_deficit=NaN;
    end

    % Estimate extra rho needed (heuristic: scale by voltage deficit ratio)
    if ~isnan(volt_deficit) && volt_deficit > 0
        rho_extra_est = min(1-rho, volt_deficit / (Vmin_lim * rho + 1e-8));
    else
        rho_extra_est = NaN;
    end

    rows{end+1} = {rho, u_min, N, total_sv, max_sv, ...
        Vmin_soft, worst_bus, volt_deficit, rho_extra_est}; %#ok<AGROW>
end

diag = cell2table(vertcat(rows{:}), 'VariableNames', ...
    {'rho','u_min','N_ES_max','TotalVoltSlack','MaxVoltSlack', ...
     'Vmin_soft','WorstBus','VoltDeficit_pu','RhoExtra_est'});

if nargin >= 4 && ~isempty(out_dir)
    if ~exist(out_dir,'dir'), mkdir(out_dir); end
    writetable(diag, fullfile(out_dir,'table_infeasibility_diagnostics.csv'));
    fprintf('  Infeasibility diagnostics saved: %d cases\n', height(diag));
end
end
