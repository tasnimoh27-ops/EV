function res = solve_es_fixed_placement(topo, loads, es_buses, rho, u_min, ops, label)
%SOLVE_ES_FIXED_PLACEMENT  Solve ES SOCP OPF for given fixed placement.
%
% Thin wrapper around existing solve_es_socp_opf_case with convenience API.
%
% INPUTS
%   topo      topology struct
%   loads     loads struct (P24, Q24)
%   es_buses  row vector of ES bus indices (1-indexed)
%   rho       NCL fraction scalar in [0,1]
%   u_min     minimum NCL service level in [0,1]
%   ops       YALMIP sdpsettings (optional)
%   label     string label for printing (optional)
%
% OUTPUT
%   res   result struct from solve_es_socp_opf_case

if nargin < 6 || isempty(ops)
    ops = sdpsettings('solver','gurobi','verbose',0);
    ops.gurobi.TimeLimit = 300;
end
if nargin < 7 || isempty(label)
    label = sprintf('ES-fixed-rho%.0f-umin%.0f', rho*100, u_min*100);
end

T    = 24;
price = ones(T,1);
price(1:6)=0.6; price(7:16)=1.0; price(17:21)=1.8; price(22:24)=0.9;

params.name        = strrep(label,' ','_');
params.label       = label;
params.es_buses    = es_buses(:)';
params.rho_val     = rho;
params.u_min_val   = u_min;
params.lambda_u    = 1.0;
params.Vmin        = 0.95;
params.Vmax        = 1.05;
params.soft_voltage = false;
params.lambda_sv   = 1e4;
params.price       = price;
params.out_dir     = '';   % no file output — caller handles saving

res = solve_es_socp_opf_case(params, topo, loads, ops);

% Attach placement metadata
res.es_buses   = es_buses(:)';
res.n_es       = numel(es_buses);
res.rho        = rho;
res.u_min      = u_min;

% Unified feasibility labels (solve_es_socp_opf_case uses hard Vmin constraint)
res.solver_ok = (res.feasible);   % res.feasible = (sol.problem==0) from inner solver
if res.solver_ok && isfield(res,'Vmin_t')
    Vmin_lim = params.Vmin;
    res.voltage_ok = (min(res.Vmin_t) >= Vmin_lim - 1e-6);
    if isfield(res,'V_val')
        viol_mask = (res.V_val < Vmin_lim);
        viol_mask(topo.root,:) = false;
        res.total_sv   = sum(sum(max(0, Vmin_lim - res.V_val)));
        res.n_viol_24h = sum(sum(viol_mask));
    else
        res.total_sv   = 0;
        res.n_viol_24h = 0;
    end
else
    res.voltage_ok = false;
    res.total_sv   = NaN;
    res.n_viol_24h = NaN;
end
res.feasible = res.solver_ok && res.voltage_ok;
end
