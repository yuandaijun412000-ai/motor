clear;
clc;
close all;


%% =========================================================
%  1. 数据读取
% ==========================================================

data = readtable('1S2P_L_F_ADD.csv', ...
    'VariableNamingRule','preserve');

% 永磁体长度
lpm = data.("lpm [mm]");

% 永磁体间距
lpmspace = data.("lpmspace [mm]");

% 动子位移
a = data.("a [mm]");

% z方向推力
F = data.("Force_pm.Force_z [newton]");


%% =========================================================
%  2. 原始数据检查
% ==========================================================

fprintf('\n');
fprintf('================ 原始数据检查 ================\n');

fprintf('原始数据总行数：%d\n',height(data));

fprintf('lpm范围：%.2f ~ %.2f mm\n', ...
    min(lpm),max(lpm));

fprintf('lpmspace范围：%.2f ~ %.2f mm\n', ...
    min(lpmspace),max(lpmspace));

fprintf('位移a取值：');
fprintf('%.0f  ',unique(a));
fprintf('mm\n');

fprintf('缺失值总数：%d\n', ...
    sum(ismissing(data),'all'));

fprintf('==============================================\n');


%% =========================================================
%  3. 保存完整参数空间
%
%  实际设计变量：
%
%  lpm      = 20,22,...,50 mm
%  lpmspace = 4,5,...,14 mm
%
%  共：
%
%  16 × 11 = 176种设计组合
% ==========================================================

lpm_all = unique(lpm);

space_all = unique(lpmspace);

target_a = [-10;0;10];


%% =========================================================
%  4. 保留 a=-10、0、+10 mm
%
%  注意：
%  本代码不剔除 a=+10 mm
% ==========================================================

index = ismember(a,target_a);

lpm_use = lpm(index);

space_use = lpmspace(index);

a_use = a(index);

F_use = F(index);


%% =========================================================
%  5. 按 lpm 和 lpmspace 分组
% ==========================================================

[G,lpm_group,space_group] = ...
    findgroups(lpm_use,space_use);


% 每种结构实际数据点数量
N_point = ...
    splitapply(@numel,F_use,G);


% 每种结构不同位移数量
N_unique_a = ...
    splitapply(@(x)numel(unique(x)),a_use,G);


% 是否包含 a=-10、0、+10 mm
has_three_a = ...
    splitapply( ...
    @(x)all(ismember(target_a,x)), ...
    a_use,G);


%% =========================================================
%  6. 判断完整三点结构
% ==========================================================

valid_group = ...
    (N_point == 3) & ...
    (N_unique_a == 3) & ...
    has_three_a;


fprintf('\n');
fprintf('================ 三点数据完整性检查 ================\n');

fprintf('设计组合总数：%d\n', ...
    length(valid_group));

fprintf('a=-10、0、+10 mm 三点完整组合数：%d\n', ...
    sum(valid_group));

fprintf('三点不完整组合数：%d\n', ...
    sum(~valid_group));

fprintf('====================================================\n');


%% =========================================================
%  7. 输出三点不完整的参数组合
% ==========================================================

IncompleteResult = table( ...
    lpm_group(~valid_group), ...
    space_group(~valid_group), ...
    N_point(~valid_group), ...
    'VariableNames', ...
    {'lpm_mm', ...
     'lpmspace_mm', ...
     'N_point'});


disp(' ');
disp('================ 三点数据不完整组合 ================');

disp(IncompleteResult);


% 保存不完整结构，方便检查
writetable( ...
    IncompleteResult, ...
    '1S2P_L_Incomplete_3point.csv');


%% =========================================================
%  8. 每种结构计算平均推力
%
%          F(-10)+F(0)+F(+10)
% F_avg = --------------------
%                   3
% ==========================================================

F_avg_all = ...
    splitapply(@mean,F_use,G);


%% =========================================================
%  9. 计算最大推力与最小推力
% ==========================================================

F_max_all = ...
    splitapply(@max,F_use,G);


F_min_all = ...
    splitapply(@min,F_use,G);


%% =========================================================
%  10. 计算推力最大差值
%
%  DeltaF =
%
%  max[F(-10),F(0),F(+10)]
%
%            -
%
%  min[F(-10),F(0),F(+10)]
% ==========================================================

F_diff_all = ...
    F_max_all - F_min_all;


