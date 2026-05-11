function res = solve_es_socp_opf_case(params, topo, loads, ops)
%SOLVE_ES_SOCP_OPF_CASE  ES smart-load SOCP OPF for one scenario.
%
% Builds, solves, and saves one ES scenario.  Never throws — infeasible
% results are recorded and returned with NaN numerics.
%
% INPUTS
%   params   struct with all scenario parameters (see fields below)
%   topo     topology struct from build_distflow_topology_from_branch_csv
%   loads    load struct from build_24h_load_profile_from_csv  (P24, Q24)
%   ops      YALMIP sdpsettings
%
% params FIELDS
%   .name         folder-safe identifier   e.g. 'scenario_A_strict'
%   .label        human-readable title     e.g. 'Scenario A — Strict'
%   .es_buses     row vector of ES bus indices  (1-indexed, not root bus)
%   .rho_val      NCL fraction scalar  in [0, 1]
%   .u_min_val    minimum NCL scaling  in [0, 1]
%   .lambda_u     curtailment penalty weight (>= 0)
%   .Vmin         voltage lower bound  p.u.
%   .Vmax         voltage upper bound  p.u.
%   .soft_voltage logical — relax lower bound with slack variables
%   .lambda_sv    voltage-slack penalty (used when soft_voltage = true)
%   .price        T x 1  TOU price vector
%   .out_dir      full path for this scenario's output folder
%
% RETURNED res FIELDS  (all populated whether feasible or not)
%   .feasible          logical
%   .sol_code          YALMIP sol.problem integer
%   .sol_info          YALMIP sol.info string
%   .V_val             nb x T  voltage magnitudes  (NaN if infeasible)
%   .u_val             nb x T  NCL scaling         (NaN if infeasible)
%   .sv_val            nb x T  voltage slack V^2   (zeros / NaN)
%   .Vmin_t            T  x 1  minimum voltage per hour
%   .VminBus_t         T  x 1  bus achieving minimum voltage
%   .loss_t            T  x 1  total active loss per hour
%   .costloss_t        T  x 1  price-weighted loss per hour
%   .total_loss        scalar  sum(loss_t)
%   .weighted_obj      scalar  total objective value
%   .mean_curtailment  scalar  mean NCL curtailment at ES buses  (0..1)
%   .max_sv            scalar  worst voltage slack (0 for hard constraints)
%   .worst_hour        scalar  hour with lowest minimum voltage
%   .params            copy of input params

T    = 24;
nb   = topo.nb;
nl   = topo.nl_tree;
root = topo.root;

from  = topo.from(:);
R     = topo.R(:);
X     = topo.X(:);

Pd    = loads.P24;     % nb x T  (p.u.)
Qd    = loads.Q24;     % nb x T
price = params.price(:);

% =========================================================================
%  LOAD DECOMPOSITION
%  rho(j) = NCL fraction at bus j  (zero for non-ES buses)
%  Pd_fixed = CL portion  — never curtailed
%  Pncl0    = NCL baseline — multiplied by u(j,t) inside the optimisation
%
%  Convexity note: u(j,t) * Pncl0(j,t) is AFFINE in u because Pncl0 is
%  constant data, so the formulation stays SOCP. ✓
% =========================================================================
rho = zeros(nb, 1);
for b = params.es_buses(:)'
    rho(b) = params.rho_val;
end

% Build nb×T load decomposition matrices via safe per-column indexing
Pd_fixed = zeros(nb, T);
Qd_fixed = zeros(nb, T);
Pncl0    = zeros(nb, T);
Qncl0    = zeros(nb, T);
for t = 1:T
    pd_col = Pd(:, t);
    qd_col = Qd(:, t);
    Pd_fixed(:, t) = pd_col - rho .* pd_col;
    Qd_fixed(:, t) = qd_col - rho .* qd_col;
    Pncl0(:, t)    = rho .* pd_col;
    Qncl0(:, t)    = rho .* qd_col;
end

