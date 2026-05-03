function results = run_es_budget_sweep(topo, loads, out_dir, ops_override)
%RUN_ES_BUDGET_SWEEP  Sweep N_ES_max × rho × u_min with MISOCP.
%
% For each combination: solve feasibility-mode MISOCP, record results.
% Saves partial results after each rho group to protect against crashes.
%
% INPUTS
%   topo         topology struct
%   loads        loads struct
%   out_dir      output directory for CSV and MAT
%   ops_override optional struct to override default sweep parameters
%       .N_ES_list  default [2,4,6,8,10,12,16,20,24,28,32]
%       .rho_vals   default [0.30,0.40,0.50,0.60,0.70,0.80]
%       .umin_vals  default [0.00,0.10,0.20,0.30]
%       .time_limit default 300

if nargin < 4 || isempty(ops_override), ops_override = struct(); end

N_ES_list = getf(ops_override,'N_ES_list', [2,4,6,8,10,12,16,20,24,28,32]);
rho_vals  = getf(ops_override,'rho_vals',  [0.30,0.40,0.50,0.60,0.70,0.80]);
umin_vals = getf(ops_override,'umin_vals', [0.00,0.10,0.20,0.30]);
t_lim     = getf(ops_override,'time_limit', 300);

if ~exist(out_dir,'dir'), mkdir(out_dir); end

T     = 24;
price = ones(T,1);
price(1:6)=0.6; price(7:16)=1.0; price(17:21)=1.8; price(22:24)=0.9;

nN    = numel(N_ES_list);
nRho  = numel(rho_vals);
nUmin = numel(umin_vals);
nTotal = nN * nRho * nUmin;

fprintf('  Budget sweep: %d × %d × %d = %d cases\n', nN, nRho, nUmin, nTotal);

rows = {};
ct   = 0;

for ir = 1:nRho
    rho = rho_vals(ir);
    for iu = 1:nUmin
        u_min = umin_vals(iu);
        for iN = 1:nN
            N = N_ES_list(iN);
            ct = ct + 1;

            fprintf('  [%d/%d] rho=%.2f u_min=%.2f N=%d ...\n', ...
                ct, nTotal, rho, u_min, N);

            params.rho          = rho;
            params.u_min        = u_min;
            params.N_ES_max     = N;
            params.Vmin         = 0.95;
            params.Vmax         = 1.05;
            params.soft_voltage = true;
            params.obj_mode     = 'feasibility';
            params.price        = price;
            params.time_limit   = t_lim;

            try
                r = solve_es_budget_misocp(topo, loads, params);
            catch ME
                fprintf('    ERROR: %s\n', ME.message);
                r.feasible   = false;
                r.sol_code   = -99;
                r.sol_info   = ME.message;
                r.n_es       = NaN;
                r.es_buses   = [];
                r.Vmin_24h   = NaN;
                r.worst_bus  = NaN;
                r.total_loss = NaN;
                r.mean_curt  = NaN;
                r.max_curt   = NaN;
                r.total_sv   = NaN;
                r.max_sv     = NaN;
                r.voltage_ok = false;
                r.solve_time = NaN;
            end

            feasible_flag = double(isfield(r,'voltage_ok') && r.voltage_ok);
            rows{end+1} = {rho, u_min, N, ...
                feasible_flag, ...
                r.n_es, mat2str(r.es_buses(:)'), ...
                r.Vmin_24h, r.worst_bus, ...
                r.total_loss, r.mean_curt, r.max_curt, ...
                r.total_sv, r.max_sv, ...
                r.sol_code, r.sol_info, r.solve_time}; %#ok<AGROW>
        end

        % Save partial results after each (rho, u_min) pair
        T_partial = build_table(rows);
        writetable(T_partial, fullfile(out_dir,'table_budget_misocp_sweep_partial.csv'));
    end
end

results = build_table(rows);
writetable(results, fullfile(out_dir,'table_budget_misocp_sweep.csv'));
save(fullfile(out_dir,'budget_sweep_results.mat'),'results');
fprintf('  Budget sweep complete. Saved to %s\n', out_dir);
end

function T = build_table(rows)
T = cell2table(rows, 'VariableNames', ...
    {'rho','u_min','N_ES_max','Feasible_volt', ...
     'N_ES_selected','ES_Buses', ...
     'Vmin_pu','WorstBus', ...
     'TotalLoss_pu','MeanCurt','MaxCurt', ...
     'TotalVoltSlack','MaxVoltSlack', ...
     'SolCode','SolInfo','SolveTime_s'});
end

function v = getf(s,f,d)
if isfield(s,f) && ~isempty(s.(f)), v=s.(f); else, v=d; end
end
