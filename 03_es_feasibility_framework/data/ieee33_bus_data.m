function bus_data = ieee33_bus_data()
%IEEE33_BUS_DATA  Return IEEE 33-bus system bus data.
%
% Returns struct with base quantities and per-unit conversions.
% Source: Baran & Wu (1989) radial distribution network.

bus_data.n_bus      = 33;
bus_data.n_load_bus = 32;       % buses 2–33
bus_data.slack_bus  = 1;
bus_data.Vbase_kV   = 12.66;    % kV
bus_data.Sbase_kVA  = 1000;     % kVA  (1 MVA base)
bus_data.Vmin_pu    = 0.95;
bus_data.Vmax_pu    = 1.05;
bus_data.load_buses = (2:33)';

% Base active/reactive loads per bus (kW / kVAr) — Baran & Wu values
%  Bus 1 = slack (substation) — zero load
P_kW = [0; 100; 90; 120; 60; 60; 200; 200; 60; 60; ...
        45; 60; 60; 120; 60; 60; 60; 90; 90; 90; ...
        90; 90; 420; 420; 60; 60; 60; 120; 200; 150; ...
        210; 60; 60];

Q_kVAr = [0; 60; 40; 80; 30; 20; 100; 100; 20; 20; ...
          30; 35; 35; 80; 10; 20; 20; 40; 40; 40; ...
          40; 40; 200; 200; 25; 25; 20; 70; 600; 70; ...
          100; 40; 40];

bus_data.P_kW   = P_kW;
bus_data.Q_kVAr = Q_kVAr;
bus_data.P_pu   = P_kW  / bus_data.Sbase_kVA;
bus_data.Q_pu   = Q_kVAr / bus_data.Sbase_kVA;
end
