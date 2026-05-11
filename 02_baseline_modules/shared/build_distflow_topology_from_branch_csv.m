function topo = build_distflow_topology_from_branch_csv(branchCsv, rootBus)
% module 3: build the radial topology to make it compatible with distflow 
if nargin < 2 || isempty(rootBus), rootBus = 1; end

T = readtable(branchCsv);

% Detect column names 
% Required:
fromCol = pick_col(T, {'F_BUS'});
toCol   = pick_col(T, {'T_BUS'});
rCol    = pick_col(T, {'BR_R_pu'});
xCol    = pick_col(T, {'BR_X_pu'});

from0 = T.(fromCol); from0 = from0(:);
to0   = T.(toCol);   to0   = to0(:);
R0    = T.(rCol);    R0    = R0(:);
X0    = T.(xCol);    X0    = X0(:);

nl0 = numel(from0);
nb  = max([from0; to0]);

% Filter by BR_STATUS if present
activeMask = true(nl0,1);
if any(strcmpi(T.Properties.VariableNames, 'BR_STATUS'))
    activeMask = (T.BR_STATUS(:) == 1);
end

fromA = from0(activeMask);
toA   = to0(activeMask);
RA    = R0(activeMask);
XA    = X0(activeMask);
origIndexA = find(activeMask);  % mapping to original row indices

nlA = numel(fromA);

% Build undirected adjacency on ACTIVE edges
adjBus  = cell(nb,1);
adjEdge = cell(nb,1); % store local edge index (1..nlA)

for e = 1:nlA
    i = fromA(e); j = toA(e);
    adjBus{i}(end+1)  = j;  adjEdge{i}(end+1)  = e;
    adjBus{j}(end+1)  = i;  adjEdge{j}(end+1)  = e;
end

% BFS to build spanning tree
parent = zeros(nb,1);
depth  = -ones(nb,1);
children = cell(nb,1);
edge_of_child = zeros(nb,1); % local active-edge index that connects parent->child

visited = false(nb,1);
q = rootBus;
visited(rootBus) = true;
parent(rootBus) = 0;
depth(rootBus) = 0;

treeEdgesLocal = [];  % local indices of edges in the tree

while ~isempty(q)
    u = q(1); q(1) = [];

    nbrs = adjBus{u};
    eids = adjEdge{u};

    for k = 1:numel(nbrs)
        v = nbrs(k);
        e = eids(k); % local edge index

        if ~visited(v)
            visited(v) = true;
            parent(v) = u;
            depth(v) = depth(u) + 1;

            children{u}(end+1) = v;
            edge_of_child(v) = e;
            treeEdgesLocal(end+1) = e; %#ok<AGROW>

            q(end+1) = v; %#ok<AGROW>
        end
    end
end

% Sanity: all buses reachable?
if any(~visited)
    missing = find(~visited);
    error("Network not fully connected to root bus %d. Missing buses: %s", rootBus, mat2str(missing.'));
end

% Tree must have nb-1 edges
if numel(treeEdgesLocal) ~= nb-1
    error("Spanning tree edge count is %d, expected %d. Check data integrity.", ...
        numel(treeEdgesLocal), nb-1);
end

% Orient tree edges parent->child and build final arrays of length nb-1 
from = zeros(nb-1,1);
to   = zeros(nb-1,1);
R    = zeros(nb-1,1);
X    = zeros(nb-1,1);
orig_branch_row = zeros(nb-1,1); % original CSV row index for each tree edge

% Create a mapping: local edge -> position in tree arrays
posOfLocal = zeros(nlA,1);
for p = 1:(nb-1)
    posOfLocal(treeEdgesLocal(p)) = p;
end

% For each non-root bus v, we know its parent and which edge connects it
for v = 1:nb
    if v == rootBus, continue; end
    eLocal = edge_of_child(v);
    p = posOfLocal(eLocal);

    from(p) = parent(v);
    to(p)   = v;
    R(p)    = RA(eLocal);
    X(p)    = XA(eLocal);
    orig_branch_row(p) = origIndexA(eLocal);
end

% Extra edges (tie-lines) that were active but not in the tree
isTree = false(nlA,1); isTree(treeEdgesLocal) = true;
droppedLocal = find(~isTree);
droppedOriginalRows = origIndexA(droppedLocal);

% Orders for sweeps
order_forward  = bfs_order(children, rootBus);
order_backward = fliplr(order_forward);

% Package
topo = struct();
topo.root = rootBus;
topo.nb = nb;
topo.nl_tree = nb-1;

topo.from = from;
topo.to   = to;
topo.R    = R;
topo.X    = X;

topo.parent = parent;
topo.children = children;
topo.edge_of_child = edge_of_child; % local active-edge index
topo.depth = depth;

topo.order_forward  = order_forward;
topo.order_backward = order_backward;

topo.original_branch_rows_used = orig_branch_row;
topo.dropped_branch_rows = droppedOriginalRows; % these are tie-lines / extra edges
end

function order = bfs_order(children, root)
order = [];
q = root;
while ~isempty(q)
    u = q(1); q(1) = [];
    order(end+1) = u; %#ok<AGROW>
    q = [q, children{u}]; %#ok<AGROW>
end
end

function col = pick_col(T, candidates)
vars = T.Properties.VariableNames;
col = '';
for i = 1:numel(candidates)
    m = strcmpi(vars, candidates{i});
    if any(m)
        col = vars{find(m,1)};
        return;
    end
end
error("Could not find required column. Tried: %s. Available: %s", ...
    strjoin(candidates, ', '), strjoin(vars, ', '));
end
