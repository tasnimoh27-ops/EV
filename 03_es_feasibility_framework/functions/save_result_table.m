function save_result_table(T, out_dir, filename, mat_filename)
%SAVE_RESULT_TABLE  Save table to CSV and optionally MAT file.
%
% INPUTS
%   T             MATLAB table
%   out_dir       output directory (created if missing)
%   filename      CSV filename (e.g. 'table_foo.csv')
%   mat_filename  MAT filename (optional, pass '' to skip)

if ~exist(out_dir,'dir'), mkdir(out_dir); end
csv_path = fullfile(out_dir, filename);
writetable(T, csv_path);
fprintf('  Saved: %s\n', csv_path);

if nargin >= 4 && ~isempty(mat_filename)
    mat_path = fullfile(out_dir, mat_filename);
    save(mat_path, 'T');
    fprintf('  Saved: %s\n', mat_path);
end
end
