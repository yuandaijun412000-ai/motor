clear;
clc;
close all;

%% 用户设置
scriptDir = fileparts(mfilename('fullpath'));
dataFile = fullfile(scriptDir, 'F_ADD_LPM.csv');
outputDir = fullfile(scriptDir, 'outputs', 'F_ADD_LPM_min_avg_max_diff_optimization');

% 多目标优化至少需要几个工况点参与。
% 当前数据中一部分结构只有 a=0 一个工况，无法形成有效“最大差值”。
% 设为 2 表示至少有两个工况才参与优化；若只想用 a=-10,0,10 齐全的结构，可改为 3。
minPointCountForOptimization = 3;

if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

%% 数据读取
data = readtable(dataFile, 'VariableNamingRule', 'preserve');

lpm = double(data.('lpm [mm]'));
stator_lpm = double(data.('stator_lpm [mm]'));
a = double(data.('a [mm]'));
force = double(data.('Force_move.Force_z [newton]'));

%% 计算每种结构的平均值和最大差值
% 同一种结构由 lpm 和 stator_lpm 唯一确定。
% 平均值 = 同一结构下所有已有工况推力的 mean(F)。
% 最大差值 = max(F)-min(F)，即绝对意义上的最大推力差；
% 例如 F=-5 和 F=5 的最大差值为 10。
groupID = findgroups(lpm, stator_lpm);
lpm_group = splitapply(@(x) x(1), lpm, groupID);
stator_lpm_group = splitapply(@(x) x(1), stator_lpm, groupID);

nGroup = numel(lpm_group);
force_a_minus10 = nan(nGroup, 1);
force_a0 = nan(nGroup, 1);
force_a10 = nan(nGroup, 1);
average_force = nan(nGroup, 1);
force_max_diff = nan(nGroup, 1);
point_count = zeros(nGroup, 1);
has_a_minus10 = false(nGroup, 1);
has_a0 = false(nGroup, 1);
has_a10 = false(nGroup, 1);

for k = 1:nGroup
    idx = groupID == k;
    a_group = a(idx);
    force_group = force(idx);

    point_count(k) = numel(force_group);

    idx_minus10 = abs(a_group + 10) < 1e-6;
    idx_zero = abs(a_group - 0) < 1e-6;
    idx_plus10 = abs(a_group - 10) < 1e-6;

    has_a_minus10(k) = any(idx_minus10);
    has_a0(k) = any(idx_zero);
    has_a10(k) = any(idx_plus10);

    if has_a_minus10(k)
        force_a_minus10(k) = mean(force_group(idx_minus10));
    end
    if has_a0(k)
        force_a0(k) = mean(force_group(idx_zero));
    end
    if has_a10(k)
        force_a10(k) = mean(force_group(idx_plus10));
    end

    average_force(k) = mean(force_group);
    force_max_diff(k) = max(force_group) - min(force_group);
end

summaryTable = table( ...
    lpm_group, ...
    stator_lpm_group, ...
    force_a_minus10, ...
    force_a0, ...
    force_a10, ...
    average_force, ...
    force_max_diff, ...
    point_count, ...
    has_a_minus10, ...
    has_a0, ...
    has_a10, ...
    'VariableNames', { ...
    'lpm_mm', ...
    'stator_lpm_mm', ...
    'force_a_minus10_N', ...
    'force_a0_N', ...
    'force_a10_N', ...
    'average_force_N', ...
    'force_max_diff_N', ...
    'point_count', ...
    'has_a_minus10', ...
    'has_a0', ...
    'has_a10'});

summaryTable = sortrows(summaryTable, {'lpm_mm', 'stator_lpm_mm'});

fprintf('\n每种结构下的平均值和最大差值：\n');
disp(summaryTable);

writetable(summaryTable, fullfile(outputDir, 'structure_force_summary.xlsx'), ...
    'Sheet', 'summary');

%% 多目标优化：平均值最小，最大差值最大
% 只使用至少包含 minPointCountForOptimization 个工况的结构参与优化。
% Pareto 支配关系：
% A 支配 B，当且仅当 A 的平均值不高于 B，最大差值不低于 B，
% 且至少一个目标严格更优。
optTable = summaryTable(summaryTable.point_count >= minPointCountForOptimization, :);

if isempty(optTable)
    error('没有满足工况点数量要求的结构，无法进行多目标优化。');
end

score_average = normalizeObjective(optTable.average_force_N, 'min');
score_diff = normalizeObjective(optTable.force_max_diff_N, 'max');
compromise_score = (score_average + score_diff) ./ 2;

isPareto = true(height(optTable), 1);
for i = 1:height(optTable)
    for j = 1:height(optTable)
        if i == j
            continue;
        end

        if dominatesSolution( ...
                optTable.average_force_N(j), optTable.force_max_diff_N(j), ...
                optTable.average_force_N(i), optTable.force_max_diff_N(i))
            isPareto(i) = false;
            break;
        end
    end
end

optTable.compromise_score = compromise_score;
optTable.is_pareto = isPareto;

rankedCandidates = sortrows(optTable, ...
    {'compromise_score', 'average_force_N', 'force_max_diff_N'}, ...
    {'descend', 'ascend', 'descend'});

paretoFront = sortrows(optTable(isPareto, :), ...
    {'average_force_N', 'force_max_diff_N'}, ...
    {'ascend', 'descend'});

writetable(rankedCandidates, fullfile(outputDir, 'ranked_candidates.xlsx'), ...
    'Sheet', 'ranked_candidates');
writetable(paretoFront, fullfile(outputDir, 'pareto_front.xlsx'), ...
    'Sheet', 'pareto_front');

%% 输出最佳折中解
bestSolution = rankedCandidates(1, :);

fprintf('\n多目标优化：平均值最小、最大差值最大\n');
fprintf('参与优化的最少工况点数量 = %d\n', minPointCountForOptimization);
fprintf('最佳折中解：lpm = %.3f mm, stator_lpm = %.3f mm\n', ...
    bestSolution.lpm_mm, bestSolution.stator_lpm_mm);
fprintf('平均值 = %.9f N\n', bestSolution.average_force_N);
fprintf('最大差值 = %.9f N\n', bestSolution.force_max_diff_N);
fprintf('综合评分 = %.9f\n', bestSolution.compromise_score);
fprintf('Pareto 解数量 = %d\n', height(paretoFront));
fprintf('\n结果已保存到：%s\n', outputDir);

%% 局部函数
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

function flag = dominatesSolution(avgA, diffA, avgB, diffB)
    noWorse = avgA <= avgB && diffA >= diffB;
    strictlyBetter = avgA < avgB || diffA > diffB;
    flag = noWorse && strictlyBetter;
end
