function res = solve_hybrid_opf_case(params, topo, loads, ops)
%SOLVE_HYBRID_OPF_CASE  Generalised ES+Qg SOCP-OPF solver — Module 9.
%
% Extends solve_es_socp_opf_case (Module 8) with four new capabilities:
%   (1) Heterogeneous rho: distinct NCL fraction per bus
%   (2) Qg support buses: reactive injection from dedicated devices
%   (3) Second-generation ES: inverter reactive capability bound by S_rated
%   (4) Soft voltage lower bound: slack variable for diagnostic runs
%
% INPUTS
%   params   struct — all scenario parameters (see fields below)
%   topo     topology struct from build_distflow_topology_from_branch_csv
%   loads    load struct from build_24h_load_profile_from_csv  (P24, Q24)
%   ops      YALMIP sdpsettings
%
% params FIELDS
%   .name         string   folder-safe scenario identifier
%   .label        string   human-readable label
%   .es_buses     [1×ne]   ES bus indices (1-indexed, not root)
%   .rho          [nb×1]   NCL fraction per bus  (0 for non-ES buses)
%   .u_min        [nb×1]   minimum NCL scaling   (1 for non-ES buses)
%   .lambda_u     scalar   curtailment penalty (>= 0)
%   .qg_buses     [1×nq]   reactive support bus indices ([] = none)
%   .Qg_max       [nb×1]   max reactive injection [pu]  (0 if not Qg bus)
%   .lambda_q     scalar   Qg utilisation cost (>= 0)
%   .second_gen   logical  enable 2nd-gen ES reactive capability
%   .S_rated      [nb×1]   ES inverter apparent power rating [pu]
%                          (0 for non-2nd-gen buses; determines Q_ES headroom)
%   .Vmin         scalar   voltage lower bound [pu]
%   .Vmax         scalar   voltage upper bound [pu]
%   .soft_voltage logical  relax lower bound with a slack variable
%   .lambda_sv    scalar   voltage-slack penalty (large → minimise violation)
%   .price        [T×1]    time-of-use price vector
%   .out_dir      string   full path to output folder
%
% RETURNED res FIELDS
%   .feasible, .sol_code, .sol_info
%   .V_val        [nb×T]   voltage magnitudes  (NaN if infeasible)
%   .u_val        [nb×T]   NCL scaling factors
%   .Qg_val       [nb×T]   Qg dispatch         (zeros if no Qg)
%   .Q_ES_val     [nb×T]   2nd-gen reactive    (zeros if not 2nd-gen)
%   .sv_val       [nb×T]   voltage slack V^2   (zeros if hard constraint)
%   .Vmin_t       [T×1]    minimum voltage per hour
%   .VminBus_t    [T×1]    bus achieving minimum
%   .loss_t       [T×1]    total active loss per hour [pu]
%   .costloss_t   [T×1]    price-weighted loss per hour
%   .total_loss   scalar
%   .weighted_obj scalar   objective value
%   .mean_curtailment  scalar  mean NCL curtailment at ES buses [0,1]
%   .total_Qg     scalar   sum of all Qg dispatch over 24 h [pu·h]
%   .max_Q_ES     scalar   peak 2nd-gen reactive injection [pu]
%   .max_sv       scalar   worst voltage slack
%   .worst_hour   scalar   hour with lowest Vmin

T    = 24;
nb   = topo.nb;
nl   = topo.nl_tree;
root = topo.root;

from  = topo.from(:);
R     = topo.R(:);
X     = topo.X(:);

Pd    = loads.P24;      % nb×T
Qd    = loads.Q24;
price = params.price(:);

% =========================================================================
%  LOAD DECOMPOSITION  (heterogeneous rho — zero for non-ES buses)
% =========================================================================
rho     = params.rho(:);      % nb×1
u_min_v = params.u_min(:);    % nb×1  (1 for non-ES buses)

