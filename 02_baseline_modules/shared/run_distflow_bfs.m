function res = run_distflow_bfs(Pd, Qd, topo, Vslack, opts)
% module 5: build the distflow equations
if nargin < 4 || isempty(Vslack), Vslack = 1.0; end
if nargin < 5, opts = struct(); end
if ~isfield(opts,'maxIter'), opts.maxIter = 100; end
if ~isfield(opts,'tolV'),    opts.tolV = 1e-8; end
if ~isfield(opts,'verbose'), opts.verbose = false; end

nb = topo.nb;
nl = topo.nl_tree;
root = topo.root;

Pd = Pd(:); Qd = Qd(:);
if numel(Pd) ~= nb || numel(Qd) ~= nb
    error("Pd and Qd must be nbx1 with nb=%d.", nb);
end

% Oriented (parent to child) branch arrays length nl = nb-1
from = topo.from(:);
to   = topo.to(:);
R    = topo.R(:);
X    = topo.X(:);

% Map each child bus - its connecting line index (parent to child)
line_of_child = zeros(nb,1);
for k = 1:nl
    line_of_child(to(k)) = k;
end

% Initialize voltages
V  = ones(nb,1);
V(root) = Vslack;
V2 = V.^2;

% Initialize flows (start at zero)
Pij = zeros(nl,1);
Qij = zeros(nl,1);
I2  = zeros(nl,1);

% Iterations
converged = false;

for it = 1:opts.maxIter
    V_old = V;

  
    % Backward sweep (leaves to root)
  
    for idx = 1:numel(topo.order_backward)
        j = topo.order_backward(idx);

        if j == root
            continue; % no parent branch for root
        end

        kline = line_of_child(j);    % line index for parent->j
        i = from(kline);             % parent bus

        % Sum flows from j to its children (already computed in backward order)
        Pdown = 0; Qdown = 0;
        ch = topo.children{j};
        for c = 1:numel(ch)
            kid = ch(c);
            k_child_line = line_of_child(kid); % line j to kid
            Pdown = Pdown + Pij(k_child_line);
            Qdown = Qdown + Qij(k_child_line);
        end

        % Start with load + downstream
        Ptmp = Pd(j) + Pdown;
        Qtmp = Qd(j) + Qdown;

        % Add loss terms based on previous I2 estimate with no generation
        % terms
        Pij(kline) = Ptmp + R(kline) * I2(kline);
        Qij(kline) = Qtmp + X(kline) * I2(kline);

        % Update branch current squared using parent bus voltage
        Vi2 = max(V2(i), 1e-12);
        I2(kline) = (Pij(kline)^2 + Qij(kline)^2) / Vi2;
    end

    % Forward sweep (root to leaves)
    % Voltage drop equation on line i->j:
    %   Vj^2 = Vi^2 - 2(R P + X Q) + (R^2 + X^2) * I^2
    %
    V2(root) = Vslack^2;

    for idx = 1:numel(topo.order_forward)
        i = topo.order_forward(idx);

        % Push voltage to each child
        ch = topo.children{i};
        for c = 1:numel(ch)
            j = ch(c);
            kline = line_of_child(j); % line i->j

            V2(j) = V2(i) ...
                    - 2*( R(kline)*Pij(kline) + X(kline)*Qij(kline) ) ...
                    + (R(kline)^2 + X(kline)^2) * I2(kline);

            % Numerical safety
            V2(j) = max(V2(j), 1e-12);
        end
    end

    V = sqrt(V2);

 
    % Convergence check
    dv = max(abs(V - V_old));
    if opts.verbose
        fprintf('Iter %d: max |dV| = %.3e\n', it, dv);
    end

    if dv < opts.tolV
        converged = true;
        break;
    end
end


% Loss calculations
Ploss = R .* I2;
Qloss = X .* I2;

% Min voltage
[Vmin, VminBus] = min(V);

% Pack results
res = struct();
res.V = V;
res.V2 = V2;

res.Pij = Pij;
res.Qij = Qij;
res.I2  = I2;

res.Ploss = Ploss;
res.Qloss = Qloss;
res.PlossTot = sum(Ploss);
res.QlossTot = sum(Qloss);

res.Vmin = Vmin;
res.VminBus = VminBus;

res.iter = it;
res.converged = converged;

if ~converged
    warning('DistFlow did not converge in %d iterations (max |dV|=%.3e).', opts.maxIter, dv);
end
end
