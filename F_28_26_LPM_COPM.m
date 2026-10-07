clear;
clc;
close all;

%% =========================================================
%  数据读取
% ==========================================================

% 三组原始 CSV 数据
data_26_26 = readtable('lpm=26_stator_lpm=26.csv', ...
    'VariableNamingRule','preserve');

data_28_26 = readtable('lpm=28_stator_lpm=26.csv', ...
    'VariableNamingRule','preserve');

data_28_28 = readtable('lpm=28_stator_lpm=28.csv', ...
    'VariableNamingRule','preserve');


% 横坐标：位移 a (mm)
a_26_26 = data_26_26.("a [mm]");
a_28_26 = data_28_26.("a [mm]");
a_28_28 = data_28_28.("a [mm]");

% 纵坐标：z 方向推力 Fz (N)
F_26_26 = data_26_26.("Force_move.Force_z [newton]");
F_28_26 = data_28_26.("Force_move.Force_z [newton]");
F_28_28 = data_28_28.("Force_move.Force_z [newton]");


%% =========================================================
%  数据处理
%  不进行拟合、平滑或数据修正
% ==========================================================

% 26/26 mm
F_avg_26_26 = mean(F_26_26);
F_max_26_26 = max(F_26_26);
F_min_26_26 = min(F_26_26);
F_diff_26_26 = F_max_26_26 - F_min_26_26;

% 28/26 mm
F_avg_28_26 = mean(F_28_26);
F_max_28_26 = max(F_28_26);
F_min_28_26 = min(F_28_26);
F_diff_28_26 = F_max_28_26 - F_min_28_26;

% 28/28 mm
F_avg_28_28 = mean(F_28_28);
F_max_28_28 = max(F_28_28);
F_min_28_28 = min(F_28_28);
F_diff_28_28 = F_max_28_28 - F_min_28_28;


%% =========================================================
%  在命令行输出统计结果
% ==========================================================

fprintf('\n================ 推力统计结果 ================\n');

fprintf('动子/定子 = 26/26 mm：\n');
fprintf('平均值   = %.4f N\n', F_avg_26_26);
fprintf('最大值   = %.4f N\n', F_max_26_26);
fprintf('最小值   = %.4f N\n', F_min_26_26);
fprintf('最大差值 = %.4f N\n\n', F_diff_26_26);

fprintf('动子/定子 = 28/26 mm：\n');
fprintf('平均值   = %.4f N\n', F_avg_28_26);
fprintf('最大值   = %.4f N\n', F_max_28_26);
fprintf('最小值   = %.4f N\n', F_min_28_26);
fprintf('最大差值 = %.4f N\n\n', F_diff_28_26);

fprintf('动子/定子 = 28/28 mm：\n');
fprintf('平均值   = %.4f N\n', F_avg_28_28);
fprintf('最大值   = %.4f N\n', F_max_28_28);
fprintf('最小值   = %.4f N\n', F_min_28_28);
fprintf('最大差值 = %.4f N\n', F_diff_28_28);

fprintf('==============================================\n');


%% =========================================================
%  绘制三条推力曲线
% ==========================================================

figure;
hold on;

p1 = plot(a_26_26, F_26_26, '-o', ...
    'LineWidth',1.5, ...
    'MarkerSize',4, ...
    'MarkerIndices',1:2:length(a_26_26));

p2 = plot(a_28_26, F_28_26, '--s', ...
    'LineWidth',1.5, ...
    'MarkerSize',4, ...
    'MarkerIndices',1:2:length(a_28_26));

p3 = plot(a_28_28, F_28_28, '-.^', ...
    'LineWidth',1.5, ...
    'MarkerSize',4, ...
    'MarkerIndices',1:2:length(a_28_28));


%% =========================================================
%  坐标轴设置
% ==========================================================

ax = gca;

set(ax, ...
    'FontName','Times New Roman', ...
    'FontSize',12, ...
    'FontAngle','normal', ...
    'LineWidth',1, ...
    'TickDir','in');

% 根据原始数据范围设置横坐标
xlim([-10 10]);
xticks(-10:2:10);


%% =========================================================
%  坐标标签
% ==========================================================

% 中文：宋体
% 英文/数字：Times New Roman
% 变量：Times New Roman 斜体
% 单位：Times New Roman 正体

xlabel(['\fontname{SimSun}位移 ', ...
        '\fontname{Times New Roman}\ita\rm (mm)'], ...
        'FontSize',12, ...
        'Interpreter','tex');

ylabel(['\fontname{SimSun}推力 ', ...
        '\fontname{Times New Roman}\itF_z\rm (N)'], ...
        'FontSize',12, ...
        'Interpreter','tex');


%% =========================================================
%  图例设置
% ==========================================================

lgd = legend([p1,p2,p3], ...
    { ...
    '\fontname{SimSun}动子/定子：\fontname{Times New Roman}26/26 mm', ...
    '\fontname{SimSun}动子/定子：\fontname{Times New Roman}28/26 mm', ...
    '\fontname{SimSun}动子/定子：\fontname{Times New Roman}28/28 mm' ...
    }, ...
    'Interpreter','tex', ...
    'FontSize',12, ...
    'Location','best');

lgd.Box = 'on';


%% =========================================================
%  网格和边框
% ==========================================================

grid on;
box on;

set(gca, ...
    'GridLineStyle','--', ...
    'GridAlpha',0.20, ...
    'LineWidth',1);


%% =========================================================
%  图形尺寸
% ==========================================================

set(gcf, ...
    'Units','centimeters', ...
    'Position',[10,5,11,4.4]);

hold off;