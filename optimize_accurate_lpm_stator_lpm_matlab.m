clear;
clc;
close all;

%% 用户设置
dataFile = 'accurate_lpm_stator_lpm.csv';
outputDir = fullfile('outputs', 'accurate_lpm_stator_lpm_optimization');

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
% 平均推力 = mean(F)
% 最大推力差值/推力波动 = max(F)-min(F)
groupID = findgroups(lpm, stator_lpm);

lpm_group = splitapply(@(x) x(1), lpm, groupID);
stator_lpm_group = splitapply(@(x) x(1), stator_lpm, groupID);
average_force = splitapply(@mean, force, groupID);
force_ripple = splitapply(@(x) max(x) - min(x), force, groupID);

summaryTable = table( ...
    lpm_group, ...
    stator_lpm_group, ...
    average_force, ...
    force_ripple, ...
    'VariableNames', { ...
    'lpm_mm', ...
    'stator_lpm_mm', ...
    'average_force_N', ...
    'force_ripple_N'});

summaryTable = sortrows(summaryTable, {'lpm_mm', 'stator_lpm_mm'});
writetable(summaryTable, fullfile(outputDir, 'structure_force_summary.xlsx'), ...
    'Sheet', 'summary');

%% 多目标优化 1：两个永磁体长度最小、平均推力最大、推力波动最小
% 四个目标：
% 1) lpm 最小
% 2) stator_lpm 最小
% 3) average_force 最大
% 4) force_ripple 最小
score_lpm = normalizeObjective(summaryTable.lpm_mm, 'min');
score_stator_lpm = normalizeObjective(summaryTable.stator_lpm_mm, 'min');
score_average_1 = normalizeObjective(summaryTable.average_force_N, 'max');
score_ripple_1 = normalizeObjective(summaryTable.force_ripple_N, 'min');
score_mode1 = (score_lpm + score_stator_lpm + score_average_1 + score_ripple_1) ./ 4;

isParetoMode1 = true(height(summaryTable), 1);
for i = 1:height(summaryTable)
    for j = 1:height(summaryTable)
        if i == j
            continue;
        end

        if dominatesMode1( ...
                summaryTable.lpm_mm(j), summaryTable.stator_lpm_mm(j), ...
                summaryTable.average_force_N(j), summaryTable.force_ripple_N(j), ...
                summaryTable.lpm_mm(i), summaryTable.stator_lpm_mm(i), ...
                summaryTable.average_force_N(i), summaryTable.force_ripple_N(i))
            isParetoMode1(i) = false;
            break;
        end
    end
end

optimizationMode1 = summaryTable;
optimizationMode1.compromise_score = score_mode1;
optimizationMode1.is_pareto = isParetoMode1;

rankedMode1 = sortrows(optimizationMode1, ...
    {'compromise_score', 'lpm_mm', 'stator_lpm_mm', 'average_force_N', 'force_ripple_N'}, ...
    {'descend', 'ascend', 'ascend', 'descend', 'ascend'});
paretoMode1 = sortrows(optimizationMode1(isParetoMode1, :), ...
    {'lpm_mm', 'stator_lpm_mm', 'average_force_N', 'force_ripple_N'}, ...
    {'ascend', 'ascend', 'descend', 'ascend'});

writetable(rankedMode1, fullfile(outputDir, 'ranked_mode1_length_avg_ripple.xlsx'), ...
    'Sheet', 'ranked_mode1');
writetable(paretoMode1, fullfile(outputDir, 'pareto_mode1_length_avg_ripple.xlsx'), ...
    'Sheet', 'pareto_mode1');

%% 多目标优化 2：平均推力最大、推力波动最小
% 两个目标：
% 1) average_force 最大
% 2) force_ripple 最小
score_average_2 = normalizeObjective(summaryTable.average_force_N, 'max');
score_ripple_2 = normalizeObjective(summaryTable.force_ripple_N, 'min');
score_mode2 = (score_average_2 + score_ripple_2) ./ 2;

isParetoMode2 = true(height(summaryTable), 1);
for i = 1:height(summaryTable)
    for j = 1:height(summaryTable)
        if i == j
            continue;
        end

        if dominatesMode2( ...
                summaryTable.average_force_N(j), summaryTable.force_ripple_N(j), ...
                summaryTable.average_force_N(i), summaryTable.force_ripple_N(i))
            isParetoMode2(i) = false;
            break;
        end
    end
end

optimizationMode2 = summaryTable;
optimizationMode2.compromise_score = score_mode2;
optimizationMode2.is_pareto = isParetoMode2;

rankedMode2 = sortrows(optimizationMode2, ...
    {'compromise_score', 'average_force_N', 'force_ripple_N'}, ...
    {'descend', 'descend', 'ascend'});
paretoMode2 = sortrows(optimizationMode2(isParetoMode2, :), ...
    {'average_force_N', 'force_ripple_N'}, ...
    {'descend', 'ascend'});

writetable(rankedMode2, fullfile(outputDir, 'ranked_mode2_avg_ripple.xlsx'), ...
    'Sheet', 'ranked_mode2');
writetable(paretoMode2, fullfile(outputDir, 'pareto_mode2_avg_ripple.xlsx'), ...
    'Sheet', 'pareto_mode2');

%% 命令行输出最佳折中解
bestMode1 = rankedMode1(1, :);
bestMode2 = rankedMode2(1, :);

fprintf('\n优化目标 1：两个永磁体长度最小、平均推力最大、推力波动最小\n');
fprintf('最佳折中解：lpm = %.3f mm, stator_lpm = %.3f mm\n', ...
    bestMode1.lpm_mm, bestMode1.stator_lpm_mm);
fprintf('平均推力 = %.9f N\n', bestMode1.average_force_N);
fprintf('最大推力差值 = %.9f N\n', bestMode1.force_ripple_N);
fprintf('综合评分 = %.9f\n', bestMode1.compromise_score);
fprintf('Pareto 解数量 = %d\n', height(paretoMode1));

fprintf('\n优化目标 2：平均推力最大、推力波动最小\n');
fprintf('最佳折中解：lpm = %.3f mm, stator_lpm = %.3f mm\n', ...
    bestMode2.lpm_mm, bestMode2.stator_lpm_mm);
fprintf('平均推力 = %.9f N\n', bestMode2.average_force_N);
fprintf('最大推力差值 = %.9f N\n', bestMode2.force_ripple_N);
fprintf('综合评分 = %.9f\n', bestMode2.compromise_score);
fprintf('Pareto 解数量 = %d\n', height(paretoMode2));

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

function flag = dominatesMode1(lpmA, statorA, avgA, rippleA, lpmB, statorB, avgB, rippleB)
    noWorse = lpmA <= lpmB ...
        && statorA <= statorB ...
        && avgA >= avgB ...
        && rippleA <= rippleB;
    strictlyBetter = lpmA < lpmB ...
        || statorA < statorB ...
        || avgA > avgB ...
        || rippleA < rippleB;
    flag = noWorse && strictlyBetter;
end

function flag = dominatesMode2(avgA, rippleA, avgB, rippleB)
    noWorse = avgA >= avgB && rippleA <= rippleB;
    strictlyBetter = avgA > avgB || rippleA < rippleB;
    flag = noWorse && strictlyBetter;
end
