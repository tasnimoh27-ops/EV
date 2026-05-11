function result = verify_radial_topology(topo)
%VERIFY_RADIAL_TOPOLOGY  BFS verification of IEEE 33-bus radial topology.
%
% Checks: correct bus count, branch count, radial/tree structure,
% slack bus index, connectivity (all buses reachable from slack).
%
% INPUT
%   topo   topology struct from build_distflow_topology_from_branch_csv
%
% OUTPUT
%   result struct with verification fields and pass/fail flag

nb   = topo.nb;
nl   = topo.nl_tree;
root = topo.root;

result.nb          = nb;
result.nl          = nl;
result.root        = root;
result.checks      = struct();
result.all_pass    = false;

% Check 1: bus count
result.checks.bus_count   = (nb == 33);
result.checks.branch_count = (nl == 32);
result.checks.slack_is_1  = (root == 1);

% Check 2: BFS reachability — all buses reachable from root
from = topo.from(:);
to   = topo.to(:);

% Build adjacency list
adj = cell(nb, 1);
for k = 1:nl
    adj{from(k)}(end+1) = to(k);
    adj{to(k)}(end+1)   = from(k);
end

visited = false(nb, 1);
queue   = root;
visited(root) = true;
while ~isempty(queue)
    cur = queue(1); queue(1) = [];
    for nxt = adj{cur}
        if ~visited(nxt)
            visited(nxt) = true;
            queue(end+1) = nxt; %#ok<AGROW>
        end
    end
end
result.checks.all_connected = all(visited);
result.n_unreachable = sum(~visited);
result.unreachable_buses = find(~visited);

% Check 3: tree property — n_branch == n_bus - 1  (necessary for radial)
result.checks.is_tree = (nl == nb - 1);

% Check 4: no self-loops
result.checks.no_self_loops = ~any(from == to);

% Check 5: weakest buses exist (expected: 17, 18, 32, 33)
expected_weak = [17, 18, 32, 33];
result.checks.weak_buses_exist = all(ismember(expected_weak, 1:nb));

result.all_pass = result.checks.bus_count    && ...
                  result.checks.branch_count  && ...
                  result.checks.slack_is_1    && ...
                  result.checks.all_connected && ...
                  result.checks.is_tree       && ...
                  result.checks.no_self_loops;

% Print summary
fprintf('  Topology Verification:\n');
fprintf('    Buses       : %d  (expect 33) — %s\n', nb, ok_str(result.checks.bus_count));
fprintf('    Branches    : %d  (expect 32) — %s\n', nl, ok_str(result.checks.branch_count));
fprintf('    Slack bus   : %d  (expect  1) — %s\n', root, ok_str(result.checks.slack_is_1));
fprintf('    Connected   : %d unreachable  — %s\n', result.n_unreachable, ok_str(result.checks.all_connected));
fprintf('    Tree (n-1)  : nl=%d nb-1=%d      — %s\n', nl, nb-1, ok_str(result.checks.is_tree));
fprintf('    No loops    :                    — %s\n', ok_str(result.checks.no_self_loops));
if result.all_pass
    fprintf('  >> ALL CHECKS PASSED\n');
else
    fprintf('  >> WARNING: Some checks FAILED\n');
end
end

function s = ok_str(flag)
if flag, s = 'PASS'; else, s = 'FAIL'; end
end
