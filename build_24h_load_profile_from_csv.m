function loads = build_24h_load_profile_from_csv(csvFile, mode, usePU, doPlot, outDir)
%module 1:  input load data from mp_export_case33bw

if nargin < 5 || isempty(outDir)
    outDir = '';
end

if nargin < 2 || isempty(mode),   mode = 'system'; end
if nargin < 3 || isempty(usePU),  usePU = true; end
if nargin < 4 || isempty(doPlot), doPlot = false; end


% 1) Read load_base CSV

T = readtable(csvFile);

bus = T.BUS_I;

if usePU
    Pbase = T.PD_pu;
    Qbase = T.QD_pu;
    unitStr = 'p.u.';
else
    Pbase = T.PD_MW;
    Qbase = T.QD_MVAr;
    unitStr = 'MW / MVAr';
end

nb = numel(bus);

% 2) Define 24-hour multiplier

alpha_sys = [ ...
 0.62 0.60 0.58 0.57 0.58 0.62 ...
 0.72 0.82 0.90 0.92 0.90 0.88 ...
 0.86 0.84 0.85 0.90 1.00 1.10 ...
 1.18 1.20 1.12 0.95 0.78 0.68];


% 3) Apply scaling mode

switch lower(mode)
    case 'system'
        alpha = repmat(alpha_sys, nb, 1);

    case 'diverse'
        rng(1);                  % reproducible
        sigma = 0.05;            % 5% diversity
        noise = sigma * randn(nb, 24);
        alpha = repmat(alpha_sys, nb, 1) .* (1 + noise);
        alpha = min(max(alpha, 0.40), 1.30);

    otherwise
        error("mode must be 'system' or 'diverse'");
end


% 4) Build 24-hour loads

P24 = Pbase .* alpha;
Q24 = Qbase .* alpha;



% 5) Package outputs

loads = struct();
loads.bus    = bus;
loads.alpha  = alpha;
loads.Pbase  = Pbase;
loads.Qbase  = Qbase;
loads.P24    = P24;
loads.Q24    = Q24;
loads.unit   = unitStr;
loads.mode   = mode;


% 5) Export to CSV (optional)

if ~isempty(outDir)
    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    hours = 1:24;

    % --- Active power table ---
    TP = array2table(P24, ...
        'VariableNames', strcat('H', string(hours)));
    TP = addvars(TP, bus, 'Before', 1);
    TP.Properties.VariableNames{1} = 'BUS';

    writetable(TP, fullfile(outDir, 'loads_P24.csv'));

    % --- Reactive power table ---
    TQ = array2table(Q24, ...
        'VariableNames', strcat('H', string(hours)));
    TQ = addvars(TQ, bus, 'Before', 1);
    TQ.Properties.VariableNames{1} = 'BUS';

    writetable(TQ, fullfile(outDir, 'loads_Q24.csv'));

    % --- System totals ---
    Ptot = sum(P24, 1).';
    Qtot = sum(Q24, 1).';

    Tsys = table(hours.', Ptot, Qtot, ...
        'VariableNames', {'Hour', 'P_total', 'Q_total'});

    writetable(Tsys, fullfile(outDir, 'loads_system_totals.csv'));
end



% 6) Command window summary

Ptot = sum(P24, 1);
Qtot = sum(Q24, 1);

[Pmax, hPmax] = max(Ptot);
[Pmin, hPmin] = min(Ptot);

fprintf('\n');
fprintf('=============================================\n');
fprintf('24-Hour Load Profile Summary\n');
fprintf('=============================================\n');
fprintf('CSV file           : %s\n', csvFile);
fprintf('Number of buses    : %d\n', nb);
fprintf('Load mode          : %s\n', mode);
fprintf('Units              : %s\n', unitStr);
fprintf('\n');
fprintf('System ACTIVE load:\n');
fprintf('  Min = %.4f at hour %d\n', Pmin, hPmin);
fprintf('  Max = %.4f at hour %d\n', Pmax, hPmax);
fprintf('\n');
fprintf('System REACTIVE load:\n');
fprintf('  Min = %.4f\n', min(Qtot));
fprintf('  Max = %.4f\n', max(Qtot));

if ~isempty(outDir)
    fprintf('\nCSV files saved to:\n');
    fprintf('  %s\n', outDir);
    fprintf('   - loads_P24.csv\n');
    fprintf('   - loads_Q24.csv\n');
    fprintf('   - loads_system_totals.csv\n');
end
fprintf('=============================================\n\n');


% 7) Optional plots (FIXED + ROBUST)

if doPlot
    hours = 1:24;

    % 1) Multiplier
    figure;
    plot(hours, alpha_sys, '-o'); grid on;
    xlabel('Hour');
    ylabel('\alpha(t)');
    title('24-hour Load Multiplier');

    % 2) Total system P
    Ptot = sum(P24, 1);
    figure;
    plot(hours, Ptot, '-o'); grid on;
    xlabel('Hour');
    ylabel(['Total P (' unitStr ')']);
    title(['Total System ACTIVE Load vs Hour (mode = ' mode ')']);

    % 3) Total system Q  <-- THIS WAS MISSING BEFORE
    Qtot = sum(Q24, 1);
    figure;
    plot(hours, Qtot, '-o'); grid on;
    xlabel('Hour');
    ylabel(['Total Q (' unitStr ')']);
    title(['Total System REACTIVE Load vs Hour (mode = ' mode ')']);

   % Example buses
    exampleBuses = [24 25 30];
    figure; hold on; grid on;
    for b = exampleBuses
        idx = find(bus == b);
        if ~isempty(idx)
            plot(hours, P24(idx,:), '-o');
        end
    end
    xlabel('Hour');
    ylabel(['P (' unitStr ')']);
    title('Example Bus Loads vs Hour');
    legend("Bus 24","Bus 25","Bus 30","Location","best");
    hold off;
end

end