clear;
clc;
close all;

%% 用户设置
dataFile = '1S2P_L_F.csv';
outputDir = fullfile('outputs', '1S2P_L_F_full_analysis');
figureDir = fullfile(outputDir, 'figures');

% 三个位移工况。若后续数据的位移点改变，只需要改这里。
aTargets = [-10, 0, 10];

% 永磁体长度目标设置：
% 'lout_plus_lpm'  : 永磁体长度目标 = lout + lpm
% 'lout_plus_2lpm' : 永磁体长度目标 = lout + 2*lpm
% 'lout_only'      : 永磁体长度目标 = lout
% 'lpm_only'       : 永磁体长度目标 = lpm
pmLengthMode = 'lout_plus_lpm';

if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end
if ~exist(figureDir, 'dir')
    mkdir(figureDir);
end

%% 数据读取
data = readtable(dataFile, 'VariableNamingRule', 'preserve');

lout = double(data.('lout [mm]'));
lpm = double(data.('lpm [mm]'));
lpmspace = double(data.('lpmspace [mm]'));
a = double(data.('a [mm]'));
force = double(data.('Force_pm.Force_z [newton]'));

%% 计算每种结构的平均推力和最大推力差值
% 同一种结构由 lout、lpm、lpmspace 唯一确定。
% 平均推力只使用 a=-10、0、+10 mm 三个工况：
%     F_avg = mean([F(-10), F(0), F(10)])
% 最大推力差值取绝对意义上的最大差值：
%     F_ripple = max(F)-min(F)
% 例如 F=-5 和 F=5 的差值为 10。
groupID = findgroups(lout, lpm, lpmspace);

lout_group = splitapply(@(x) x(1), lout, groupID);
lpm_group = splitapply(@(x) x(1), lpm, groupID);
lpmspace_group = splitapply(@(x) x(1), lpmspace, groupID);

force_a_minus10 = splitapply(@(aa, ff) getForceAtA(aa, ff, aTargets(1)), a, force, groupID);
force_a0 = splitapply(@(aa, ff) getForceAtA(aa, ff, aTargets(2)), a, force, groupID);
force_a10 = splitapply(@(aa, ff) getForceAtA(aa, ff, aTargets(3)), a, force, groupID);

forceMatrix = [force_a_minus10, force_a0, force_a10];
average_force = mean(forceMatrix, 2);
force_ripple = max(forceMatrix, [], 2) - min(forceMatrix, [], 2);

summaryTable = table( ...
    lout_group, ...
    lpm_group, ...
    lpmspace_group, ...
    force_a_minus10, ...
    force_a0, ...
    force_a10, ...
    average_force, ...
    force_ripple, ...
    'VariableNames', { ...
    'lout_mm', ...
    'lpm_mm', ...
    'lpmspace_mm', ...
    'force_a_minus10_N', ...
    'force_a0_N', ...
    'force_a10_N', ...
    'average_force_N', ...
    'force_ripple_N'});

summaryTable = sortrows(summaryTable, {'lout_mm', 'lpm_mm', 'lpmspace_mm'});
writetable(summaryTable, fullfile(outputDir, 'structure_force_summary.xlsx'), ...
    'Sheet', 'summary');

%% 三维画图：3 个变量选 2 个，2 个结果选 1 个，画出所有组合
% 结构变量：lout、lpm、lpmspace
% 结果变量：平均推力、推力波动
% 对任意两个结构变量作 x/y 轴，剩下的第三个变量按每个取值固定切片。
structureVars = {'lout_mm', 'lpm_mm', 'lpmspace_mm'};
resultVars = {'average_force_N', 'force_ripple_N'};

