function profile = load_profile_24h(ev_multiplier)
%LOAD_PROFILE_24H  Return 24-hour load multiplier profile.
%
% Models aggregate EV charging stress as elevated evening peak.
%
%   Hours  1–6  : off-peak night   × 0.60
%   Hours  7–16 : daytime          × 1.00
%   Hours 17–21 : EV evening peak  × ev_multiplier  (default 1.80)
%   Hours 22–24 : late evening     × 0.90
%
% INPUT
%   ev_multiplier  scalar evening multiplier (default 1.80)
%
% OUTPUT
%   profile  struct with:
%     .mult         24×1 multiplier vector
%     .ev_mult      scalar used
%     .peak_hour    hour index of maximum multiplier

if nargin < 1 || isempty(ev_multiplier)
    ev_multiplier = 1.80;
end

mult = ones(24, 1);
mult(1:6)   = 0.60;
mult(7:16)  = 1.00;
mult(17:21) = ev_multiplier;
mult(22:24) = 0.90;

[~, peak_hour] = max(mult);

profile.mult      = mult;
profile.ev_mult   = ev_multiplier;
profile.peak_hour = peak_hour;
profile.hours     = (1:24)';
end
