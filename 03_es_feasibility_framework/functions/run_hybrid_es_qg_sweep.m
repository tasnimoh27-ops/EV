function results = run_hybrid_es_qg_sweep(topo, loads, out_dir, ops_override)
%RUN_HYBRID_ES_QG_SWEEP  Sweep hybrid ES+Qg over rho, u_min, N_ES, Qg_frac.
%
% Cases H0-H6 and full parameter sweep.

if nargin < 4 || isempty(ops_override), ops_override=struct(); end

rho_vals  = getf(ops_override,'rho_vals',  [0.30,0.40,0.50,0.60,0.70]);
umin_vals = getf(ops_override,'umin_vals', [0.00,0.20]);
N_ES_list = getf(ops_override,'N_ES_list', [4,8,12,16,20,24,28,32]);
Qg_fracs  = getf(ops_override,'Qg_fracs',  [0,0.25,0.50,0.75,1.00]);
t_lim     = getf(ops_override,'time_limit', 300);

T = 24;
price = ones(T,1); price(1:6)=0.6; price(7:16)=1.0; price(17:21)=1.8; price(22:24)=0.9;

if ~exist(out_dir,'dir'), mkdir(out_dir); end

nTotal = numel(rho_vals)*numel(umin_vals)*numel(N_ES_list)*numel(Qg_fracs);
fprintf('  Hybrid sweep: %d cases\n', nTotal);

rows = {};
ct   = 0;

for ir = 1:numel(rho_vals)
    rho = rho_vals(ir);
    for iu = 1:numel(umin_vals)
        u_min = umin_vals(iu);
        for iN = 1:numel(N_ES_list)
            N = N_ES_list(iN);
            for iq = 1:numel(Qg_fracs)
                qf = Qg_fracs(iq);
                ct = ct+1;
                fprintf('  [%d/%d] rho=%.2f umin=%.2f N=%d Qg=%.2f ...\n',...
                    ct,nTotal,rho,u_min,N,qf);

                params.rho=rho; params.u_min=u_min; params.N_ES_max=N;
                params.Qg_limit_frac=qf; params.price=price;
                params.Vmin=0.95; params.Vmax=1.05;
                params.soft_voltage=true; params.obj_mode='feasibility';
                params.time_limit=t_lim;

                try
                    r = solve_hybrid_es_qg_misocp(topo, loads, params);
                catch ME
                    fprintf('    ERROR: %s\n',ME.message);
                    r.feasible=false; r.sol_code=-99; r.sol_info=ME.message;
                    r.n_es=NaN; r.es_buses=[]; r.Vmin_24h=NaN;
                    r.worst_bus=NaN; r.total_loss=NaN; r.mean_curt=NaN;
                    r.max_curt=NaN; r.total_sv=NaN; r.total_Qg=NaN;
                    r.voltage_ok=false; r.solve_time=NaN;
                end

                if qf==0, case_name='ES_only';
                elseif qf==1, case_name='Qg_full_ES';
                else, case_name=sprintf('ES_Qg%.0f',qf*100); end
                rows{end+1} = {case_name, qf, rho, u_min, N, ...
                    double(isfield(r,'voltage_ok')&&r.voltage_ok), ...
                    r.n_es, mat2str(r.es_buses(:)'), ...
                    r.Vmin_24h, r.worst_bus, r.total_loss, ...
                    r.mean_curt, r.max_curt, r.total_sv, r.total_Qg, ...
                    r.sol_code, r.solve_time}; %#ok<AGROW>
            end
        end

        T_partial = build_table(rows);
        writetable(T_partial, fullfile(out_dir,'table_hybrid_sweep_partial.csv'));
    end
end

results = build_table(rows);
writetable(results, fullfile(out_dir,'table_hybrid_es_qg_sweep.csv'));
save(fullfile(out_dir,'hybrid_sweep_results.mat'),'results');
fprintf('  Hybrid sweep complete.\n');
end

function T = build_table(rows)
T = cell2table(vertcat(rows{:}),'VariableNames', ...
    {'Case','Qg_frac','rho','u_min','N_ES_max','Feasible_volt', ...
     'N_ES_sel','ES_Buses','Vmin_pu','WorstBus','TotalLoss_pu', ...
     'MeanCurt','MaxCurt','TotalVoltSlack','TotalQg_pu','SolCode','SolTime_s'});
end

function v = getf(s,f,d)
if isfield(s,f)&&~isempty(s.(f)), v=s.(f); else, v=d; end
end
