csvFile = './01_data/loads_base.csv';
%module 2: run the module 1 function
loads = build_24h_load_profile_from_csv( ...
            csvFile, ...
            'system', ...     % or 'diverse'
            true, ...         % use per-unit
            true, ...         % plot
            './out_loads');   % NEW: save CSVs
