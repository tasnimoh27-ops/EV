function loads_out = build_load_profile_24h(loads_base, ev_multiplier)
%BUILD_LOAD_PROFILE_24H  Apply 24h EV-stress load profile to base loads.
%
% INPUTS
%   loads_base    base loads struct (P24, Q24, nb×24) — flat or no multiplier
%   ev_multiplier evening EV multiplier (default 1.80)
%
% OUTPUT
%   loads_out  struct with scaled P24, Q24

if nargin < 2, ev_multiplier = 1.80; end

prof = load_profile_24h(ev_multiplier);
nb   = size(loads_base.P24, 1);

loads_out = loads_base;
for t = 1:24
    loads_out.P24(:,t) = loads_base.P24(:,t) * prof.mult(t);
    loads_out.Q24(:,t) = loads_base.Q24(:,t) * prof.mult(t);
end
loads_out.ev_multiplier = ev_multiplier;
loads_out.profile_mult  = prof.mult;
end
