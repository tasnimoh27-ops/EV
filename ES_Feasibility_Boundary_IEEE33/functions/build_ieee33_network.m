function [topo, loads] = build_ieee33_network(repo_root, ev_multiplier)
%BUILD_IEEE33_NETWORK  Load IEEE 33-bus topology and 24h load profile.
%
% Wraps existing repo helpers. Applies EV stress multiplier to evening hours.
%
% INPUTS
%   repo_root      path to EV Research code root (contains mp_export_case33bw/)
%   ev_multiplier  evening EV load multiplier (default 1.80)
%
% OUTPUTS
%   topo   topology struct (build_distflow_topology_from_branch_csv)
%   loads  load struct with P24, Q24 after multiplier applied  (nb×24)

if nargin < 2 || isempty(ev_multiplier), ev_multiplier = 1.80; end

caseDir   = fullfile(repo_root, 'mp_export_case33bw');
branchCsv = fullfile(caseDir, 'branch.csv');
loadsCsv  = fullfile(caseDir, 'loads_base.csv');

assert(exist(branchCsv,'file')==2, ...
    'Missing branch.csv at: %s', branchCsv);
assert(exist(loadsCsv,'file')==2, ...
    'Missing loads_base.csv at: %s', loadsCsv);

topo  = build_distflow_topology_from_branch_csv(branchCsv, 1);
loads = build_24h_load_profile_from_csv(loadsCsv, 'system', true, false);

% Apply EV stress: scale evening hours 17-21 by ev_multiplier
% Base profile already has default multipliers from the CSV loader.
% Re-apply custom evening multiplier relative to the loaded base.
prof = load_profile_24h(ev_multiplier);
nb   = topo.nb;

% Reload clean base and apply custom profile
loads_base = build_24h_load_profile_from_csv(loadsCsv, 'flat', false, false);
for t = 1:24
    loads.P24(:,t) = loads_base.P24(:,t) * prof.mult(t);
    loads.Q24(:,t) = loads_base.Q24(:,t) * prof.mult(t);
end

loads.ev_multiplier = ev_multiplier;
loads.profile_mult  = prof.mult;
end
