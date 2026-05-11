function [topo, loads] = build_ieee33_network(repo_root, ev_multiplier)
%BUILD_IEEE33_NETWORK  Load IEEE 33-bus topology and 24h load profile.
%
% Wraps existing repo helpers. Applies EV stress multiplier to evening hours.
%
% INPUTS
%   repo_root      path to EV Research code root (contains 01_data/)
%   ev_multiplier  evening EV load multiplier (default 1.80)
%
% OUTPUTS
%   topo   topology struct (build_distflow_topology_from_branch_csv)
%   loads  load struct with P24, Q24 after multiplier applied  (nb×24)

if nargin < 2 || isempty(ev_multiplier), ev_multiplier = 1.80; end

caseDir   = fullfile(repo_root, '01_data');
branchCsv = fullfile(caseDir, 'branch.csv');
loadsCsv  = fullfile(caseDir, 'loads_base.csv');

assert(exist(branchCsv,'file')==2, ...
    'Missing branch.csv at: %s', branchCsv);
assert(exist(loadsCsv,'file')==2, ...
    'Missing loads_base.csv at: %s', loadsCsv);

topo  = build_distflow_topology_from_branch_csv(branchCsv, 1);

% Load once with 'system' mode — gives both Pbase (flat) and P24 (pre-scaled).
% Use Pbase directly so we control the full 24h profile ourselves.
loads_raw = build_24h_load_profile_from_csv(loadsCsv, 'system', true, false);

prof = load_profile_24h(ev_multiplier);
nb   = topo.nb;

% Build P24/Q24 from flat base × custom EV-stress profile
loads        = loads_raw;              % copy struct (bus, unit, mode fields)
for t = 1:24
    loads.P24(:,t) = loads_raw.Pbase * prof.mult(t);
    loads.Q24(:,t) = loads_raw.Qbase * prof.mult(t);
end

loads.ev_multiplier = ev_multiplier;
loads.profile_mult  = prof.mult;
end