Pd_fixed = (1 - rho) .* Pd;   % nb×T  critical load (never curtailed)
Qd_fixed = (1 - rho) .* Qd;
Pncl0    =       rho  .* Pd;   % nb×T  NCL baseline (scaled by u)
Qncl0    =       rho  .* Qd;

% =========================================================================
%  DECISION VARIABLES
% =========================================================================
v   = sdpvar(nb, T, 'full');   % squared voltage  V^2
Pij = sdpvar(nl, T, 'full');   % branch active flow
Qij = sdpvar(nl, T, 'full');   % branch reactive flow
ell = sdpvar(nl, T, 'full');   % squared current  I^2
u   = sdpvar(nb, T, 'full');   % NCL scaling factor
c   = sdpvar(nb, T, 'full');   % curtailment aux  c = 1 - u  (>= 0)

% Reactive support (Qg)
use_Qg = ~isempty(params.qg_buses);
if use_Qg
    Qg = sdpvar(nb, T, 'full');
end

% Second-generation ES reactive (Q_ES)
use_Q_ES = params.second_gen && ~isempty(params.es_buses);
if use_Q_ES
    Q_ES = sdpvar(nb, T, 'full');
end

% Soft-voltage slack
if params.soft_voltage
    sv = sdpvar(nb, T, 'full');
end

% =========================================================================
%  ADJACENCY MAPS
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
    Con = [Con, v + sv >= params.Vmin^2];    % soft lower bound
else
    Con = [Con, v >= params.Vmin^2];         % hard lower bound
end
Con = [Con, v <= params.Vmax^2, ell >= 0];
Con = [Con, v(root, :) == 1.0];

% --- u and curtailment bounds ---
for t = 1:T
    Con = [Con, u(:, t) >= u_min_v, u(:, t) <= 1];
end
Con = [Con, c == 1 - u, c >= 0];

% --- Qg bounds ---
if use_Qg
    Qg_max_v = params.Qg_max(:);    % nb×1
    for j = 1:nb
        if ismember(j, params.qg_buses)
            Con = [Con, Qg(j,:) >= 0, Qg(j,:) <= Qg_max_v(j)];
        else
            Con = [Con, Qg(j,:) == 0];
        end
    end
end

% --- Second-generation ES: reactive bounds + inverter rating ---
%
% The ES inverter handles curtailed active power AND reactive injection.
% Apparent power constraint:
%   P_curtailed(j,t)^2 + Q_ES(j,t)^2  <=  S_rated(j)^2
% where P_curtailed(j,t) = (1 - u(j,t)) * Pncl0(j,t)   [affine in u]
%
% Written as Lorentz cone (standard SOCP form):
%   || [ P_curtailed ; Q_ES ] ||_2  <=  S_rated
%
if use_Q_ES
    S_rated_v = params.S_rated(:);   % nb×1
    for j = 1:nb
        if ismember(j, params.es_buses) && S_rated_v(j) > 0
            for t = 1:T
                % Curtailed active power (affine in u — Pncl0 is constant data)
                P_curt = Pncl0(j,t) * (1 - u(j,t));
                Con = [Con, Q_ES(j,t) >= 0];
                Con = [Con, cone([P_curt; Q_ES(j,t)], S_rated_v(j))];
            end
        else
            Con = [Con, Q_ES(j,:) == 0];
        end
    end
end

