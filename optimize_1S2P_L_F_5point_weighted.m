clear;
clc;
close all;

%% 用户设置
scriptDir = fileparts(mfilename('fullpath'));
dataFile = fullfile(scriptDir, '1S2P_L_F.csv');
outputDir = fullfile(scriptDir, 'outputs', '1S2P_L_F_5point_weighted_optimization');

% 五个位移工况
expectedA = [-10, -5, 0, 5, 10];

% 三个优化目标的权重，可手动调节。
% 目标 1：平均推力最大
% 目标 2：推力波动最小
% 目标 3：lpm 最小
weight_average_force = 0.40;
weight_force_ripple = 0.40;
weight_lpm = 0.2;

% 如果权重和不等于 1，代码会自动归一化。
weightSum = weight_average_force + weight_force_ripple + weight_lpm;
weight_average_force = weight_average_force / weightSum;
weight_force_ripple = weight_force_ripple / weightSum;
weight_lpm = weight_lpm / weightSum;

if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

%% 数据读取
data = readtable(dataFile, 'VariableNamingRule', 'preserve');

lout = double(data.('lout [mm]'));
lpm = double(data.('lpm [mm]'));
lpmspace = double(data.('lpmspace [mm]'));
a = double(data.('a [mm]'));
force = double(data.('Force_PM.Force_z [newton]'));

%% 计算每种结构下 5 个点的平均推力和推力波动
% 同一种结构由 lout、lpm、lpmspace 唯一确定。
% 平均推力 = mean(F(-10), F(-5), F(0), F(5), F(10))
% 推力波动 = max(F)-min(F)
groupID = findgroups(lout, lpm, lpmspace);
lout_group = splitapply(@(x) x(1), lout, groupID);
lpm_group = splitapply(@(x) x(1), lpm, groupID);
lpmspace_group = splitapply(@(x) x(1), lpmspace, groupID);

nGroup = numel(lout_group);
forceMatrix = nan(nGroup, numel(expectedA));
average_force = nan(nGroup, 1);
force_ripple = nan(nGroup, 1);
point_count = zeros(nGroup, 1);
is_complete = false(nGroup, 1);

for k = 1:nGroup
    idx = groupID == k;
    a_group = a(idx);
    force_group = force(idx);
    point_count(k) = numel(force_group);

    for j = 1:numel(expectedA)
        targetA = expectedA(j);
        idxA = abs(a_group - targetA) < 1e-6;
        if any(idxA)
            forceMatrix(k, j) = mean(force_group(idxA));
        end
    end

    is_complete(k) = all(~isnan(forceMatrix(k, :)));

    if is_complete(k)
        average_force(k) = mean(forceMatrix(k, :));
        force_ripple(k) = max(forceMatrix(k, :)) - min(forceMatrix(k, :));
    else
        average_force(k) = mean(force_group);
        force_ripple(k) = max(force_group) - min(force_group);
    end
end

summaryTable = table( ...
    lout_group, ...
    lpm_group, ...
    lpmspace_group, ...
    forceMatrix(:, 1), ...
    forceMatrix(:, 2), ...
    forceMatrix(:, 3), ...
    forceMatrix(:, 4), ...
    forceMatrix(:, 5), ...
    average_force, ...
    force_ripple, ...
    point_count, ...
    is_complete, ...
    'VariableNames', { ...
    'lout_mm', ...
    'lpm_mm', ...
    'lpmspace_mm', ...
    'force_a_minus10_N', ...
    'force_a_minus5_N', ...
    'force_a0_N', ...
    'force_a5_N', ...
    'force_a10_N', ...
    'average_force_N', ...
    'force_ripple_N', ...
    'point_count', ...
    'is_complete'});

summaryTable = sortrows(summaryTable, {'lout_mm', 'lpm_mm', 'lpmspace_mm'});

fprintf('\n每种结构下 5 个点的平均推力和推力波动：\n');
disp(summaryTable);

writetable(summaryTable, fullfile(outputDir, 'structure_force_summary.xlsx'), ...
    'Sheet', 'summary');

%% 多目标优化：平均推力最大、推力波动最小、lpm 最小
% Pareto 前沿使用三目标支配关系。
% 综合评分使用可调权重：
% score = w1*平均推力归一化得分 + w2*波动归一化得分 + w3*lpm归一化得分
optTable = summaryTable(summaryTable.is_complete, :);

if isempty(optTable)
    error('没有完整包含 5 个 a 工况的结构，无法进行优化。');
end

score_average = normalizeObjective(optTable.average_force_N, 'max');
score_ripple = normalizeObjective(optTable.force_ripple_N, 'min');
score_lpm = normalizeObjective(optTable.lpm_mm, 'min');

weighted_score = weight_average_force .* score_average ...
    + weight_force_ripple .* score_ripple ...
    + weight_lpm .* score_lpm;

isPareto = true(height(optTable), 1);
for i = 1:height(optTable)
    for j = 1:height(optTable)
        if i == j
            continue;
        end

        if dominatesSolution( ...
                optTable.average_force_N(j), optTable.force_ripple_N(j), optTable.lpm_mm(j), ...
                optTable.average_force_N(i), optTable.force_ripple_N(i), optTable.lpm_mm(i))
            isPareto(i) = false;
            break;
        end
    end
end

optTable.weighted_score = weighted_score;
optTable.is_pareto = isPareto;
optTable.weight_average_force = repmat(weight_average_force, height(optTable), 1);
optTable.weight_force_ripple = repmat(weight_force_ripple, height(optTable), 1);
optTable.weight_lpm = repmat(weight_lpm, height(optTable), 1);

rankedCandidates = sortrows(optTable, ...
    {'weighted_score', 'average_force_N', 'force_ripple_N', 'lpm_mm'}, ...
    {'descend', 'descend', 'ascend', 'ascend'});

paretoFront = sortrows(optTable(isPareto, :), ...
    {'average_force_N', 'force_ripple_N', 'lpm_mm'}, ...
    {'descend', 'ascend', 'ascend'});

writetable(rankedCandidates, fullfile(outputDir, 'ranked_candidates.xlsx'), ...
    'Sheet', 'ranked_candidates');
writetable(paretoFront, fullfile(outputDir, 'pareto_front.xlsx'), ...
    'Sheet', 'pareto_front');

%% 输出最佳加权折中解
bestSolution = rankedCandidates(1, :);

fprintf('\n三目标优化：平均推力最大、推力波动最小、lpm 最小\n');
fprintf('当前权重：平均推力 %.3f，推力波动 %.3f，lpm %.3f\n', ...
    weight_average_force, weight_force_ripple, weight_lpm);
fprintf('最佳加权折中解：lout = %.3f mm, lpm = %.3f mm, lpmspace = %.3f mm\n', ...
    bestSolution.lout_mm, bestSolution.lpm_mm, bestSolution.lpmspace_mm);
fprintf('平均推力 = %.9f N\n', bestSolution.average_force_N);
fprintf('推力波动 = %.9f N\n', bestSolution.force_ripple_N);
fprintf('加权评分 = %.9f\n', bestSolution.weighted_score);
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

function flag = dominatesSolution(avgA, rippleA, lpmA, avgB, rippleB, lpmB)
    noWorse = avgA >= avgB && rippleA <= rippleB && lpmA <= lpmB;
    strictlyBetter = avgA > avgB || rippleA < rippleB || lpmA < lpmB;
    flag = noWorse && strictlyBetter;
end
