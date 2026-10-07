clear;
clc;
close all;

%% 数据读取
dataFile = 'F_LPM_STATOR_LPM.csv';
outputDir = fullfile('outputs', 'F_LPM_STATOR_LPM_3a_matlab');

if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

data = readtable(dataFile, 'VariableNamingRule', 'preserve');

lpm = double(data.('lpm [mm]'));
stator_lpm = double(data.('stator_lpm [mm]'));
a = double(data.('a [mm]'));
force = double(data.('Force_move.Force_z [newton]'));

%% 数据处理：三个位移工况下的平均推力和最大差值
% 同一种结构对应 a=-10 mm、a=0 mm、a=10 mm 三个推力值。
% 平均推力：三个推力值的算术平均值。
% 最大差值：max(F)-min(F)，即三个推力值中最大值和最小值之差。
aTargets = [-10, 0, 10];

groupID = findgroups(lpm, stator_lpm);
lpm_group = splitapply(@(x) x(1), lpm, groupID);
stator_lpm_group = splitapply(@(x) x(1), stator_lpm, groupID);
force_a_minus10 = splitapply(@(aa, ff) getForceAtA(aa, ff, -10), a, force, groupID);
force_a0 = splitapply(@(aa, ff) getForceAtA(aa, ff, 0), a, force, groupID);
force_a10 = splitapply(@(aa, ff) getForceAtA(aa, ff, 10), a, force, groupID);

average_force = (force_a_minus10 + force_a0 + force_a10) ./ 3;
force_max_diff = max([force_a_minus10, force_a0, force_a10], [], 2) ...
    - min([force_a_minus10, force_a0, force_a10], [], 2);

summaryTable = table( ...
    lpm_group, ...
    stator_lpm_group, ...
    force_a_minus10, ...
    force_a0, ...
    force_a10, ...
    average_force, ...
    force_max_diff, ...
    'VariableNames', { ...
    'lpm_mm', ...
    'stator_lpm_mm', ...
    'force_a_minus10_N', ...
    'force_a0_N', ...
    'force_a10_N', ...
    'average_force_N', ...
    'force_max_diff_N'});

summaryTable = sortrows(summaryTable, {'lpm_mm', 'stator_lpm_mm'});
writetable(summaryTable, fullfile(outputDir, 'force_summary_3a.xlsx'), ...
    'Sheet', '计算结果');

%% 三维关系图数据整理
lpmList = unique(summaryTable.lpm_mm);
statorLpmList = unique(summaryTable.stator_lpm_mm);
[LpmGrid, StatorLpmGrid] = meshgrid(lpmList, statorLpmList);

AvgForceGrid = nan(size(LpmGrid));
MaxDiffGrid = nan(size(LpmGrid));

for i = 1:height(summaryTable)
    rowIndex = find(statorLpmList == summaryTable.stator_lpm_mm(i), 1);
    colIndex = find(lpmList == summaryTable.lpm_mm(i), 1);
    AvgForceGrid(rowIndex, colIndex) = summaryTable.average_force_N(i);
    MaxDiffGrid(rowIndex, colIndex) = summaryTable.force_max_diff_N(i);
end

%% 绘制三维图 1：平均推力
figure('Color', 'w');
surf(LpmGrid, StatorLpmGrid, AvgForceGrid, ...
    'EdgeColor', [0.35, 0.35, 0.35], ...
    'LineWidth', 0.6, ...
    'FaceAlpha', 0.95);
colormap(parula);
colorbar;
shading interp;
view(45, 28);

ax = gca;
set(ax, ...
    'FontName', 'Times New Roman', ...
    'FontSize', 12, ...
    'LineWidth', 1, ...
    'GridLineStyle', '--');
grid on;
box on;

xlabel('\fontname{SimSun}动子侧永磁体长度 \fontname{Times New Roman}\itl_{\rm pm}\rm (mm)', ...
    'FontSize', 12, 'Interpreter', 'tex');
ylabel('\fontname{SimSun}定子侧永磁体长度 \fontname{Times New Roman}\itl_{\rm pm,s}\rm (mm)', ...
    'FontSize', 12, 'Interpreter', 'tex');
zlabel('\fontname{SimSun}平均推力 \fontname{Times New Roman}\itF_{\rm avg}\rm (N)', ...
    'FontSize', 12, 'Interpreter', 'tex');

set(gcf, 'Units', 'centimeters', 'Position', [10, 5, 11, 8]);

%% 绘制三维图 2：推力最大差值
figure('Color', 'w');
surf(LpmGrid, StatorLpmGrid, MaxDiffGrid, ...
    'EdgeColor', [0.35, 0.35, 0.35], ...
    'LineWidth', 0.6, ...
    'FaceAlpha', 0.95);
colormap(parula);
colorbar;
shading interp;
view(45, 28);