% --- DistFlow power balance + voltage drop + SOCP cone ---
%
% Net reactive injection at bus j:
%   Q_net(j,t) = Qg(j,t) [if Qg bus]  +  Q_ES(j,t) [if 2nd-gen ES bus]
%
for t = 1:T
    for j = 1:nb
        if j == root, continue; end

        kpar = line_of_child(j);
        i    = from(kpar);

        % Effective active demand (linear in u)
        Peff = Pd_fixed(j,t) + u(j,t)*Pncl0(j,t);

        % Effective reactive demand minus injections
        Qeff = Qd_fixed(j,t) + u(j,t)*Qncl0(j,t);
        if use_Qg
            Qeff = Qeff - Qg(j,t);
        end
        if use_Q_ES
            Qeff = Qeff - Q_ES(j,t);
        end

        % Downstream power sum
        ch = outLines{j};
        if isempty(ch)
            sumP = 0;  sumQ = 0;
        else
            sumP = sum(Pij(ch, t));
            sumQ = sum(Qij(ch, t));
        end

        % Power balance
        Con = [Con, ...
            Pij(kpar,t) == Peff  + sumP + R(kpar)*ell(kpar,t), ...
            Qij(kpar,t) == Qeff + sumQ + X(kpar)*ell(kpar,t)];

        % Voltage drop
        Con = [Con, ...
            v(j,t) == v(i,t) ...
                    - 2*(R(kpar)*Pij(kpar,t) + X(kpar)*Qij(kpar,t)) ...
                    + (R(kpar)^2 + X(kpar)^2)*ell(kpar,t)];

        % SOCP relaxation  Pij^2 + Qij^2 <= ell * v_parent
        Con = [Con, cone([2*Pij(kpar,t); 2*Qij(kpar,t); ell(kpar,t)-v(i,t)], ...
                          ell(kpar,t)+v(i,t))];
    end
end

% =========================================================================
%  OBJECTIVE
%   J1  price-weighted loss cost
%   J2  NCL curtailment penalty   (discourages aggressive load shedding)
%   J3  Qg utilisation cost       (discourages over-use of reactive devices)
%   J4  voltage-slack penalty     (diagnostic mode only)
% =========================================================================
lossCost = 0;
for t = 1:T
    lossCost = lossCost + price(t)*sum(R.*ell(:,t));
end

curtCost = 0;
if params.lambda_u > 0
    for b = params.es_buses(:)'
        curtCost = curtCost + params.lambda_u*sum(c(b,:));
    end
end

qgCost = 0;
if use_Qg && params.lambda_q > 0
    for t = 1:T
        qgCost = qgCost + params.lambda_q*sum(Qg(:,t));
    end
end

svCost = 0;
if params.soft_voltage
    svCost = params.lambda_sv*sum(sum(sv));
end

Obj = lossCost + curtCost + qgCost + svCost;

% =========================================================================
%  SOLVE
% =========================================================================
fprintf('  [%s] solving ...\n', params.label);
sol = optimize(Con, Obj, ops);

