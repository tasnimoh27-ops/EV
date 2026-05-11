%% run_all_analyses_distflow.m
% module 6: Runs DistFlow baseline + time series + stress tests + VAR support (manual).
clear; clc; close all;

% Paths to exported CSVs
caseDir   = './01_data';        % change if needed
loadsCsv  = fullfile(caseDir, 'loads_base.csv');
branchCsv = fullfile(caseDir, 'branch.csv');  % use full branch.csv so BR_STATUS exists

assert(exist(loadsCsv,'file')==2,  "Missing: %s", loadsCsv);
assert(exist(branchCsv,'file')==2, "Missing: %s", branchCsv);


% Output folder
outDir = './out_distflow';
if ~exist(outDir,'dir'), mkdir(outDir); end


% Build topology (DistFlow-ready radial tree)

topo = build_distflow_topology_from_branch_csv(branchCsv, 1);

fprintf('Topology: nb=%d, tree branches=%d\n', topo.nb, topo.nl_tree);
if isfield(topo,'dropped_branch_rows')
    fprintf('Dropped tie-lines rows: %s\n', mat2str(topo.dropped_branch_rows(:).'));
end


% Build 24h loads from CSV (per-unit)

loads = build_24h_load_profile_from_csv(loadsCsv, 'system', true, false);

% Field sanity (to avoid earlier P24 naming issue)
assert(isfield(loads,'P24') && isfield(loads,'Q24'), ...
    "loads struct must contain fields P24 and Q24. Rebuild load profile.");


% DistFlow solver options

opts.maxIter = 200;
opts.tolV    = 1e-9;
opts.verbose = false;
Vslack = 1.0;

% STAGE 1 – Baseline (no control)
%   1) Voltage profiles (peak/off-peak)
%   2) Min voltage vs hour
%   3) Weakest bus


% Identify off-peak and peak hours from total load
Ptot = sum(loads.P24, 1);
[~, t_peak] = max(Ptot);
[~, t_off]  = min(Ptot);

fprintf('\nStage 1:\n');
fprintf('  Peak hour  = %d\n', t_peak);
fprintf('  Off-peak   = %d\n', t_off);

% Run DistFlow at peak/off-peak
res_peak = run_distflow_bfs(loads.P24(:,t_peak), loads.Q24(:,t_peak), topo, Vslack, opts);
res_off  = run_distflow_bfs(loads.P24(:,t_off),  loads.Q24(:,t_off),  topo, Vslack, opts);

% 1A) Voltage profiles (peak/off-peak)
figure; plot(1:topo.nb, res_off.V, '-o'); grid on;
xlabel('Bus'); ylabel('Voltage (p.u.)'); title(sprintf('Voltage Profile (Off-peak hour %d)', t_off));
saveas(gcf, fullfile(outDir, sprintf('stage1_voltage_profile_offpeak_h%02d.png', t_off)));

figure; plot(1:topo.nb, res_peak.V, '-o'); grid on;
xlabel('Bus'); ylabel('Voltage (p.u.)'); title(sprintf('Voltage Profile (Peak hour %d)', t_peak));
saveas(gcf, fullfile(outDir, sprintf('stage1_voltage_profile_peak_h%02d.png', t_peak)));

% 1B) Min voltage vs hour + weakest bus per hour
Vmin_t = zeros(24,1);
VminBus_t = zeros(24,1);
Ploss_t = zeros(24,1);

allV = zeros(topo.nb, 24);  % store voltages for envelope (used later)
for t = 1:24
    res_t = run_distflow_bfs(loads.P24(:,t), loads.Q24(:,t), topo, Vslack, opts);
    allV(:,t) = res_t.V;
    Vmin_t(t) = res_t.Vmin;
    VminBus_t(t) = res_t.VminBus;
    Ploss_t(t) = res_t.PlossTot;
end