% u bounds: ES buses get [u_min, 1];  non-ES buses are clamped to 1
u_lo = ones(nb, 1);
u_hi = ones(nb, 1);
for b = params.es_buses(:)'
    u_lo(b) = params.u_min_val;
end

% =========================================================================
%  YALMIP DECISION VARIABLES
% =========================================================================
v   = sdpvar(nb, T, 'full');   % squared voltages  V^2
Pij = sdpvar(nl, T, 'full');   % branch active flow
Qij = sdpvar(nl, T, 'full');   % branch reactive flow
ell = sdpvar(nl, T, 'full');   % squared current   I^2
u   = sdpvar(nb, T, 'full');   % NCL scaling factor
c   = sdpvar(nb, T, 'full');   % curtailment aux: c = 1 - u  (>= 0)

if params.soft_voltage
    % sv(j,t) >= 0 is the shortfall in V^2 below Vmin^2.
    % When the voltage is healthy sv = 0; when it falls short sv > 0.
    sv = sdpvar(nb, T, 'full');
end

% =========================================================================
%  ADJACENCY  (same pattern as Module 7)
% =========================================================================
outLines      = cell(nb, 1);
line_of_child = zeros(nb, 1);
for k = 1:nl
    outLines{from(k)}(end+1) = k;
    line_of_child(topo.to(k)) = k;
end

% =========================================================================
%  CONSTRAINTS
% =========================================================================
Con = [];

% --- Voltage bounds ---
if params.soft_voltage
    Con = [Con, sv >= 0];
    Con = [Con, v + sv >= params.Vmin^2];     % soft lower bound
else
    Con = [Con, v >= params.Vmin^2];          % hard lower bound
end
Con = [Con, v <= params.Vmax^2, ell >= 0];
Con = [Con, v(root, :) == 1.0];              % Vslack = 1 pu => V^2 = 1

% --- u and curtailment bounds ---
for t = 1:T
    Con = [Con, u(:, t) >= u_lo, u(:, t) <= u_hi];
end
Con = [Con, c == 1 - u, c >= 0];

% --- DistFlow power balance + voltage drop + SOCP cone ---
for t = 1:T
    for j = 1:nb
        if j == root, continue; end

        kpar = line_of_child(j);
        i    = from(kpar);

        % Effective demand (linear in u — Pncl0 is constant data)
        Peff = Pd_fixed(j,t) + u(j,t) * Pncl0(j,t);
        Qeff = Qd_fixed(j,t) + u(j,t) * Qncl0(j,t);

        % Downstream flow sum
        ch = outLines{j};
        if isempty(ch)
            sumP = 0;  sumQ = 0;
        else
            sumP = sum(Pij(ch, t));
            sumQ = sum(Qij(ch, t));
        end

        % Power balance
        Con = [Con, ...
            Pij(kpar,t) == Peff + sumP + R(kpar)*ell(kpar,t), ...
            Qij(kpar,t) == Qeff + sumQ + X(kpar)*ell(kpar,t)];

        % Voltage drop equation
        Con = [Con, ...
            v(j,t) == v(i,t) ...
                    - 2*(R(kpar)*Pij(kpar,t) + X(kpar)*Qij(kpar,t)) ...
                    + (R(kpar)^2 + X(kpar)^2)*ell(kpar,t)];

        % SOCP relaxation:  Pij^2 + Qij^2 <= ell * v_parent
        % Lorentz cone form: ||[2P; 2Q; ell-v]||_2 <= ell+v
        Con = [Con, ...
            cone([2*Pij(kpar,t); 2*Qij(kpar,t); ell(kpar,t)-v(i,t)], ...
                  ell(kpar,t)+v(i,t))];
    end
end

% =========================================================================
%  OBJECTIVE
%  (1) Weighted loss cost  — same as Module 7 baseline
%  (2) NCL curtailment penalty — discourages aggressive load shedding
%  (3) Voltage-slack penalty — only for soft-constrained scenarios
% =========================================================================
lossCost = 0;
for t = 1:T
    lossCost = lossCost + price(t) * sum(R .* ell(:, t));
end

