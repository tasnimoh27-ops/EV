function [scenarios, loads_cell] = generate_aggregate_ev_stress_scenarios(topo, repo_root, opts)
%GENERATE_AGGREGATE_EV_STRESS_SCENARIOS  Deterministic + stochastic EV scenarios.
%
% EV charging modelled as aggregate feeder-level load stress via evening multiplier.
% No individual EV constraints.
%
% Deterministic scenarios:
%   S1: low     EV mult = 1.4
%   S2: medium  EV mult = 1.6
%   S3: high    EV mult = 1.8  (base case)
%   S4: extreme EV mult = 2.0
%
% Stochastic scenarios (optional):
%   Samples evening multiplier from Normal(1.8, 0.1) clipped to [1.4, 2.1]

if nargin < 3, opts = struct(); end
n_stoch   = getf(opts,'n_stoch',0);     % set >0 to generate stochastic
rng_seed  = getf(opts,'rng_seed',42);
out_dir   = getf(opts,'out_dir','');

% Deterministic scenarios
det_names = {'S1_low','S2_medium','S3_high','S4_extreme'};
det_mults = [1.4, 1.6, 1.8, 2.0];

n_det  = numel(det_mults);
n_scen = n_det + n_stoch;

scenarios  = struct();
loads_cell = cell(n_scen, 1);

% Build base loads (flat profile, no multiplier)
caseDir   = fullfile(repo_root, 'mp_export_case33bw');
branchCsv = fullfile(caseDir,'branch.csv');
loadsCsv  = fullfile(caseDir,'loads_base.csv');
% Load with 'system' mode — use Pbase (flat) to apply custom EV profile
loads_base = build_24h_load_profile_from_csv(loadsCsv,'system',true,false);

for is = 1:n_det
    mult_ev = det_mults(is);
    prof    = load_profile_24h(mult_ev);
    ld = loads_base;
    for t = 1:24
        ld.P24(:,t) = loads_base.Pbase * prof.mult(t);
        ld.Q24(:,t) = loads_base.Qbase * prof.mult(t);
    end
    ld.ev_multiplier = mult_ev;
    loads_cell{is}   = ld;
    scenarios.names{is}  = det_names{is};
    scenarios.mults(is)  = mult_ev;
    scenarios.type{is}   = 'deterministic';
end

% Stochastic scenarios
if n_stoch > 0
    rng(rng_seed);
    stoch_mults = randn(1,n_stoch)*0.1 + 1.8;
    stoch_mults = min(max(stoch_mults, 1.4), 2.1);
    for is = 1:n_stoch
        idx = n_det + is;
        mult_ev = stoch_mults(is);
        prof    = load_profile_24h(mult_ev);
        ld = loads_base;
        for t = 1:24
            ld.P24(:,t) = loads_base.Pbase * prof.mult(t);
            ld.Q24(:,t) = loads_base.Qbase * prof.mult(t);
        end
        ld.ev_multiplier = mult_ev;
        loads_cell{idx}  = ld;
        scenarios.names{idx} = sprintf('Stoch_%03d',is);
        scenarios.mults(idx) = mult_ev;
        scenarios.type{idx}  = 'stochastic';
    end
end

scenarios.n_det   = n_det;
scenarios.n_stoch = n_stoch;
scenarios.n_total = n_scen;

% Save
if ~isempty(out_dir)
    if ~exist(out_dir,'dir'), mkdir(out_dir); end
    save(fullfile(out_dir,'ev_stress_scenarios.mat'), 'scenarios','loads_cell');
    T_scen = table((1:n_scen)', scenarios.names(:), scenarios.mults(:), scenarios.type(:), ...
        'VariableNames',{'ScenarioID','Name','EV_Mult','Type'});
    writetable(T_scen, fullfile(out_dir,'table_ev_stress_scenarios.csv'));
    fprintf('  EV stress scenarios saved: %d det + %d stoch\n', n_det, n_stoch);
end
end

function v = getf(s,f,d)
if isfield(s,f)&&~isempty(s.(f)), v=s.(f); else, v=d; end
end