%% =========================================================
%  11. 只使用三点完整结构计算统一评价指标
%
%  缺少 a=+10 mm 的结构：
%
%  不删除原始文件中的数据；
%  不进行人为补值；
%  不参与三点指标比较。
% ==========================================================

lpm_valid = ...
    lpm_group(valid_group);


space_valid = ...
    space_group(valid_group);


F_avg = ...
    F_avg_all(valid_group);


F_max = ...
    F_max_all(valid_group);


F_min = ...
    F_min_all(valid_group);


F_diff = ...
    F_diff_all(valid_group);


%% =========================================================
%  12. 建立统计结果表
% ==========================================================

Result = table( ...
    lpm_valid, ...
    space_valid, ...
    F_avg, ...
    F_max, ...
    F_min, ...
    F_diff, ...
    'VariableNames', ...
    {'lpm_mm', ...
     'lpmspace_mm', ...
     'F_avg_N', ...
     'F_max_N', ...
     'F_min_N', ...
     'F_diff_N'});


Result = sortrows( ...
    Result, ...
    {'lpm_mm','lpmspace_mm'});


disp(' ');
disp('================ 三点完整结构统计结果 ================');

disp(Result);


%% 保存统计结果

writetable( ...
    Result, ...
    '1S2P_L_statistics_3point.csv');


%% =========================================================
%  13. 单目标最优结果
%
%  目标1：
%       推力最大差值最小
%
%  目标2：
%       平均推力最大
%
%  目标3：
%       lpm最小
% ==========================================================


%% 推力最大差值最小

[~,idx_min_diff] = ...
    min(Result.F_diff_N);


%% 平均推力最大

[~,idx_max_avg] = ...
    max(Result.F_avg_N);


%% lpm最小

lpm_min = ...
    min(Result.lpm_mm);


fprintf('\n');
fprintf('================ 单目标最优结果 ================\n');


fprintf('\n【推力最大差值最小】\n');

fprintf('lpm       = %.2f mm\n', ...
    Result.lpm_mm(idx_min_diff));

fprintf('lpmspace  = %.2f mm\n', ...
    Result.lpmspace_mm(idx_min_diff));

fprintf('平均推力  = %.6f N\n', ...
    Result.F_avg_N(idx_min_diff));

fprintf('最大差值  = %.6f N\n', ...
    Result.F_diff_N(idx_min_diff));


fprintf('\n【平均推力最大】\n');

fprintf('lpm       = %.2f mm\n', ...
    Result.lpm_mm(idx_max_avg));

fprintf('lpmspace  = %.2f mm\n', ...
    Result.lpmspace_mm(idx_max_avg));

fprintf('平均推力  = %.6f N\n', ...
    Result.F_avg_N(idx_max_avg));

fprintf('最大差值  = %.6f N\n', ...
    Result.F_diff_N(idx_max_avg));


fprintf('\n【永磁体长度最小】\n');

fprintf('lpm最小值 = %.2f mm\n', ...
    lpm_min);


fprintf('================================================\n');


%% =========================================================
%  14. 三目标Pareto优化
%
%  三个优化目标：
%
%  (1) 推力最大差值最小
%
%       min DeltaF
%
%  (2) 平均推力最大
%
%       max F_avg
%
%  (3) 永磁体长度最小
%
%       min lpm
%
%
%  转换成统一的最小化问题：
%
%  Objective =
%
%       [DeltaF, -F_avg, lpm]
% ==========================================================

Objective = [ ...
    Result.F_diff_N, ...
   -Result.F_avg_N, ...
    Result.lpm_mm];


N = height(Result);

isPareto = true(N,1);


%% =========================================================
%  15. Pareto非支配解筛选
% ==========================================================

for i = 1:N

    % 若存在另外一个方案：
    %
    % 三个目标均不差于当前方案，
    % 并至少有一个目标严格优于当前方案，
    %
    % 则当前方案被支配。

    dominate = ...
        all(Objective <= Objective(i,:),2) & ...
        any(Objective < Objective(i,:),2);


    if any(dominate)

        isPareto(i) = false;

    end

end


%% =========================================================
%  16. 提取Pareto非支配解
% ==========================================================

ParetoResult = ...
    Result(isPareto,:);


ParetoResult = ...
    sortrows( ...
    ParetoResult, ...
    {'lpm_mm','F_avg_N'});


disp(' ');
disp('================ 三目标Pareto非支配解 ================');

