clear;
clc;
close all;

%% 用户设置
scriptDir = fileparts(mfilename('fullpath'));
dataFile = fullfile(scriptDir, 'F_ADD_LPM.csv');
outputDir = fullfile(scriptDir, 'outputs', 'F_ADD_LPM_avg_maxdiff_optimization');

% 本数据每种结构应包含 4 个位移工况。
expectedA = [-10, -7.5, 0, 10];

if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

%% 数据读取
data = readtable(dataFile, 'VariableNamingRule', 'preserve');

lpm = double(data.('lpm [mm]'));
stator_lpm = double(data.('stator_lpm [mm]'));
a = double(data.('a [mm]'));
force = double(data.('Force_move.Force_z [newton]'));

%% 计算每种结构的平均推力和最大推力差值
% 同一种结构由 lpm 和 stator_lpm 唯一确定。
% 平均推力 = 4 个 a 工况推力的算术平均值。
% 推力波动/最大差值 = max(F)-min(F)，例如 F=-5 和 F=5 的差值为 10。
groupID = findgroups(lpm, stator_lpm);
lpm_group = splitapply(@(x) x(1), lpm, groupID);
stator_lpm_group = splitapply(@(x) x(1), stator_lpm, groupID);

nGroup = numel(lpm_group);
force_a_minus10 = nan(nGroup, 1);
force_a_minus7p5 = nan(nGroup, 1);
force_a0 = nan(nGroup, 1);
force_a10 = nan(nGroup, 1);
average_force = nan(nGroup, 1);
force_ripple = nan(nGroup, 1);
point_count = zeros(nGroup, 1);
is_complete = false(nGroup, 1);

for k = 1:nGroup
    idx = groupID == k;
    a_group = a(idx);
    force_group = force(idx);

    point_count(k) = numel(force_group);

    force_a_minus10(k) = getMeanForceAtA(a_group, force_group, -10);
    force_a_minus7p5(k) = getMeanForceAtA(a_group, force_group, -7.5);
    force_a0(k) = getMeanForceAtA(a_group, force_group, 0);
    force_a10(k) = getMeanForceAtA(a_group, force_group, 10);

    is_complete(k) = all(ismembertol(expectedA, unique(a_group), 1e-6));

    if is_complete(k)
        forceValues = [force_a_minus10(k), force_a_minus7p5(k), force_a0(k), force_a10(k)];
        average_force(k) = mean(forceValues);
        force_ripple(k) = max(forceValues) - min(forceValues);
    else
        average_force(k) = mean(force_group);
        force_ripple(k) = max(force_group) - min(force_group);
    end
end

summaryTable = table( ...
    lpm_group, ...
    stator_lpm_group, ...
    force_a_minus10, ...
    force_a_minus7p5, ...
    force_a0, ...
    force_a10, ...
    average_force, ...
    force_ripple, ...
    point_count, ...
    is_complete, ...
    'VariableNames', { ...
    'lpm_mm', ...
    'stator_lpm_mm', ...
    'force_a_minus10_N', ...
    'force_a_minus7p5_N', ...
    'force_a0_N', ...
    'force_a10_N', ...
    'average_force_N', ...
    'force_ripple_N', ...
    'point_count', ...
    'is_complete'});

summaryTable = sortrows(summaryTable, {'lpm_mm', 'stator_lpm_mm'});

fprintf('\n每种结构下的平均推力和推力波动：\n');
disp(summaryTable);

writetable(summaryTable, fullfile(outputDir, 'structure_force_summary.xlsx'), ...
    'Sheet', 'summary');

%% 多目标优化：平均推力最大，推力波动最小
% 只使用 4 个 a 工况完整的结构参与优化。
optTable = summaryTable(summaryTable.is_complete, :);

if isempty(optTable)
    error('没有完整包含 a=-10, -7.5, 0, 10 mm 四个工况的结构，无法优化。');
end

score_average = normalizeObjective(optTable.average_force_N, 'max');
score_ripple = normalizeObjective(optTable.force_ripple_N, 'min');
compromise_score = (score_average + score_ripple) ./ 2;

isPareto = true(height(optTable), 1);
for i = 1:height(optTable)
    for j = 1:height(optTable)
        if i == j
            continue;
        end

        if dominatesSolution( ...
                optTable.average_force_N(j), optTable.force_ripple_N(j), ...
                optTable.average_force_N(i), optTable.force_ripple_N(i))
            isPareto(i) = false;
            break;
        end
    end
end

optTable.compromise_score = compromise_score;
optTable.is_pareto = isPareto;

rankedCandidates = sortrows(optTable, ...
    {'compromise_score', 'average_force_N', 'force_ripple_N'}, ...
    {'descend', 'descend', 'ascend'});

paretoFront = sortrows(optTable(isPareto, :), ...
    {'average_force_N', 'force_ripple_N'}, ...
    {'descend', 'ascend'});

writetable(rankedCandidates, fullfile(outputDir, 'ranked_candidates.xlsx'), ...
    'Sheet', 'ranked_candidates');
writetable(paretoFront, fullfile(outputDir, 'pareto_front.xlsx'), ...
    'Sheet', 'pareto_front');

%% 输出最佳折中解
bestSolution = rankedCandidates(1, :);

fprintf('\n多目标优化：平均推力最大、推力波动最小\n');
fprintf('最佳折中解：lpm = %.3f mm, stator_lpm = %.3f mm\n', ...
    bestSolution.lpm_mm, bestSolution.stator_lpm_mm);
fprintf('平均推力 = %.9f N\n', bestSolution.average_force_N);
fprintf('推力波动 max(F)-min(F) = %.9f N\n', bestSolution.force_ripple_N);
fprintf('综合评分 = %.9f\n', bestSolution.compromise_score);
fprintf('Pareto 解数量 = %d\n', height(paretoFront));
fprintf('\n结果已保存到：%s\n', outputDir);

%% 局部函数
function forceValue = getMeanForceAtA(aValues, forceValues, targetA)
    idx = abs(aValues - targetA) < 1e-6;
    if any(idx)
        forceValue = mean(forceValues(idx));
    else
        forceValue = nan;
    end
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

function flag = dominatesSolution(avgA, rippleA, avgB, rippleB)
    noWorse = avgA >= avgB && rippleA <= rippleB;
    strictlyBetter = avgA > avgB || rippleA < rippleB;
    flag = noWorse && strictlyBetter;
end