ax = gca;
set(ax, ...
    'FontName', 'Times New Roman', ...
    'FontSize', 12, ...
    'LineWidth', 1, ...
    'GridLineStyle', '--');
grid on;
box on;

xlabel('\fontname{SimSun}动子侧永磁体长度 \fontname{Times New Roman}\itl_{\rm pm}\rm (mm)', ...
    'FontSize', 12, 'Interpreter', 'tex');
ylabel('\fontname{SimSun}定子侧永磁体长度 \fontname{Times New Roman}\itl_{\rm pm,s}\rm (mm)', ...
    'FontSize', 12, 'Interpreter', 'tex');
zlabel('\fontname{SimSun}推力最大差值 \fontname{Times New Roman}\Delta\itF_{\rm max}\rm (N)', ...
    'FontSize', 12, 'Interpreter', 'tex');

set(gcf, 'Units', 'centimeters', 'Position', [10, 5, 11, 8]);

%% 多目标优化：永磁体长度最小、推力最大差值最小、平均推力最大
% 永磁体长度目标沿用前面的物理口径：lpm + 2*stator_lpm。
pm_length_objective = summaryTable.lpm_mm + 2 .* summaryTable.stator_lpm_mm;

score_length = normalizeObjective(pm_length_objective, 'min');
score_diff = normalizeObjective(summaryTable.force_max_diff_N, 'min');
score_average_force = normalizeObjective(summaryTable.average_force_N, 'max');
compromise_score = (score_length + score_diff + score_average_force) ./ 3;

isPareto = true(height(summaryTable), 1);
for i = 1:height(summaryTable)
    for j = 1:height(summaryTable)
        if i == j
            continue;
        end
        if dominatesSolution( ...
                pm_length_objective(j), summaryTable.force_max_diff_N(j), summaryTable.average_force_N(j), ...
                pm_length_objective(i), summaryTable.force_max_diff_N(i), summaryTable.average_force_N(i))
            isPareto(i) = false;
            break;
        end
    end
end

optimizationTable = summaryTable;
optimizationTable.pm_length_objective_mm = pm_length_objective;
optimizationTable.compromise_score = compromise_score;
optimizationTable.is_pareto = isPareto;

rankedCandidates = sortrows(optimizationTable, ...
    {'compromise_score', 'pm_length_objective_mm', 'force_max_diff_N', 'average_force_N'}, ...
    {'descend', 'ascend', 'ascend', 'descend'});
paretoFront = rankedCandidates(rankedCandidates.is_pareto, :);

writetable(rankedCandidates, fullfile(outputDir, 'ranked_candidates_3a.xlsx'), ...
    'Sheet', '综合排序');
writetable(paretoFront, fullfile(outputDir, 'pareto_front_3a.xlsx'), ...
    'Sheet', 'Pareto前沿');

bestSolution = rankedCandidates(1, :);

fprintf('\n最佳折中解：\n');
fprintf('lpm = %.0f mm\n', bestSolution.lpm_mm);
fprintf('stator_lpm = %.0f mm\n', bestSolution.stator_lpm_mm);
fprintf('永磁体长度目标 lpm+2*stator_lpm = %.6f mm\n', bestSolution.pm_length_objective_mm);
fprintf('F(a=-10 mm) = %.9f N\n', bestSolution.force_a_minus10_N);
fprintf('F(a=0) = %.9f N\n', bestSolution.force_a0_N);
fprintf('F(a=10 mm) = %.9f N\n', bestSolution.force_a10_N);
fprintf('平均推力 = %.9f N\n', bestSolution.average_force_N);
fprintf('推力最大差值 max(F)-min(F) = %.9f N\n', bestSolution.force_max_diff_N);
fprintf('综合评分 = %.9f\n', bestSolution.compromise_score);
fprintf('Pareto 解数量 = %d\n', height(paretoFront));
fprintf('\n结果已保存到：%s\n', outputDir);

%% 局部函数
function forceValue = getForceAtA(aValues, forceValues, targetA)
    index = abs(aValues - targetA) < 1e-9;
    if sum(index) ~= 1
        error('某一组参数下未找到唯一的 a=%.6g mm 工况。', targetA);
    end
    forceValue = forceValues(index);
end

function score = normalizeObjective(values, mode)
    minValue = min(values);
    maxValue = max(values);
    if abs(maxValue - minValue) < 1e-12
        score = ones(size(values));
        return;
    end

    normalized = (values - minValue) ./ (maxValue - minValue);
    if strcmpi(mode, 'min')
        score = 1 - normalized;
    else
        score = normalized;
    end
end

function flag = dominatesSolution(lenA, diffA, avgA, lenB, diffB, avgB)
    noWorse = lenA <= lenB && diffA <= diffB && avgA >= avgB;
    strictlyBetter = lenA < lenB || diffA < diffB || avgA > avgB;
    flag = noWorse && strictlyBetter;
end
