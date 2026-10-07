clear;
clc;
close all;

%% 数据读取
dataFile = 'lextrude_RIPPLE.csv';
data = readtable(dataFile, 'VariableNamingRule', 'preserve');

lextrude = double(data.('lextrude [mm]'));
force = double(data.('Force_move.Force_z [newton]'));

%% 数据处理
% 同一个 lextrude 下包含多个位移 a 的推力值。
% 推力波动定义为 max(F)-min(F)。
groupID = findgroups(lextrude);
lextrude_group = splitapply(@(x) x(1), lextrude, groupID);
force_ripple = splitapply(@(x) max(x) - min(x), force, groupID);

resultTable = table( ...
    lextrude_group, ...
    force_ripple, ...
    'VariableNames', {'lextrude_mm', 'force_ripple_N'});

resultTable = sortrows(resultTable, 'lextrude_mm');

%% 绘制二维关系图
figure('Color', 'w');
plot(resultTable.lextrude_mm, resultTable.force_ripple_N, 'o-', ...
    'LineWidth', 1.5, ...
    'MarkerSize', 6, ...
    'MarkerFaceColor', [0.0000, 0.4470, 0.7410], ...
    'MarkerEdgeColor', [0.0000, 0.4470, 0.7410]);

%% 坐标轴设置
ax = gca;
set(ax, ...
    'FontName', 'Times New Roman', ...
    'FontSize', 12, ...
    'LineWidth', 1, ...
    'GridLineStyle', '--');
grid on;
box on;

%% 坐标标签
xlabel('\fontname{SimSun}磁化铁突出长度 \fontname{Times New Roman}\itl_{\rm extrude}\rm (mm)', ...
    'FontSize', 12, 'Interpreter', 'tex');
ylabel('\fontname{SimSun}推力波动 \fontname{Times New Roman}\Delta\itF_{\rm e}\rm (N)', ...
    'FontSize', 12, 'Interpreter', 'tex');

%% 坐标范围
xlim([min(resultTable.lextrude_mm), max(resultTable.lextrude_mm)]);
yMargin = 0.05 * range(resultTable.force_ripple_N);
if yMargin == 0
    yMargin = 1;
end
ylim([min(resultTable.force_ripple_N) - yMargin, ...
      max(resultTable.force_ripple_N) + yMargin]);

%% 图形尺寸
set(gcf, 'Units', 'centimeters', 'Position', [10, 5, 11, 4.4]);

%% 输出计算结果到命令行
disp(resultTable);
