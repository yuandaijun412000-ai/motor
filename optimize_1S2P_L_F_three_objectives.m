clear;
clc;
close all;

%% 用户设置
dataFile = '1S2P_L_F.csv';
outputDir = fullfile('outputs', '1S2P_L_F_three_objective_optimization');

% 永磁体长度目标设置：
% 'lout_plus_lpm'  : 永磁体长度目标 = lout + lpm
% 'lout_plus_2lpm' : 永磁体长度目标 = lout + 2*lpm
% 'lout_only'      : 永磁体长度目标 = lout
% 'lpm_only'       : 永磁体长度目标 = lpm
pmLengthMode = 'lout_plus_lpm';

if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

%% 数据读取
data = readtable(dataFile, 'VariableNamingRule', 'preserve');

lout = double(data.('lout [mm]'));
lpm = double(data.('lpm [mm]'));
lpmspace = double(data.('lpmspace [mm]'));
force = double(data.('Force_pm.Force_z [newton]'));

%% 计算每种结构的平均推力和推力波动
% 同一种结构由 lout、lpm、lpmspace 唯一确定。
% 平均推力 = mean(F)
% 推力波动 = max(F)-min(F)
groupID = findgroups(lout, lpm, lpmspace);

lout_group = splitapply(@(x) x(1), lout, groupID);
lpm_group = splitapply(@(x) x(1), lpm, groupID);
lpmspace_group = splitapply(@(x) x(1), lpmspace, groupID);
average_force = splitapply(@mean, force, groupID);
force_ripple = splitapply(@(x) max(x) - min(x), force, groupID);

summaryTable = table( ...
    lout_group, ...
    lpm_group, ...
    lpmspace_group, ...
    average_force, ...
    force_ripple, ...
    'VariableNames', { ...
    'lout_mm', ...
    'lpm_mm', ...
    'lpmspace_mm', ...
    'average_force_N', ...
    'force_ripple_N'});

summaryTable = sortrows(summaryTable, {'lout_mm', 'lpm_mm', 'lpmspace_mm'});

%% 三目标多目标优化
% 目标 1：永磁体长度最小
% 目标 2：平均推力最大
% 目标 3：推力波动最小
pm_length_objective = calcPmLengthObjective(summaryTable, pmLengthMode);

score_length = normalizeObjective(pm_length_objective, 'min');
score_average_force = normalizeObjective(summaryTable.average_force_N, 'max');
score_ripple = normalizeObjective(summaryTable.force_ripple_N, 'min');
compromise_score = (score_length + score_average_force + score_ripple) ./ 3;

isPareto = true(height(summaryTable), 1);
for i = 1:height(summaryTable)
    for j = 1:height(summaryTable)
        if i == j
            continue;
        end

        if dominatesSolution( ...
                pm_length_objective(j), summaryTable.average_force_N(j), summaryTable.force_ripple_N(j), ...
                pm_length_objective(i), summaryTable.average_force_N(i), summaryTable.force_ripple_N(i))
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
    {'compromise_score', 'pm_length_objective_mm', 'average_force_N', 'force_ripple_N'}, ...
    {'descend', 'ascend', 'descend', 'ascend'});

paretoFront = sortrows(optimizationTable(isPareto, :), ...
    {'pm_length_objective_mm', 'average_force_N', 'force_ripple_N'}, ...
    {'ascend', 'descend', 'ascend'});

%% 保存结果
writetable(summaryTable, fullfile(outputDir, 'structure_force_summary.xlsx'), ...
    'Sheet', 'summary');
writetable(rankedCandidates, fullfile(outputDir, 'ranked_candidates.xlsx'), ...
    'Sheet', 'ranked_candidates');
writetable(paretoFront, fullfile(outputDir, 'pareto_front.xlsx'), ...
    'Sheet', 'pareto_front');

bestSolution = rankedCandidates(1, :);

fprintf('\n三目标优化最佳折中解：\n');
fprintf('lout = %.0f mm\n', bestSolution.lout_mm);
fprintf('lpm = %.0f mm\n', bestSolution.lpm_mm);
fprintf('lpmspace = %.0f mm\n', bestSolution.lpmspace_mm);
fprintf('永磁体长度目标 = %.9f mm\n', bestSolution.pm_length_objective_mm);
fprintf('平均推力 = %.9f N\n', bestSolution.average_force_N);
fprintf('推力波动 max(F)-min(F) = %.9f N\n', bestSolution.force_ripple_N);
fprintf('综合评分 = %.9f\n', bestSolution.compromise_score);
fprintf('Pareto 解数量 = %d\n', height(paretoFront));
fprintf('\n结果已保存到：%s\n', outputDir);

%% 局部函数
function pmLength = calcPmLengthObjective(summaryTable, mode)
    switch mode
        case 'lout_plus_lpm'
            pmLength = summaryTable.lout_mm + summaryTable.lpm_mm;
        case 'lout_plus_2lpm'
            pmLength = summaryTable.lout_mm + 2 .* summaryTable.lpm_mm;
        case 'lout_only'
            pmLength = summaryTable.lout_mm;
        case 'lpm_only'
            pmLength = summaryTable.lpm_mm;
        otherwise
            error('未知永磁体长度目标模式：%s', mode);
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

function flag = dominatesSolution(lengthA, avgA, rippleA, lengthB, avgB, rippleB)
    noWorse = lengthA <= lengthB && avgA >= avgB && rippleA <= rippleB;
    strictlyBetter = lengthA < lengthB || avgA > avgB || rippleA < rippleB;
    flag = noWorse && strictlyBetter;
end
