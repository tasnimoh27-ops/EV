% Main script to calculate network R/X ratio analysis
% Generates a comprehensive table of R/X ratios for all branches

clear; clc; close all;

% Change to functions directory to access calculate_rx_ratio
addpath('../functions');

% Calculate R/X ratio and generate table
rx_table = calculate_rx_ratio();

% Display first 10 rows
disp('First 10 branches:');
disp(rx_table(1:10, :));
