clear;
clc;
close all;

%% 用户设置
scriptDir = fileparts(mfilename('fullpath'));
dataFile = fullfile(scriptDir, 'F_ADD_LPM_CPM1.csv');
outputDir = fullfile(scriptDir, 'outputs', 'F_ADD_LPM_CPM1_clean_optimization');

% 本数据按 a=-10 mm 和 a=0 mm 两个工况计算平均推力和推力波动。
requiredA = [-10, 0];

if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

%% 数据读取
data = readtable(dataFile, 'VariableNamingRule', 'preserve');

lpm = double(data.('lpm [mm]'));
stator_lpm = double(data.('stator_lpm [mm]'));
a = double(data.('a [mm]'));
force = double(data.('Force_move.Force_z [newton]'));

%% 计算每种结构的平均推力和最大差值
% 同一种结构由 lpm 和 stator_lpm 唯一确定。
% 完整结构：同时存在 a=-10 mm 和 a=0 mm。
% 平均推力 = (F(a=-10)+F(a=0))/2
% 推力波动/最大差值 = abs(F(a=0)-F(a=-10))
% 若某结构缺少其中一个 a 工况，则写入 summary 表，但不参与优化。
groupID = findgroups(lpm, stator_lpm);
lpm_group = splitapply(@(x) x(1), lpm, groupID);
stator_lpm_group = splitapply(@(x) x(1), stator_lpm, groupID);

nGroup = numel(lpm_group);
force_a_minus10 = nan(nGroup, 1);
force_a0 = nan(nGroup, 1);
average_force = nan(nGroup, 1);
force_ripple = nan(nGroup, 1);
has_a_minus10 = false(nGroup, 1);
has_a0 = false(nGroup, 1);
point_count = zeros(nGroup, 1);

for k = 1:nGroup
    idx = groupID == k;
    a_group = a(idx);
    force_group = force(idx);
    point_count(k) = numel(force_group);

    idx_minus10 = abs(a_group - requiredA(1)) < 1e-6;
    idx_zero = abs(a_group - requiredA(2)) < 1e-6;

    has_a_minus10(k) = any(idx_minus10);
    has_a0(k) = any(idx_zero);

    if has_a_minus10(k)
        force_a_minus10(k) = mean(force_group(idx_minus10));
    end
    if has_a0(k)
        force_a0(k) = mean(force_group(idx_zero));
    end

    if has_a_minus10(k) && has_a0(k)
        average_force(k) = (force_a_minus10(k) + force_a0(k)) / 2;
        force_ripple(k) = abs(force_a0(k) - force_a_minus10(k));
    end
end

is_complete_pair = has_a_minus10 & has_a0;

summaryTable = table( ...
    lpm_group, ...
    stator_lpm_group, ...
    force_a_minus10, ...
    force_a0, ...
    average_force, ...
    force_ripple, ...
    has_a_minus10, ...
    has_a0, ...
    point_count, ...
    is_complete_pair, ...
    'VariableNames', { ...
    'lpm_mm', ...
    'stator_lpm_mm', ...
    'force_a_minus10_N', ...
    'force_a0_N', ...
    'average_force_N', ...
    'force_ripple_N', ...
    'has_a_minus10', ...
    'has_a0', ...
    'point_count', ...
    'is_complete_pair'});

summaryTable = sortrows(summaryTable, {'lpm_mm', 'stator_lpm_mm'});
writetable(summaryTable, fullfile(outputDir, 'structure_force_summary.xlsx'), ...
    'Sheet', 'summary');

fprintf('\n每种结构下的平均推力和推力波动：\n');
disp(summaryTable);

%% 多目标优化：平均推力最大，推力波动最小
% 只用完整结构参与优化，避免单工况结构因波动为 0 而误导结果。
optTable = summaryTable(summaryTable.is_complete_pair, :);

if isempty(optTable)
    error('没有同时包含 a=-10 mm 和 a=0 mm 的完整结构，无法进行多目标优化。');
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
fprintf('F(a=-10) = %.9f N\n', bestSolution.force_a_minus10_N);
fprintf('F(a=0) = %.9f N\n', bestSolution.force_a0_N);
fprintf('平均推力 = %.9f N\n', bestSolution.average_force_N);
fprintf('推力波动 = %.9f N\n', bestSolution.force_ripple_N);
fprintf('综合评分 = %.9f\n', bestSolution.compromise_score);
fprintf('Pareto 解数量 = %d\n', height(paretoFront));
fprintf('\n结构汇总和优化结果已保存到：%s\n', outputDir);

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

function flag = dominatesSolution(avgA, rippleA, avgB, rippleB)
    noWorse = avgA >= avgB && rippleA <= rippleB;
    strictlyBetter = avgA > avgB || rippleA < rippleB;
    flag = noWorse && strictlyBetter;
end
