function cl_ncl = split_cl_ncl_load(loads, alpha_ncl, es_buses, ncl_pf)
%SPLIT_CL_NCL_LOAD  Split load at ES candidate buses into CL and NCL parts.
%
% INPUTS
%   loads      struct from build_24h_load_profile_from_csv (fields P24, Q24)
%   alpha_ncl  scalar NCL share in [0,1]  e.g. 0.30 for 30% NCL
%   es_buses   vector of bus indices where ES is considered (1-indexed)
%   ncl_pf     NCL power factor, scalar in (0,1] or 1.0 for pure resistive
%              If ncl_pf < 1: Q_NCL = P_NCL * tan(acos(ncl_pf))  (lagging)
%
% OUTPUTS
%   cl_ncl     struct with fields:
%     .P_CL    nb x 24  critical load active power
%     .Q_CL    nb x 24  critical load reactive power
%     .P_NCL   nb x 24  non-critical load active power (at ES buses only)
%     .Q_NCL   nb x 24  non-critical load reactive power (at ES buses only)
%     .alpha   scalar NCL share used
%     .ncl_pf  NCL power factor used
%     .es_buses bus indices with ES

if nargin < 4 || isempty(ncl_pf), ncl_pf = 1.0; end

nb = size(loads.P24, 1);
T  = size(loads.P24, 2);

P_CL  = loads.P24;    % start with all load as critical
Q_CL  = loads.Q24;
P_NCL = zeros(nb, T);
Q_NCL = zeros(nb, T);

% NCL reactive from power factor
if ncl_pf < 1.0
    tan_phi = tan(acos(ncl_pf));
else
    tan_phi = 0;
end

for b = es_buses(:)'
    if b < 1 || b > nb, continue; end
    P_NCL(b, :) = alpha_ncl * loads.P24(b, :);
    P_CL(b,  :) = loads.P24(b, :) - P_NCL(b, :);

    if ncl_pf < 1.0
        % NCL has its own Q from specified PF; CL keeps remaining Q
        Q_NCL(b, :) = P_NCL(b, :) * tan_phi;
        Q_CL(b,  :) = loads.Q24(b, :) - Q_NCL(b, :);
        Q_CL(b,  :) = max(Q_CL(b, :), 0);  % prevent negative CL reactive
    else
        % NCL is purely resistive: split Q proportionally
        Q_NCL(b, :) = alpha_ncl * loads.Q24(b, :);
        Q_CL(b,  :) = loads.Q24(b, :) - Q_NCL(b, :);
    end
end

cl_ncl.P_CL    = P_CL;
cl_ncl.Q_CL    = Q_CL;
cl_ncl.P_NCL   = P_NCL;
cl_ncl.Q_NCL   = Q_NCL;
cl_ncl.alpha   = alpha_ncl;
cl_ncl.ncl_pf  = ncl_pf;
cl_ncl.es_buses = es_buses(:)';
end