if ~exist(params.out_dir, 'dir'), mkdir(params.out_dir); end

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

    Qg_val   = zeros(nb, T);
    Q_ES_val = zeros(nb, T);
    sv_val   = zeros(nb, T);

    if use_Qg,     Qg_val   = max(value(Qg),   0); end
    if use_Q_ES,   Q_ES_val = max(value(Q_ES),  0); end
    if params.soft_voltage, sv_val = max(value(sv), 0); end

    loss_t     = zeros(T, 1);
    costloss_t = zeros(T, 1);
    Vmin_t     = zeros(T, 1);
    VminBus_t  = zeros(T, 1);
    for t = 1:T
        loss_t(t)     = sum(R.*ell_val(:,t));
        costloss_t(t) = price(t)*loss_t(t);
        [Vmin_t(t), VminBus_t(t)] = min(V_val(:,t));
    end

    [~, worstHour] = min(Vmin_t);
    curtRatio = 1 - u_val(params.es_buses, :);   % ne×T

    res.V_val            = V_val;
    res.u_val            = u_val;
    res.Qg_val           = Qg_val;
    res.Q_ES_val         = Q_ES_val;
    res.sv_val           = sv_val;
    res.Vmin_t           = Vmin_t;
    res.VminBus_t        = VminBus_t;
    res.loss_t           = loss_t;
    res.costloss_t       = costloss_t;
    res.total_loss       = sum(loss_t);
    res.weighted_obj     = value(Obj);
    res.mean_curtailment = mean(curtRatio(:));
    res.total_Qg         = sum(Qg_val(:));
    res.max_Q_ES         = max(Q_ES_val(:));
    res.max_sv           = max(sv_val(:));
    res.worst_hour       = worstHour;

    % ---------------------------------------------------------------
    %  SAVE CSVs
    % ---------------------------------------------------------------
    summary = table((1:T).', price, Vmin_t, VminBus_t, loss_t, costloss_t, ...
        'VariableNames', {'Hour','Price','Vmin_pu','VminBus','Loss_pu','LossCost'});
    writetable(summary, fullfile(params.out_dir,'summary_24h.csv'));

    writetable(array2table(V_val,'VariableNames',compose('h%02d',1:T)), ...
        fullfile(params.out_dir,'V_bus_by_hour.csv'));
    writetable(array2table(u_val,'VariableNames',compose('h%02d',1:T)), ...
        fullfile(params.out_dir,'u_bus_by_hour.csv'));

    Pd_eff_val = Pd_fixed + u_val.*Pncl0;
    writetable(array2table(Pd_eff_val,'VariableNames',compose('h%02d',1:T)), ...
        fullfile(params.out_dir,'Pd_eff_by_hour.csv'));

    if use_Qg && res.total_Qg > 1e-8
        writetable(array2table(Qg_val,'VariableNames',compose('h%02d',1:T)), ...
            fullfile(params.out_dir,'Qg_by_hour.csv'));
        qg_peak = max(Qg_val,[],2);
        qg_sum  = sum(Qg_val,2);
        qgTbl   = table((1:nb).',qg_peak,qg_sum, ...
            'VariableNames',{'Bus','PeakQg_pu','SumQg_pu_h'});
        writetable(qgTbl(qg_peak>1e-6,:), fullfile(params.out_dir,'Qg_summary.csv'));
    end

    if use_Q_ES && res.max_Q_ES > 1e-8
        writetable(array2table(Q_ES_val,'VariableNames',compose('h%02d',1:T)), ...
            fullfile(params.out_dir,'Q_ES_by_hour.csv'));
    end

    esLabels  = compose('bus%d', params.es_buses(:));
    curtTable = array2table(curtRatio,'RowNames',esLabels, ...
        'VariableNames',compose('h%02d',1:T));
    writetable(curtTable, fullfile(params.out_dir,'curtailment_ratio.csv'), ...
        'WriteRowNames',true);

    if params.soft_voltage && res.max_sv > 1e-5
        writetable(array2table(sv_val,'VariableNames',compose('h%02d',1:T)), ...
            fullfile(params.out_dir,'voltage_slack.csv'));
        thr = 1e-5;
        maxSV = max(sv_val,[],2);
        slkTbl = table((1:nb).',maxSV,sum(sv_val>thr,2), ...
            'VariableNames',{'Bus','MaxSlack_V2','HoursViolated'});
        writetable(slkTbl(maxSV>thr,:), fullfile(params.out_dir,'slack_summary.csv'));
    end

    % ---------------------------------------------------------------
    %  PLOTS
    % ---------------------------------------------------------------
    fh = figure('Visible','off');
    plot(1:T, Vmin_t,'-o','LineWidth',1.4); grid on; hold on;
    plot([1 T],[params.Vmin params.Vmin],'--r','DisplayName','Vmin limit');
    xlabel('Hour'); ylabel('Min Voltage (p.u.)');
    title([params.label ': Minimum Voltage vs Hour']);
    legend({'Vmin(t)','Limit'},'Location','best');
    saveas(fh, fullfile(params.out_dir,'Vmin_vs_hour.png')); close(fh);

    fh = figure('Visible','off');
    plot(1:T, loss_t,'-o','LineWidth',1.4); grid on;
    xlabel('Hour'); ylabel('Total Loss (p.u.)');
    title([params.label ': Feeder Loss vs Hour']);
    saveas(fh, fullfile(params.out_dir,'loss_vs_hour.png')); close(fh);

    fh = figure('Visible','off');
    plot(1:nb, V_val(:,worstHour),'-o','LineWidth',1.4); grid on; hold on;
    plot([1 nb],[params.Vmin params.Vmin],'--r');
    plot([1 nb],[params.Vmax params.Vmax],'--g');
    xlabel('Bus'); ylabel('Voltage (p.u.)');
    title(sprintf('%s: Voltage Profile — Hour %d', params.label, worstHour));
    legend({'V(pu)','Vmin','Vmax'},'Location','best');
    saveas(fh, fullfile(params.out_dir, sprintf('voltage_profile_h%02d.png',worstHour)));
    close(fh);

    if ~isempty(params.es_buses)
        fh = figure('Visible','off'); hold on; grid on;
        clr = lines(numel(params.es_buses));
        for k = 1:numel(params.es_buses)
            plot(1:T, u_val(params.es_buses(k),:),'-o','Color',clr(k,:), ...
                'LineWidth',1.2,'DisplayName',sprintf('Bus %d',params.es_buses(k)));
        end
        xlabel('Hour'); ylabel('u(j,t)'); ylim([0 1.1]);
        title([params.label ': NCL Scaling at ES Buses']);
        legend('Location','best'); hold off;
        saveas(fh, fullfile(params.out_dir,'u_vs_hour.png')); close(fh);

        fh = figure('Visible','off'); hold on; grid on;
        for k = 1:numel(params.es_buses)
            plot(1:T, curtRatio(k,:)*100,'-o','Color',clr(k,:),'LineWidth',1.2, ...
                'DisplayName',sprintf('Bus %d',params.es_buses(k)));
        end
        xlabel('Hour'); ylabel('NCL Curtailment (%)'); ylim([-5 105]);
        title([params.label ': Curtailment at ES Buses']);
        legend('Location','best'); hold off;
        saveas(fh, fullfile(params.out_dir,'curtailment_vs_hour.png')); close(fh);
    end

    if use_Qg && res.total_Qg > 1e-8
        fh = figure('Visible','off'); hold on; grid on;
        clr2 = lines(numel(params.qg_buses));
        for k = 1:numel(params.qg_buses)
            b = params.qg_buses(k);
            plot(1:T, Qg_val(b,:),'-s','Color',clr2(k,:),'LineWidth',1.2, ...
                'DisplayName',sprintf('Qg Bus %d',b));
        end
        xlabel('Hour'); ylabel('Qg (p.u.)');
        title([params.label ': Reactive Injection (Qg) vs Hour']);
        legend('Location','best'); hold off;
        saveas(fh, fullfile(params.out_dir,'Qg_vs_hour.png')); close(fh);
    end

    if use_Q_ES && res.max_Q_ES > 1e-8
        fh = figure('Visible','off'); hold on; grid on;
        clr3 = lines(numel(params.es_buses));
        for k = 1:numel(params.es_buses)
            b = params.es_buses(k);
            plot(1:T, Q_ES_val(b,:),'-^','Color',clr3(k,:),'LineWidth',1.2, ...
                'DisplayName',sprintf('Q_{ES} Bus %d',b));
        end
        xlabel('Hour'); ylabel('Q_{ES} (p.u.)');
        title([params.label ': 2nd-Gen ES Reactive Injection']);
        legend('Location','best'); hold off;
        saveas(fh, fullfile(params.out_dir,'Q_ES_vs_hour.png')); close(fh);
    end

    fprintf('    OK | Vmin=%.4f(h%d,b%d) | Loss=%.5f | Curt=%.1f%% | Qg=%.4f | QES=%.4f\n', ...
        min(Vmin_t), worstHour, VminBus_t(worstHour), ...
        sum(loss_t), 100*res.mean_curtailment, res.total_Qg, res.max_Q_ES);