disp(ParetoResult);


fprintf('\nPareto非支配解数量：%d\n', ...
    height(ParetoResult));


writetable( ...
    ParetoResult, ...
    '1S2P_L_Pareto_3Objective.csv');


%% =========================================================
%  17. 目标1归一化
%
%  推力最大差值：
%
%  越小越好
%
%  最小值 -> 0
%  最大值 -> 1
% ==========================================================

diff_min = min(Result.F_diff_N);

diff_max = max(Result.F_diff_N);

diff_range = ...
    diff_max - diff_min;


if diff_range == 0

    f1_norm = ...
        zeros(height(Result),1);

else

    f1_norm = ...
        (Result.F_diff_N - diff_min) ./ ...
        diff_range;

end


%% =========================================================
%  18. 目标2归一化
%
%  平均推力：
%
%  越大越好
%
%  最大值 -> 0
%  最小值 -> 1
% ==========================================================

avg_min = min(Result.F_avg_N);

avg_max = max(Result.F_avg_N);

avg_range = ...
    avg_max - avg_min;


if avg_range == 0

    f2_norm = ...
        zeros(height(Result),1);

else

    f2_norm = ...
        (avg_max - Result.F_avg_N) ./ ...
        avg_range;

end


%% =========================================================
%  19. 目标3归一化
%
%  永磁体长度：
%
%  越小越好
%
%  最小值 -> 0
%  最大值 -> 1
% ==========================================================

lpm_min = min(Result.lpm_mm);

lpm_max = max(Result.lpm_mm);

lpm_range = ...
    lpm_max - lpm_min;


if lpm_range == 0

    f3_norm = ...
        zeros(height(Result),1);

else

    f3_norm = ...
        (Result.lpm_mm - lpm_min) ./ ...
        lpm_range;

end


%% =========================================================
%  20. 三目标权重
%
%  推力最大差值 DeltaF：0.5
%
%  平均推力 F_avg：     0.3
%
%  永磁体长度 lpm：     0.2
%
%  权重之和：
%
%       0.5 + 0.3 + 0.2 = 1
% ==========================================================

w = [0.8, 0.1, 0.1];


%% =========================================================
%  21. 加权理想点距离
%
%  理想状态：
%
%  DeltaF最小
%  F_avg最大
%  lpm最小
%
%  对应归一化理想点：
%
%       [0,0,0]
%
%  Score越小综合性能越好
% ==========================================================

Score = sqrt( ...
    w(1).*f1_norm.^2 + ...
    w(2).*f2_norm.^2 + ...
    w(3).*f3_norm.^2);


%% =========================================================
%  22. 只在Pareto解中寻找最终折中方案
% ==========================================================

ParetoIndex = ...
    find(isPareto);


[~,local_best] = ...
    min(Score(ParetoIndex));


BestIndex = ...
    ParetoIndex(local_best);


BestResult = ...
    Result(BestIndex,:);


%% =========================================================
%  23. 输出最终优化结果
% ==========================================================

fprintf('\n');
fprintf('================ 三目标折中优化结果 ================\n');

fprintf('权重设置：\n');

fprintf('推力波动 DeltaF = %.2f\n', ...
    w(1));

fprintf('平均推力 F_avg  = %.2f\n', ...
    w(2));

fprintf('永磁体长度 lpm  = %.2f\n\n', ...
    w(3));


fprintf('永磁体长度 lpm          = %.2f mm\n', ...
    BestResult.lpm_mm);

fprintf('永磁体间距 lpmspace     = %.2f mm\n', ...
    BestResult.lpmspace_mm);

fprintf('平均推力 F_avg          = %.6f N\n', ...
    BestResult.F_avg_N);

fprintf('最大推力 F_max          = %.6f N\n', ...
    BestResult.F_max_N);

fprintf('最小推力 F_min          = %.6f N\n', ...
    BestResult.F_min_N);

fprintf('推力最大差值 DeltaF     = %.6f N\n', ...
    BestResult.F_diff_N);

fprintf('综合评价值 Score        = %.6f\n', ...
    Score(BestIndex));

fprintf('====================================================\n');


%% =========================================================
%  24. 将优化信息加入结果表
% ==========================================================

Result.Score = Score;

Result.isPareto = isPareto;


writetable( ...
    Result, ...
    '1S2P_L_AllOptimizationResult.csv');


