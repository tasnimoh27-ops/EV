function cases = define_es_placement_cases(topo, vis)
%DEFINE_ES_PLACEMENT_CASES  Return named ES placement candidate sets.
%
% Defines 5 benchmark placement strategies used throughout the study.
% These are consistent labels used in manual placement, scan, and comparison.
%
% INPUTS
%   topo   topology struct (needs nb, root)
%   vis    struct from calculate_voltage_impact_score (needs rank)
%
% OUTPUTS
%   cases  cell array, each row: {label, bus_vector, description}

nb   = topo.nb;
root = topo.root;
all_non_slack = setdiff(1:nb, root);

% VIS top-7 from sensitivity ranking
vis_top7 = vis.rank(1:min(7, end));
vis_top7 = vis_top7(vis_top7 ~= root)';

% Every 3rd non-slack bus (11 buses in 33-bus network)
every3 = 3:3:nb;
every3 = setdiff(every3, root);

cases = {
    [18, 33],       'P1: {18,33} — terminal weak buses (2)';
    [9,18,26,33],   'P2: {9,18,26,33} — terminal + midpoint (4)';
    vis_top7,       'P3: VIS-top7 — sensitivity-ranked (7)';
    every3,         'P4: every-3rd — distributed (11)';
    all_non_slack,  'P5: all non-slack buses (32)';
};
end
