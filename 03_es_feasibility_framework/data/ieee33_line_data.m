function line_data = ieee33_line_data()
%IEEE33_LINE_DATA  Return IEEE 33-bus branch impedance data.
%
% Returns branch R and X in per-unit (Sbase=1 MVA, Vbase=12.66 kV).
% Zbase = Vbase^2/Sbase = 12.66^2/1 = 160.27 ohm
%
% Source: Baran & Wu (1989) IEEE Transactions on Power Delivery.

Zbase = 12.66^2 / 1;   % ohm  (Vbase in kV, Sbase in MVA)

% Columns: [from, to, R_ohm, X_ohm]
branch_ohm = [
     1,  2,  0.0922, 0.0470;
     2,  3,  0.4930, 0.2511;
     3,  4,  0.3660, 0.1864;
     4,  5,  0.3811, 0.1941;
     5,  6,  0.8190, 0.7070;
     6,  7,  0.1872, 0.6188;
     7,  8,  0.7114, 0.2351;
     8,  9,  1.0300, 0.7400;
     9, 10,  1.0440, 0.7400;
    10, 11,  0.1966, 0.0650;
    11, 12,  0.3744, 0.1238;
    12, 13,  1.4680, 1.1550;
    13, 14,  0.5416, 0.7129;
    14, 15,  0.5910, 0.5260;
    15, 16,  0.7463, 0.5450;
    16, 17,  1.2890, 1.7210;
    17, 18,  0.7320, 0.5740;
     2, 19,  0.1640, 0.1565;
    19, 20,  1.5042, 1.3554;
    20, 21,  0.4095, 0.4784;
    21, 22,  0.7089, 0.9373;
     3, 23,  0.4512, 0.3083;
    23, 24,  0.8980, 0.7091;
    24, 25,  0.8960, 0.7011;
     6, 26,  0.2030, 0.1034;
    26, 27,  0.2842, 0.1447;
    27, 28,  1.0590, 0.9337;
    28, 29,  0.8042, 0.7006;
    29, 30,  0.5075, 0.2585;
    30, 31,  0.9744, 0.9630;
    31, 32,  0.3105, 0.3619;
    32, 33,  0.3410, 0.5302;
];

line_data.from  = branch_ohm(:,1);
line_data.to    = branch_ohm(:,2);
line_data.R_ohm = branch_ohm(:,3);
line_data.X_ohm = branch_ohm(:,4);
line_data.R_pu  = branch_ohm(:,3) / Zbase;
line_data.X_pu  = branch_ohm(:,4) / Zbase;
line_data.n_branch = size(branch_ohm, 1);
line_data.Zbase = Zbase;
end