plotCount = 0;
for ix = 1:numel(structureVars)-1
    for iy = ix+1:numel(structureVars)
        xVar = structureVars{ix};
        yVar = structureVars{iy};
        fixedVar = structureVars{~ismember(1:numel(structureVars), [ix, iy])};
        fixedValues = unique(summaryTable.(fixedVar));

        for iz = 1:numel(resultVars)
            zResult = resultVars{iz};

            for iv = 1:numel(fixedValues)
                fixedValue = fixedValues(iv);
                plotTable = summaryTable(abs(summaryTable.(fixedVar) - fixedValue) < 1e-9, :);
                if isempty(plotTable)
                    continue;
                end

                xList = unique(plotTable.(xVar));
                yList = unique(plotTable.(yVar));
                [XGrid, YGrid] = meshgrid(xList, yList);
                ZGrid = nan(size(XGrid));

                for i = 1:height(plotTable)
                    rowIndex = find(yList == plotTable.(yVar)(i), 1);
                    colIndex = find(xList == plotTable.(xVar)(i), 1);
                    ZGrid(rowIndex, colIndex) = plotTable.(zResult)(i);
                end

                plotCount = plotCount + 1;
                fig = figure('Color', 'w');
                surf(XGrid, YGrid, ZGrid, ...
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

                xlabel(getAxisLabel(xVar), 'FontSize', 12, 'Interpreter', 'tex');
                ylabel(getAxisLabel(yVar), 'FontSize', 12, 'Interpreter', 'tex');
                zlabel(getResultLabel(zResult), 'FontSize', 12, 'Interpreter', 'tex');

                fixedText = sprintf('%s = %.0f mm', getPlainName(fixedVar), fixedValue);
                text(0.02, 0.96, fixedText, ...
                    'Units', 'normalized', ...
                    'FontName', 'Times New Roman', ...
                    'FontSize', 12);

                set(fig, 'Units', 'centimeters', 'Position', [10, 5, 11, 8]);

                fileStem = sprintf('%02d_%s_%s_fixed_%s_%g_%s', ...
                    plotCount, xVar, yVar, fixedVar, fixedValue, zResult);
                fileStem = regexprep(fileStem, '[^\w.-]', '_');
                savefig(fig, fullfile(figureDir, [fileStem, '.fig']));
                print(fig, fullfile(figureDir, [fileStem, '.png']), '-dpng', '-r600');
            end
        end
    end
end

%% 多目标优化 1：永磁体长度最小、平均推力最大、推力波动最小
% 三个目标：
% 1) 永磁体长度目标最小
% 2) 平均推力最大
% 3) 推力波动最小
pm_length_objective = calcPmLengthObjective(summaryTable, pmLengthMode);

score_length = normalizeObjective(pm_length_objective, 'min');
score_average_1 = normalizeObjective(summaryTable.average_force_N, 'max');
score_ripple_1 = normalizeObjective(summaryTable.force_ripple_N, 'min');
score_mode1 = (score_length + score_average_1 + score_ripple_1) ./ 3;

isParetoMode1 = true(height(summaryTable), 1);
for i = 1:height(summaryTable)
    for j = 1:height(summaryTable)
        if i == j
            continue;
        end

        if dominatesMode1( ...
                pm_length_objective(j), summaryTable.average_force_N(j), summaryTable.force_ripple_N(j), ...
                pm_length_objective(i), summaryTable.average_force_N(i), summaryTable.force_ripple_N(i))
            isParetoMode1(i) = false;
            break;
        end
    end
end

optimizationMode1 = summaryTable;
optimizationMode1.pm_length_objective_mm = pm_length_objective;
optimizationMode1.compromise_score = score_mode1;
optimizationMode1.is_pareto = isParetoMode1;

rankedMode1 = sortrows(optimizationMode1, ...
    {'compromise_score', 'pm_length_objective_mm', 'average_force_N', 'force_ripple_N'}, ...
    {'descend', 'ascend', 'descend', 'ascend'});
paretoMode1 = sortrows(optimizationMode1(isParetoMode1, :), ...
    {'pm_length_objective_mm', 'average_force_N', 'force_ripple_N'}, ...
    {'ascend', 'descend', 'ascend'});

writetable(rankedMode1, fullfile(outputDir, 'ranked_mode1_length_avg_ripple.xlsx'), ...
    'Sheet', 'ranked_mode1');
writetable(paretoMode1, fullfile(outputDir, 'pareto_mode1_length_avg_ripple.xlsx'), ...
    'Sheet', 'pareto_mode1');