curtCost = 0;
for b = params.es_buses(:)'
    curtCost = curtCost + params.lambda_u * sum(c(b, :));
end

svCost = 0;
if params.soft_voltage
    svCost = params.lambda_sv * sum(sum(sv));
end

Obj = lossCost + curtCost + svCost;

% =========================================================================
%  SOLVE
% =========================================================================
fprintf('  Solving %s ...\n', params.label);
sol = optimize(Con, Obj, ops);

if ~isempty(params.out_dir) && ~exist(params.out_dir, 'dir'), mkdir(params.out_dir); end

% =========================================================================
%  BUILD RESULT STRUCT
% =========================================================================
res          = struct();
res.params   = params;
res.sol_code = sol.problem;
res.sol_info = sol.info;
res.feasible = (sol.problem == 0);

if res.feasible
    v_val   = value(v);
    V_val   = sqrt(max(v_val, 0));
    ell_val = value(ell);
    u_val   = value(u);

    sv_val  = zeros(nb, T);
    if params.soft_voltage
        sv_val = max(value(sv), 0);   % numerical clean-up
    end

    loss_t     = zeros(T, 1);
    costloss_t = zeros(T, 1);
    Vmin_t     = zeros(T, 1);
    VminBus_t  = zeros(T, 1);
    for t = 1:T
        loss_t(t)     = sum(R .* ell_val(:, t));
        costloss_t(t) = price(t) * loss_t(t);
        [Vmin_t(t), VminBus_t(t)] = min(V_val(:, t));
    end

    [~, worstHour] = min(Vmin_t);
    curtRatio = 1 - u_val(params.es_buses, :);   % ne x T

    res.V_val            = V_val;
    res.u_val            = u_val;
    res.sv_val           = sv_val;
    res.Vmin_t           = Vmin_t;
    res.VminBus_t        = VminBus_t;
    res.loss_t           = loss_t;
    res.costloss_t       = costloss_t;
    res.total_loss       = sum(loss_t);
    res.weighted_obj     = value(Obj);
    res.mean_curtailment = mean(curtRatio(:));
    res.max_sv           = max(sv_val(:));
    res.worst_hour       = worstHour;

    % ---------------------------------------------------------------
    %  SAVE CSVs + FIGURES  (skipped when out_dir is empty)
    % ---------------------------------------------------------------
  if ~isempty(params.out_dir)
    summary = table((1:T).', price, Vmin_t, VminBus_t, loss_t, costloss_t, ...
        'VariableNames', {'Hour','Price','Vmin_pu','VminBus','Loss_pu','LossCost'});
    writetable(summary, fullfile(params.out_dir, 'summary_24h.csv'));

    writetable(array2table(V_val,  'VariableNames', compose('h%02d',1:T)), ...
        fullfile(params.out_dir, 'V_bus_by_hour.csv'));
    writetable(array2table(u_val,  'VariableNames', compose('h%02d',1:T)), ...
        fullfile(params.out_dir, 'u_bus_by_hour.csv'));

    Pd_eff_val = Pd_fixed + u_val .* Pncl0;
    Qd_eff_val = Qd_fixed + u_val .* Qncl0;
    writetable(array2table(Pd_eff_val, 'VariableNames', compose('h%02d',1:T)), ...
        fullfile(params.out_dir, 'Pd_eff_by_hour.csv'));
    writetable(array2table(Qd_eff_val, 'VariableNames', compose('h%02d',1:T)), ...
        fullfile(params.out_dir, 'Qd_eff_by_hour.csv'));

    % Curtailment ratio at ES buses
    esLabels = compose('bus%d', params.es_buses(:));
    curtTable = array2table(curtRatio, 'RowNames', esLabels, ...
        'VariableNames', compose('h%02d',1:T));
    writetable(curtTable, fullfile(params.out_dir, 'curtailment_ratio.csv'), ...
        'WriteRowNames', true);

    % Voltage slack (diagnostic scenarios)
    if params.soft_voltage
        writetable(array2table(sv_val, 'VariableNames', compose('h%02d',1:T)), ...
            fullfile(params.out_dir, 'voltage_slack_V2.csv'));

        thr = 1e-5;
        maxSlack_bus   = max(sv_val, [], 2);
        hoursWithSlack = sum(sv_val > thr, 2);
        slkTbl = table((1:nb).', maxSlack_bus, hoursWithSlack, ...
            'VariableNames', {'Bus','MaxSlack_V2','HoursAboveThreshold'});
        slkTbl = slkTbl(maxSlack_bus > thr, :);
        writetable(slkTbl, fullfile(params.out_dir, 'voltage_slack_summary.csv'));
    end

    % ---------------------------------------------------------------
    %  FIGURES  (all invisible — saved to disk)
    % ---------------------------------------------------------------
    % 1) Minimum voltage vs hour
    fh = figure('Visible','off');
    plot(1:T, Vmin_t, '-o', 'LineWidth',1.4); grid on; hold on;
    plot([1 T],[params.Vmin params.Vmin],'--r','DisplayName','Vmin limit');
    xlabel('Hour'); ylabel('Min Voltage (p.u.)');
    title([params.label ': Minimum Voltage vs Hour']);
    legend('Vmin(t)','Limit','Location','best');
    saveas(fh, fullfile(params.out_dir,'Vmin_vs_hour.png')); close(fh);

    % 2) Loss vs hour
    fh = figure('Visible','off');
    plot(1:T, loss_t, '-o','LineWidth',1.4); grid on;
    xlabel('Hour'); ylabel('Total Loss (p.u.)');
    title([params.label ': Feeder Loss vs Hour']);
    saveas(fh, fullfile(params.out_dir,'loss_vs_hour.png')); close(fh);

    % 3) Voltage profile at worst hour
    fh = figure('Visible','off');
    plot(1:nb, V_val(:,worstHour), '-o','LineWidth',1.4); grid on; hold on;
    plot([1 nb],[params.Vmin params.Vmin],'--r');
    plot([1 nb],[params.Vmax params.Vmax],'--g');
    xlabel('Bus'); ylabel('Voltage (p.u.)');
    title(sprintf('%s: Voltage Profile — Worst Hour %d', params.label, worstHour));
    legend('V (p.u.)','Vmin','Vmax','Location','best');
    saveas(fh, fullfile(params.out_dir, ...
        sprintf('voltage_profile_h%02d.png', worstHour))); close(fh);

    % 4) NCL scaling u(j,t) at ES buses
    if ~isempty(params.es_buses)
        fh = figure('Visible','off');
        hold on; grid on;
        clr = lines(numel(params.es_buses));
        for k = 1:numel(params.es_buses)
            plot(1:T, u_val(params.es_buses(k),:), '-o', 'Color', clr(k,:), ...
                'LineWidth',1.2, 'DisplayName', sprintf('Bus %d', params.es_buses(k)));
        end
        xlabel('Hour'); ylabel('u(j,t)'); ylim([0, 1.1]);
        title([params.label ': NCL Scaling at ES Buses']);
        legend('Location','best'); hold off;
        saveas(fh, fullfile(params.out_dir,'u_vs_hour.png')); close(fh);

        % 5) Curtailment (%) at ES buses
        fh = figure('Visible','off');
        hold on; grid on;
        for k = 1:numel(params.es_buses)
            plot(1:T, curtRatio(k,:)*100, '-o', 'Color', clr(k,:), ...
                'LineWidth',1.2, 'DisplayName', sprintf('Bus %d', params.es_buses(k)));
        end
        xlabel('Hour'); ylabel('NCL Curtailment (%)'); ylim([-5, 105]);
        title([params.label ': Load Curtailment at ES Buses']);
        legend('Location','best'); hold off;
        saveas(fh, fullfile(params.out_dir,'curtailment_vs_hour.png')); close(fh);
    end

    % 6) Voltage slack heatmap (diagnostic only)
    if params.soft_voltage && res.max_sv > 1e-6
        fh = figure('Visible','off');
        imagesc(sv_val); colorbar;
        xlabel('Hour'); ylabel('Bus');
        title([params.label ': Voltage Slack V^2 (p.u.)^2 — Infeasibility Map']);
        colormap('hot');
        saveas(fh, fullfile(params.out_dir,'voltage_slack_heatmap.png')); close(fh);
    end
  end  % ~isempty(params.out_dir)

    fprintf('    OK | Vmin=%.4f (h%d,bus%d) | Loss=%.5f pu | Curt=%.1f%% | MaxSV=%.2e\n', ...
        min(Vmin_t), worstHour, VminBus_t(worstHour), ...
        sum(loss_t), 100*res.mean_curtailment, res.max_sv);

