function pv_prof = build_stage10_pv_profile()
%BUILD_STAGE10_PV_PROFILE  Generate 24-hour PV generation profile.
%
% Models solar generation as normalized Hou-style profile:
%   pv_profile(t) = max(0, sin(π*(t - 6)/12))^1.5
%
% Zero at night (t<6 or t>18), peak at midday (t=12).
%
% OUTPUT
%   pv_prof  struct with:
%     .profile_24h    24×1 normalized PV profile [0,1]
%     .hours          24×1 hour vector [1:24]'

T = 24;
hours = (1:T)';

% Hou-style normalized solar profile
% sin(π*(t - 6)/12) = sin(0) at t=6, sin(π/2) at t=12, sin(π) at t=18
% Raising to power 1.5 sharpens the peak

profile = zeros(T, 1);
for t = 1:T
    arg = pi * (t - 6) / 12;
    if arg >= 0 && arg <= pi
        profile(t) = max(0, sin(arg))^1.5;
    end
end

pv_prof.profile_24h = profile;
pv_prof.hours       = hours;

% Sanity check: profile should be ~0 at night
assert(profile(1) < 0.01 && profile(24) < 0.01, ...
    'PV profile not zero at night boundaries');
% Peak should be near hour 12
[~, pk_hour] = max(profile);
assert(pk_hour >= 11 && pk_hour <= 13, ...
    'PV profile peak not near hour 12');

end
