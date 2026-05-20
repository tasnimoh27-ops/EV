function loads_pv = apply_stage10_pv_penetration(loads_base, pv_buses, pv_peak_pu, pv_profile, pv_scale)
%APPLY_STAGE10_PV_PENETRATION  Apply PV generation to base loads.
%
% Subtracts scaled PV from active load at specified buses.
% Net active load = base load - scaled PV.
% Allows net load to become negative (local generation > local demand).
% Reactive load unchanged.
%
% INPUTS
%   loads_base      base load struct with P24, Q24 (nb×24)
%   pv_buses        vector of PV bus indices [1×n_pv]
%   pv_peak_pu      vector of peak PV capacities in pu [1×n_pv]
%   pv_profile      24×1 normalized PV profile [0,1]
%   pv_scale        scalar multiplier to peak capacities (0 = no PV, 1 = reference)
%
% OUTPUT
%   loads_pv        struct with P24_net, Q24, pv_info

T = 24;
nb = size(loads_base.P24, 1);

assert(length(pv_buses) == length(pv_peak_pu), ...
    'pv_buses and pv_peak_pu must have same length');
assert(length(pv_profile) == T, ...
    'pv_profile must be 24×1');
assert(pv_scale >= 0, ...
    'pv_scale must be non-negative');

% Copy base loads
loads_pv = loads_base;
loads_pv.P24_net = loads_base.P24;  % will subtract PV
loads_pv.Q24_net = loads_base.Q24;  % unchanged

% Build full PV generation matrix (nb×T)
pv_gen = zeros(nb, T);
total_pv_peak = 0;

for i = 1:length(pv_buses)
    bus_idx = pv_buses(i);
    peak_pu = pv_peak_pu(i);

    assert(bus_idx >= 1 && bus_idx <= nb, ...
        'PV bus %d out of range [1,%d]', bus_idx, nb);
    assert(peak_pu >= 0, ...
        'PV peak capacity must be non-negative');

    % PV generation at this bus
    pv_gen(bus_idx, :) = pv_scale * peak_pu * pv_profile';
    total_pv_peak = total_pv_peak + peak_pu;
end

% Apply PV: net load = base load - PV
% Allow negative net load (exports active power)
loads_pv.P24_net = loads_base.P24 - pv_gen;
loads_pv.Q24_net = loads_base.Q24;  % reactive unchanged

% Store PV metadata
loads_pv.pv_buses      = pv_buses;
loads_pv.pv_peak_pu    = pv_peak_pu;
loads_pv.pv_profile    = pv_profile;
loads_pv.pv_scale      = pv_scale;
loads_pv.pv_gen_matrix = pv_gen;  % nb×T matrix of PV generation
loads_pv.total_pv_peak_pu = total_pv_peak;
loads_pv.total_pv_peak_mw = total_pv_peak * 10;  % assuming 10 MVA base

end