else
    % ------------------------------------------------------------------
    %  INFEASIBLE — populate with NaN so comparison table still works
    % ------------------------------------------------------------------
    res.V_val            = NaN(nb, T);
    res.u_val            = NaN(nb, T);
    res.sv_val           = NaN(nb, T);
    res.Vmin_t           = NaN(T, 1);
    res.VminBus_t        = NaN(T, 1);
    res.loss_t           = NaN(T, 1);
    res.costloss_t       = NaN(T, 1);
    res.total_loss       = NaN;
    res.weighted_obj     = NaN;
    res.mean_curtailment = NaN;
    res.max_sv           = NaN;
    res.worst_hour       = NaN;

    fprintf('    INFEASIBLE | Code=%d | %s\n', sol.problem, sol.info);
end

% Save scenario info file (only when out_dir is set)
if ~isempty(params.out_dir)
    write_scenario_info(params, res);
end

end   % end main function


% =========================================================================
%  LOCAL HELPER
% =========================================================================
function write_scenario_info(params, res)
fpath = fullfile(params.out_dir, 'scenario_info.txt');
fid   = fopen(fpath, 'w');
fprintf(fid, '==================================================\n');
fprintf(fid, ' SCENARIO INFORMATION\n');
fprintf(fid, '==================================================\n');
fprintf(fid, ' Name          : %s\n', params.name);
fprintf(fid, ' Label         : %s\n', params.label);
fprintf(fid, '--------------------------------------------------\n');
fprintf(fid, ' ES buses      : %s\n', mat2str(params.es_buses(:)'));
fprintf(fid, ' rho_val       : %.4f  (NCL fraction)\n', params.rho_val);
fprintf(fid, ' u_min_val     : %.4f  (min NCL scaling)\n', params.u_min_val);
fprintf(fid, ' lambda_u      : %.4f  (curtailment penalty)\n', params.lambda_u);
fprintf(fid, ' Vmin          : %.4f  p.u.\n', params.Vmin);
fprintf(fid, ' Vmax          : %.4f  p.u.\n', params.Vmax);
fprintf(fid, ' soft_voltage  : %d\n', params.soft_voltage);
if params.soft_voltage
    fprintf(fid, ' lambda_sv     : %.2f   (voltage-slack penalty)\n', params.lambda_sv);
end
fprintf(fid, '--------------------------------------------------\n');
fprintf(fid, ' FEASIBLE      : %d\n', res.feasible);
fprintf(fid, ' Solver code   : %d\n', res.sol_code);
fprintf(fid, ' Solver info   : %s\n', res.sol_info);
if res.feasible
    fprintf(fid, '--------------------------------------------------\n');
    fprintf(fid, ' Min voltage   : %.6f  p.u.\n', min(res.Vmin_t));
    fprintf(fid, ' Worst hour    : %d\n',          res.worst_hour);
    fprintf(fid, ' Total loss    : %.6f  p.u.\n',  res.total_loss);
    fprintf(fid, ' Weighted obj  : %.6f\n',         res.weighted_obj);
    fprintf(fid, ' Mean curtail  : %.4f  (%.2f%%)\n', ...
        res.mean_curtailment, res.mean_curtailment*100);
    fprintf(fid, ' Max V-slack   : %.4e\n', res.max_sv);
end
fprintf(fid, '==================================================\n');
fclose(fid);
end