figure; plot(1:24, Vmin_t, '-o'); grid on;
xlabel('Hour'); ylabel('Minimum Voltage (p.u.)'); title('Stage 1: Minimum Voltage vs Hour');
saveas(gcf, fullfile(outDir, 'stage1_min_voltage_vs_hour.png'));

% Weakest bus overall (most frequent, plus worst-case)
[~, worstHour] = min(Vmin_t);
weakestBus_worstHour = VminBus_t(worstHour);

% "most frequent weakest bus"
weakestBus_mode = mode(VminBus_t);

fprintf('  Worst hour by Vmin: hour %d (Vmin=%.4f) at bus %d\n', worstHour, Vmin_t(worstHour), weakestBus_worstHour);
fprintf('  Most frequent weakest bus over 24h: bus %d\n', weakestBus_mode);

% Save Stage 1 summary CSV
stage1 = table((1:24).', Vmin_t, VminBus_t, Ploss_t, 'VariableNames', ...
    {'Hour','Vmin_pu','VminBus','PlossTot_pu'});
writetable(stage1, fullfile(outDir, 'stage1_summary_24h.csv'));


% STAGE 2 – Time series
%   1) Daily voltage envelope
%   2) Loss vs hour

fprintf('\nStage 2:\n');

Vmin_bus = min(allV, [], 2);
Vmax_bus = max(allV, [], 2);

figure; hold on; grid on;
plot(1:topo.nb, Vmin_bus, '-o');
plot(1:topo.nb, Vmax_bus, '-o');
xlabel('Bus'); ylabel('Voltage (p.u.)');
title('Stage 2: Daily Voltage Envelope (min/max over 24h)');
legend('Min over 24h','Max over 24h','Location','best');
hold off;
saveas(gcf, fullfile(outDir, 'stage2_voltage_envelope_minmax.png'));

figure; plot(1:24, Ploss_t, '-o'); grid on;
xlabel('Hour'); ylabel('Total Active Loss (p.u.)');
title('Stage 2: Total Loss vs Hour');
saveas(gcf, fullfile(outDir, 'stage2_loss_vs_hour.png'));

stage2 = table((1:topo.nb).', Vmin_bus, Vmax_bus, 'VariableNames', {'Bus','Vmin_24h','Vmax_24h'});
writetable(stage2, fullfile(outDir, 'stage2_voltage_envelope.csv'));


% STAGE 3 – Stress testing
%   1) Load scaling (±20%)
%   2) Local load shock

fprintf('\nStage 3:\n');

% 3A) Load scaling (0.8, 1.0, 1.2) at peak hour
scales = [0.8 1.0 1.2];
Vprofiles = zeros(topo.nb, numel(scales));

for k = 1:numel(scales)
    s = scales(k);
    Pd = s * loads.P24(:, t_peak);
    Qd = s * loads.Q24(:, t_peak);

    res_s = run_distflow_bfs(Pd, Qd, topo, Vslack, opts);
    Vprofiles(:,k) = res_s.V;

    fprintf('  Scale %.1f @ peak hour %d: Vmin=%.4f at bus %d, Ploss=%.6f pu\n', ...
        s, t_peak, res_s.Vmin, res_s.VminBus, res_s.PlossTot);
end

figure; hold on; grid on;
for k = 1:numel(scales)
    plot(1:topo.nb, Vprofiles(:,k), '-o');
end
xlabel('Bus'); ylabel('Voltage (p.u.)');
title(sprintf('Stage 3: Voltage Profiles @ Peak Hour %d for Load Scaling', t_peak));
legend("0.8x","1.0x","1.2x",'Location','best');
hold off;
saveas(gcf, fullfile(outDir, sprintf('stage3_load_scaling_voltage_profiles_peak_h%02d.png', t_peak)));

% 3B) Local load shock at a chosen bus and hour
shockBus = weakestBus_worstHour;   % good default
shockHour = t_peak;
shockFactor = 1.50;               % +50% at one bus

Pd0 = loads.P24(:, shockHour);
Qd0 = loads.Q24(:, shockHour);