else
    % Infeasible — populate NaN so comparison table still works
    res.V_val            = NaN(nb, T);
    res.u_val            = NaN(nb, T);
    res.Qg_val           = NaN(nb, T);
    res.Q_ES_val         = NaN(nb, T);
    res.sv_val           = NaN(nb, T);
    res.Vmin_t           = NaN(T, 1);
    res.VminBus_t        = NaN(T, 1);
    res.loss_t           = NaN(T, 1);
    res.costloss_t       = NaN(T, 1);
    res.total_loss       = NaN;
    res.weighted_obj     = NaN;
    res.mean_curtailment = NaN;
    res.total_Qg         = NaN;
    res.max_Q_ES         = NaN;
    res.max_sv           = NaN;
    res.worst_hour       = NaN;
    fprintf('    INFEASIBLE | Code=%d | %s\n', sol.problem, sol.info);
end

write_scenario_info_hybrid(params, res);

end   % end solve_hybrid_opf_case


% =========================================================================
%  LOCAL HELPER
% =========================================================================
function write_scenario_info_hybrid(params, res)
fpath = fullfile(params.out_dir, 'scenario_info.txt');
fid   = fopen(fpath, 'w');
fprintf(fid, '==================================================\n');
fprintf(fid, ' MODULE 9 SCENARIO: %s\n', params.label);
fprintf(fid, '==================================================\n');
fprintf(fid, ' ES buses      : %s\n', mat2str(params.es_buses(:)'));
rho_es = params.rho(params.es_buses);
fprintf(fid, ' rho(ES buses) : %s\n', mat2str(rho_es(:)'));
umin_es = params.u_min(params.es_buses);
fprintf(fid, ' u_min(ES)     : %s\n', mat2str(umin_es(:)'));
fprintf(fid, ' lambda_u      : %.4f\n', params.lambda_u);
fprintf(fid, ' Qg buses      : %s\n', mat2str(params.qg_buses));
if ~isempty(params.qg_buses)
    fprintf(fid, ' Qg_max(Qg)    : %s\n', mat2str(params.Qg_max(params.qg_buses)'));
end
fprintf(fid, ' lambda_q      : %.4f\n', params.lambda_q);
fprintf(fid, ' Second-gen ES : %d\n', params.second_gen);
if params.second_gen && ~isempty(params.es_buses)
    fprintf(fid, ' S_rated(ES)   : %s\n', mat2str(params.S_rated(params.es_buses)'));
end
fprintf(fid, ' Vmin / Vmax   : %.4f / %.4f pu\n', params.Vmin, params.Vmax);
fprintf(fid, ' Soft voltage  : %d\n', params.soft_voltage);
if params.soft_voltage
    fprintf(fid, ' lambda_sv     : %.2f\n', params.lambda_sv);
end
fprintf(fid, '--------------------------------------------------\n');
fprintf(fid, ' FEASIBLE      : %d\n', res.feasible);
fprintf(fid, ' Solver code   : %d\n', res.sol_code);
fprintf(fid, ' Solver info   : %s\n', res.sol_info);
if res.feasible
    fprintf(fid, '--------------------------------------------------\n');
    fprintf(fid, ' Min voltage   : %.6f pu\n', min(res.Vmin_t));
    fprintf(fid, ' Worst hour    : %d\n',       res.worst_hour);
    fprintf(fid, ' Total loss    : %.6f pu\n',  res.total_loss);
    fprintf(fid, ' Weighted obj  : %.4f\n',     res.weighted_obj);
    fprintf(fid, ' Mean curtail  : %.2f%%\n',   100*res.mean_curtailment);
    fprintf(fid, ' Total Qg      : %.6f pu·h\n',res.total_Qg);
    fprintf(fid, ' Max Q_ES      : %.6f pu\n',  res.max_Q_ES);
    fprintf(fid, ' Max V-slack   : %.4e\n',     res.max_sv);
end
fprintf(fid, '==================================================\n');
fclose(fid);
end
