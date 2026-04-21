clear; clc;
% module 4: verify the topology structure
branchCsv = './mp_export_case33bw/branch.csv';

assert(exist(branchCsv,'file')==2, 'branchCsv path is wrong: %s', branchCsv);

which build_distflow_topology_from_branch_csv -all

topo = build_distflow_topology_from_branch_csv(branchCsv, 1);

disp([topo.nb topo.nl_tree])     % should print [33 32]
disp(topo.dropped_branch_rows)   % should be empty or list tie-lines

fprintf('\n=============================\n');
fprintf('RADIAL STRUCTURE (TREE) CHECK\n');
fprintf('=============================\n');

fprintf('Root bus: %d\n', topo.root);
fprintf('nb=%d, nl_tree=%d (should be nb-1=%d)\n', topo.nb, topo.nl_tree, topo.nb-1);

% Every non-root bus must have exactly 1 parent
numParents = sum(topo.parent ~= 0);
fprintf('Buses with a parent: %d (should be %d)\n', numParents, topo.nb-1);

% Print parent of each bus
fprintf('\n--- Parent of each bus ---\n');
for b = 1:topo.nb
    if b == topo.root
        fprintf('Bus %2d: ROOT\n', b);
    else
        fprintf('Bus %2d: parent = %2d\n', b, topo.parent(b));
    end
end

% Print children list
fprintf('\n--- Children list (tree view) ---\n');
for b = 1:topo.nb
    ch = topo.children{b};
    if isempty(ch)
        fprintf('Bus %2d: [leaf]\n', b);
    else
        fprintf('Bus %2d: children = %s\n', b, mat2str(ch));
    end
end

G = digraph(topo.from, topo.to);   % directed parent->child edges

figure;
h = plot(G, 'Layout','layered');
title('IEEE-33 Radial Tree Topology (Parent \rightarrow Child)');
h.NodeLabel = string(1:topo.nb);
grid on;