writetable( ...
    BestResult, ...
    '1S2P_L_BestResult_3Objective.csv');


%% =========================================================
%  25. 构造三维响应矩阵
%
%  横轴：
%       lpm = 20 ~ 50 mm
%
%  纵轴：
%       lpmspace = 4 ~ 14 mm
%
%
%  缺少三点数据的位置：
%
%       设置为 NaN
%
%
%  不拟合
%  不平滑
%  不插值
%  不补造数据
% ==========================================================

[LPM,SPACE] = ...
    meshgrid( ...
    lpm_all, ...
    space_all);


FAVG_grid = ...
    nan(size(LPM));


FDIFF_grid = ...
    nan(size(LPM));


for i = 1:height(Result)

    row = find( ...
        abs(space_all - ...
        Result.lpmspace_mm(i)) < 1e-10);


    col = find( ...
        abs(lpm_all - ...
        Result.lpm_mm(i)) < 1e-10);


    FAVG_grid(row,col) = ...
        Result.F_avg_N(i);


    FDIFF_grid(row,col) = ...
        Result.F_diff_N(i);

end


%% =========================================================
%  26. 图1
%
%  永磁体长度、间距与平均推力
% ==========================================================

figure;


surf( ...
    LPM, ...
    SPACE, ...
    FAVG_grid, ...
    'FaceAlpha',0.95, ...
    'EdgeColor',[0.30 0.30 0.30], ...
    'LineWidth',0.5);


hold on;


%% 三点完整原始数据

p1 = plot3( ...
    Result.lpm_mm, ...
    Result.lpmspace_mm, ...
    Result.F_avg_N, ...
    '.', ...
    'MarkerSize',8);


%% 最终折中优化点

p2 = plot3( ...
    BestResult.lpm_mm, ...
    BestResult.lpmspace_mm, ...
    BestResult.F_avg_N, ...
    'p', ...
    'MarkerSize',11, ...
    'LineWidth',1.5);


hold off;


%% 坐标轴设置

set(gca, ...
    'FontName','Times New Roman', ...
    'FontSize',12, ...
    'FontAngle','normal', ...
    'LineWidth',1, ...
    'TickDir','in');


xlim([20 50]);

ylim([4 14]);


xticks(20:5:50);

yticks(4:2:14);


view(45,30);


%% 坐标标签

xlabel([ ...
    '\fontname{SimSun}永磁体长度 ', ...
    '\fontname{Times New Roman}\itl_{\rm pm}\rm (mm)'], ...
    'FontSize',12, ...
    'Interpreter','tex');


ylabel([ ...
    '\fontname{SimSun}永磁体间距 ', ...
    '\fontname{Times New Roman}\itl_{\rm space}\rm (mm)'], ...
    'FontSize',12, ...
    'Interpreter','tex');


zlabel([ ...
    '\fontname{SimSun}平均推力 ', ...
    '\fontname{Times New Roman}\itF_{\rm avg}\rm (N)'], ...
    'FontSize',12, ...
    'Interpreter','tex');


%% 图例

legend( ...
    [p1,p2], ...
    { ...
    '\fontname{SimSun}原始设计点', ...
    '\fontname{SimSun}折中最优方案' ...
    }, ...
    'Interpreter','tex', ...
    'FontSize',12, ...
    'Location','best');


%% 网格和边框

grid on;
box on;


set(gca, ...
    'GridLineStyle','--', ...
    'GridAlpha',0.20, ...
    'LineWidth',1);


%% 图形尺寸

set(gcf, ...
    'Units','centimeters', ...
    'Position',[10,5,11,8]);


%% =========================================================
%  27. 图2
%
%  永磁体长度、间距与推力最大差值
% ==========================================================

figure;


surf( ...
    LPM, ...
    SPACE, ...
    FDIFF_grid, ...
    'FaceAlpha',0.95, ...
    'EdgeColor',[0.30 0.30 0.30], ...
    'LineWidth',0.5);


hold on;


%% 三点完整原始数据

p3 = plot3( ...
    Result.lpm_mm, ...
    Result.lpmspace_mm, ...
    Result.F_diff_N, ...
    '.', ...
    'MarkerSize',8);


%% 最终折中优化点

p4 = plot3( ...
    BestResult.lpm_mm, ...
    BestResult.lpmspace_mm, ...
    BestResult.F_diff_N, ...
    'p', ...
    'MarkerSize',11, ...
    'LineWidth',1.5);


