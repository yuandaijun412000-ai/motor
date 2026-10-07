clear;
clc;
close all;

%% 用户设置
dataFile = '1S2P_L_F.csv';
outputDir = fullfile('outputs', '1S2P_L_F_matlab_analysis');

% 三维图会自动画出所有组合：
% 结构变量三选二：lout/lpm、lout/lpmspace、lpm/lpmspace；
% 结果变量二选一：平均推力、推力波动；
% 剩余的第三个结构变量按每个取值分别固定切片绘图。
structureVars = {'lout_mm', 'lpm_mm', 'lpmspace_mm'};
resultVars = {'average_force_N', 'force_ripple_N'};

% 永磁体长度目标设置：
% 'lout_plus_lpm'      : 永磁体长度目标 = lout + lpm
% 'lout_plus_2lpm'     : 永磁体长度目标 = lout + 2*lpm
% 'lout_only'          : 永磁体长度目标 = lout
% 'lpm_only'           : 永磁体长度目标 = lpm
pmLengthMode = 'lout_plus_lpm';

if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

%% 数据读取
data = readtable(dataFile, 'VariableNamingRule', 'preserve');

lout = double(data.('lout [mm]'));
lpm = double(data.('lpm [mm]'));
lpmspace = double(data.('lpmspace [mm]'));
a = double(data.('a [mm]'));
force = double(data.('Force_pm.Force_z [newton]'));

%% 计算每种结构的平均推力和最大推力差值
% 同一种结构由 lout、lpm、lpmspace 唯一确定；
% 平均推力 = 该结构所有 a 工况下推力的算术平均值；
% 推力波动/最大推力差值 = max(F)-min(F)。
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
writetable(summaryTable, fullfile(outputDir, 'structure_force_summary.xlsx'), ...
    'Sheet', 'summary');

%% 三维关系图：自动画出所有变量组合与结果组合
figureDir = fullfile(outputDir, 'figures');
if ~exist(figureDir, 'dir')
    mkdir(figureDir);
end

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
                figure('Color', 'w');
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

                set(gcf, 'Units', 'centimeters', 'Position', [10, 5, 11, 8]);

                fileStem = sprintf('%02d_%s_%s_fixed_%s_%g_%s', ...
                    plotCount, xVar, yVar, fixedVar, fixedValue, zResult);
                fileStem = regexprep(fileStem, '[^\w.-]', '_');
                savefig(gcf, fullfile(figureDir, [fileStem, '.fig']));
                print(gcf, fullfile(figureDir, [fileStem, '.png']), ...
                    '-dpng', '-r600');
            end
        end
    end
end

%% 多目标优化：永磁体长度最小、平均推力最大、推力波动最小
% 采用两种输出：
% 1. Pareto 前沿：不存在另一个结构在永磁体长度不大、平均推力不低、
%    推力波动不高的同时至少一项更优；
% 2. 综合评分推荐：永磁体长度越小越好，平均推力越大越好，
%    推力波动越小越好，三者等权。
pm_length_objective = calcPmLengthObjective(summaryTable, pmLengthMode);

score_length = normalizeObjective(pm_length_objective, 'min');
score_average = normalizeObjective(summaryTable.average_force_N, 'max');
score_ripple = normalizeObjective(summaryTable.force_ripple_N, 'min');
compromise_score = (score_length + score_average + score_ripple) ./ 3;

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

writetable(rankedCandidates, fullfile(outputDir, 'ranked_candidates.xlsx'), ...
    'Sheet', 'ranked_candidates');
writetable(paretoFront, fullfile(outputDir, 'pareto_front.xlsx'), ...
    'Sheet', 'pareto_front');

bestSolution = rankedCandidates(1, :);

fprintf('\n最佳折中解：\n');
fprintf('lout = %.0f mm\n', bestSolution.lout_mm);
fprintf('lpm = %.0f mm\n', bestSolution.lpm_mm);
fprintf('lpmspace = %.0f mm\n', bestSolution.lpmspace_mm);
fprintf('永磁体长度目标 = %.9f mm\n', bestSolution.pm_length_objective_mm);
fprintf('平均推力 = %.9f N\n', bestSolution.average_force_N);
fprintf('推力波动 max(F)-min(F) = %.9f N\n', bestSolution.force_ripple_N);
fprintf('综合评分 = %.9f\n', bestSolution.compromise_score);
fprintf('Pareto 解数量 = %d\n', height(paretoFront));
fprintf('三维图数量 = %d\n', plotCount);
fprintf('\n结果已保存到：%s\n', outputDir);
fprintf('三维图已保存到：%s\n', figureDir);

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

function flag = dominatesSolution(lengthA, avgA, rippleA, lengthB, avgB, rippleB)
    noWorse = lengthA <= lengthB && avgA >= avgB && rippleA <= rippleB;
    strictlyBetter = lengthA < lengthB || avgA > avgB || rippleA < rippleB;
    flag = noWorse && strictlyBetter;
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