%% 多目标优化 2：平均推力最大、推力波动最小
% 两个目标：
% 1) 平均推力最大
% 2) 推力波动最小
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

fprintf('\n优化模式 1：永磁体长度最小、平均推力最大、推力波动最小\n');
fprintf('最佳折中解：lout = %.0f mm, lpm = %.0f mm, lpmspace = %.0f mm\n', ...
    bestMode1.lout_mm, bestMode1.lpm_mm, bestMode1.lpmspace_mm);
fprintf('永磁体长度目标 = %.9f mm\n', bestMode1.pm_length_objective_mm);
fprintf('平均推力 = %.9f N\n', bestMode1.average_force_N);
fprintf('推力波动 = %.9f N\n', bestMode1.force_ripple_N);
fprintf('综合评分 = %.9f\n', bestMode1.compromise_score);
fprintf('Pareto 解数量 = %d\n', height(paretoMode1));

fprintf('\n优化模式 2：平均推力最大、推力波动最小\n');
fprintf('最佳折中解：lout = %.0f mm, lpm = %.0f mm, lpmspace = %.0f mm\n', ...
    bestMode2.lout_mm, bestMode2.lpm_mm, bestMode2.lpmspace_mm);
fprintf('平均推力 = %.9f N\n', bestMode2.average_force_N);
fprintf('推力波动 = %.9f N\n', bestMode2.force_ripple_N);
fprintf('综合评分 = %.9f\n', bestMode2.compromise_score);
fprintf('Pareto 解数量 = %d\n', height(paretoMode2));

fprintf('\n结构汇总与优化结果已保存到：%s\n', outputDir);
fprintf('三维图数量 = %d\n', plotCount);
fprintf('三维图已保存到：%s\n', figureDir);

%% 局部函数
function forceValue = getForceAtA(aValues, forceValues, targetA)
    index = abs(aValues - targetA) < 1e-9;
    if sum(index) ~= 1
        error('某一组结构下未找到唯一的 a=%.6g mm 工况。', targetA);
    end
    forceValue = forceValues(index);
end

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

function flag = dominatesMode1(lengthA, avgA, rippleA, lengthB, avgB, rippleB)
    noWorse = lengthA <= lengthB && avgA >= avgB && rippleA <= rippleB;
    strictlyBetter = lengthA < lengthB || avgA > avgB || rippleA < rippleB;
    flag = noWorse && strictlyBetter;
end

function flag = dominatesMode2(avgA, rippleA, avgB, rippleB)
    noWorse = avgA >= avgB && rippleA <= rippleB;
    strictlyBetter = avgA > avgB || rippleA < rippleB;
    flag = noWorse && strictlyBetter;
end

function labelText = getAxisLabel(varName)
    switch varName
        case 'lout_mm'
            labelText = '\fontname{SimSun}定子侧永磁体总长 \fontname{Times New Roman}\itl_{\rm out}\rm (mm)';
        case 'lpm_mm'
            labelText = '\fontname{SimSun}动子侧永磁体长度 \fontname{Times New Roman}\itl_{\rm pm}\rm (mm)';
        case 'lpmspace_mm'
            labelText = '\fontname{SimSun}永磁体间距 \fontname{Times New Roman}\itl_{\rm pmspace}\rm (mm)';
        otherwise
            error('未知坐标变量：%s', varName);
    end
end

function labelText = getResultLabel(resultName)
    switch resultName
        case 'average_force_N'
            labelText = '\fontname{SimSun}平均推力 \fontname{Times New Roman}\itF_{\rm avg}\rm (N)';
        case 'force_ripple_N'
            labelText = '\fontname{SimSun}推力波动 \fontname{Times New Roman}\Delta\itF_{\rm e}\rm (N)';
        otherwise
            error('未知结果变量：%s', resultName);
    end
end

function plainName = getPlainName(varName)
    switch varName
        case 'lout_mm'
            plainName = 'lout';
        case 'lpm_mm'
            plainName = 'lpm';
        case 'lpmspace_mm'
            plainName = 'lpmspace';
        otherwise
            plainName = varName;
    end
end