res_base = run_distflow_bfs(Pd0, Qd0, topo, Vslack, opts);

Pd_shock = Pd0; Qd_shock = Qd0;
Pd_shock(shockBus) = shockFactor * Pd_shock(shockBus);
Qd_shock(shockBus) = shockFactor * Qd_shock(shockBus);

res_shock = run_distflow_bfs(Pd_shock, Qd_shock, topo, Vslack, opts);

fprintf('  Local shock @ hour %d, bus %d, factor %.2f\n', shockHour, shockBus, shockFactor);
fprintf('    Base:  Vmin=%.4f (bus %d), Ploss=%.6f pu\n', res_base.Vmin,  res_base.VminBus,  res_base.PlossTot);
fprintf('    Shock: Vmin=%.4f (bus %d), Ploss=%.6f pu\n', res_shock.Vmin, res_shock.VminBus, res_shock.PlossTot);

figure; hold on; grid on;
plot(1:topo.nb, res_base.V, '-o');
plot(1:topo.nb, res_shock.V, '-o');
xlabel('Bus'); ylabel('Voltage (p.u.)');
title(sprintf('Stage 3: Local Load Shock @ Bus %d (Hour %d)', shockBus, shockHour));
legend('Base','Shock','Location','best');
hold off;
saveas(gcf, fullfile(outDir, sprintf('stage3_local_shock_bus%d_h%02d.png', shockBus, shockHour)));


% STAGE 4 – Support strategies
%   1) Manual VAR injection
%   2) Compare before/after

fprintf('\nStage 4:\n');

% Manual VAR injection at weakest bus during peak hour
supportBus = weakestBus_worstHour;
supportHour = t_peak;

% Choose an injection amount in p.u. of Q (positive injection reduces net load Q)
% Start conservative: 20% of that bus Q load at peak hour
Qinj = 0.20 * loads.Q24(supportBus, supportHour);

Pd = loads.P24(:, supportHour);
Qd = loads.Q24(:, supportHour);

res_before = run_distflow_bfs(Pd, Qd, topo, Vslack, opts);

Qd_after = Qd;
Qd_after(supportBus) = max(Qd_after(supportBus) - Qinj, 0);  % net reactive load reduced

res_after = run_distflow_bfs(Pd, Qd_after, topo, Vslack, opts);

fprintf('  VAR support @ hour %d, bus %d, Qinj=%.6f pu\n', supportHour, supportBus, Qinj);
fprintf('    Before: Vmin=%.4f (bus %d), Ploss=%.6f pu\n', res_before.Vmin, res_before.VminBus, res_before.PlossTot);
fprintf('    After : Vmin=%.4f (bus %d), Ploss=%.6f pu\n', res_after.Vmin,  res_after.VminBus,  res_after.PlossTot);

figure; hold on; grid on;
plot(1:topo.nb, res_before.V, '-o');
plot(1:topo.nb, res_after.V,  '-o');
xlabel('Bus'); ylabel('Voltage (p.u.)');
title(sprintf('Stage 4: Manual VAR Support @ Bus %d (Hour %d)', supportBus, supportHour));
legend('Before','After','Location','best');
hold off;
saveas(gcf, fullfile(outDir, sprintf('stage4_var_support_bus%d_h%02d.png', supportBus, supportHour)));

% Save Stage 4 summary
stage4 = table(supportHour, supportBus, Qinj, ...
    res_before.Vmin, res_before.VminBus, res_before.PlossTot, ...
    res_after.Vmin,  res_after.VminBus,  res_after.PlossTot, ...
    'VariableNames', {'Hour','SupportBus','Qinj_pu','Vmin_before','VminBus_before','Ploss_before_pu', ...
                                     'Vmin_after','VminBus_after','Ploss_after_pu'});
writetable(stage4, fullfile(outDir, 'stage4_var_support_summary.csv'));

fprintf('\nAll stages completed. Outputs saved to: %s\n', outDir);