hold off;


%% 坐标轴设置

set(gca, ...
    'FontName','Times New Roman', ...
    'FontSize',12, ...
    'FontAngle','normal', ...
    'LineWidth',1, ...
    'TickDir','in');


xlim([20 50]);

ylim([4 14]);


xticks(20:5:50);

yticks(4:2:14);


view(45,30);


%% 坐标标签

xlabel([ ...
    '\fontname{SimSun}永磁体长度 ', ...
    '\fontname{Times New Roman}\itl_{\rm pm}\rm (mm)'], ...
    'FontSize',12, ...
    'Interpreter','tex');


ylabel([ ...
    '\fontname{SimSun}永磁体间距 ', ...
    '\fontname{Times New Roman}\itl_{\rm space}\rm (mm)'], ...
    'FontSize',12, ...
    'Interpreter','tex');


zlabel([ ...
    '\fontname{SimSun}推力最大差值 ', ...
    '\fontname{Times New Roman}\it\Delta F\rm (N)'], ...
    'FontSize',12, ...
    'Interpreter','tex');


%% 图例

legend( ...
    [p3,p4], ...
    { ...
    '\fontname{SimSun}原始设计点', ...
    '\fontname{SimSun}折中最优方案' ...
    }, ...
    'Interpreter','tex', ...
    'FontSize',12, ...
    'Location','best');


%% 网格和边框

grid on;
box on;


set(gca, ...
    'GridLineStyle','--', ...
    'GridAlpha',0.20, ...
    'LineWidth',1);


%% 图形尺寸

set(gcf, ...
    'Units','centimeters', ...
    'Position',[10,5,11,8]);


%% =========================================================
%  28. 图3
%
%  三目标Pareto解空间
%
%  x：
%      平均推力，越大越好
%
%  y：
%      推力最大差值，越小越好
%
%  z：
%      永磁体长度，越小越好
% ==========================================================

figure;


%% 全部有效设计方案

q1 = plot3( ...
    Result.F_avg_N, ...
    Result.F_diff_N, ...
    Result.lpm_mm, ...
    'o', ...
    'LineWidth',1, ...
    'MarkerSize',4);


hold on;


%% Pareto非支配解

q2 = plot3( ...
    ParetoResult.F_avg_N, ...
    ParetoResult.F_diff_N, ...
    ParetoResult.lpm_mm, ...
    's', ...
    'LineWidth',1.5, ...
    'MarkerSize',6);


%% 最终折中解

q3 = plot3( ...
    BestResult.F_avg_N, ...
    BestResult.F_diff_N, ...
    BestResult.lpm_mm, ...
    'p', ...
    'LineWidth',1.5, ...
    'MarkerSize',11);


hold off;


%% 坐标轴设置

set(gca, ...
    'FontName','Times New Roman', ...
    'FontSize',12, ...
    'FontAngle','normal', ...
    'LineWidth',1, ...
    'TickDir','in');


view(45,30);


%% 坐标标签

xlabel([ ...
    '\fontname{SimSun}平均推力 ', ...
    '\fontname{Times New Roman}\itF_{\rm avg}\rm (N)'], ...
    'FontSize',12, ...
    'Interpreter','tex');


ylabel([ ...
    '\fontname{SimSun}推力最大差值 ', ...
    '\fontname{Times New Roman}\it\Delta F\rm (N)'], ...
    'FontSize',12, ...
    'Interpreter','tex');


zlabel([ ...
    '\fontname{SimSun}永磁体长度 ', ...
    '\fontname{Times New Roman}\itl_{\rm pm}\rm (mm)'], ...
    'FontSize',12, ...
    'Interpreter','tex');


%% 图例

legend( ...
    [q1,q2,q3], ...
    { ...
    '\fontname{SimSun}全部设计方案', ...
    '\fontname{SimSun}Pareto非支配解', ...
    '\fontname{SimSun}折中最优方案' ...
    }, ...
    'Interpreter','tex', ...
    'FontSize',12, ...
    'Location','best');


%% 网格和边框

grid on;
box on;


set(gca, ...
    'GridLineStyle','--', ...
    'GridAlpha',0.20, ...
    'LineWidth',1);


%% 图形尺寸

set(gcf, ...
    'Units','centimeters', ...
    'Position',[10,5,11,8]);