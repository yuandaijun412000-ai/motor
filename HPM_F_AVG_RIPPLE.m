clear;
clc;
close all;

%% =========================================================
%  数据读取
% ==========================================================

data = readtable('F_HPM_RIPPLE_AVG.csv', ...
    'VariableNamingRule','preserve');

% 两块永磁体厚度
hpm1 = data.("hpm [mm]");
hpm2 = data.("hpm2 [mm]");

% 动子位移
a = data.("a [mm]");

% z方向推力
F = data.("Force_move.Force_z [newton]");


%% =========================================================
%  数据筛选
%  每种永磁体结构仅采用 a = -10、0、+10 mm 三个位置
% ==========================================================

index = ismember(a,[-10,0,10]);

hpm1 = hpm1(index);
hpm2 = hpm2(index);
a    = a(index);
F    = F(index);


%% =========================================================
%  每种永磁体厚度组合的推力统计
% ==========================================================

% 根据两块永磁体厚度进行分组
[G,hpm1_group,hpm2_group] = findgroups(hpm1,hpm2);

% 三个位移位置的平均推力
F_avg = splitapply(@mean,F,G);

% 最大推力
F_max = splitapply(@max,F,G);

% 最小推力
F_min = splitapply(@min,F,G);

% 最大差值，即推力波动
F_diff = F_max - F_min;

% 两块永磁体总厚度
H_total = hpm1_group + hpm2_group;


%% =========================================================
%  统计结果整理
% ==========================================================

Result = table( ...
    hpm1_group, ...
    hpm2_group, ...
    H_total, ...
    F_avg, ...
    F_max, ...
    F_min, ...
    F_diff, ...
    'VariableNames', ...
    {'hpm1_mm','hpm2_mm','H_total_mm', ...
     'F_avg_N','F_max_N','F_min_N','F_diff_N'});

% 按第一块永磁体厚度、第二块永磁体厚度排序
Result = sortrows(Result,{'hpm1_mm','hpm2_mm'});

% 在命令窗口显示全部121种结构
disp(' ');
disp('================ 永磁体结构推力统计结果 ================');
disp(Result);

% 如需要，可将121种结构统计结果输出为CSV
writetable(Result,'F_HPM_statistics.csv');


%% =========================================================
%  三目标多目标优化
%
%  目标1：两块永磁体总厚度最小
%        f1 = hpm1 + hpm2
%
%  目标2：推力最大差值最小
%        f2 = DeltaF
%
%  目标3：平均推力最大
%        f3 = F_avg
%
%  为统一成最小化问题：
%        objective = [H_total, F_diff, -F_avg]
%
%  由于原始数据为121个离散设计点，这里直接进行
%  Pareto非支配筛选，不拟合、不插值原始数据。
% ==========================================================

Obj = [Result.H_total_mm, ...
       Result.F_diff_N, ...
      -Result.F_avg_N];

N = size(Obj,1);

% true表示该方案属于Pareto非支配解
isPareto = true(N,1);

for i = 1:N

    % 判断是否存在一个方案：
    % 三个目标均不差于第i个方案，
    % 且至少一个目标严格优于第i个方案
    dominate_i = all(Obj <= Obj(i,:),2) & ...
                 any(Obj <  Obj(i,:),2);

    if any(dominate_i)
        isPareto(i) = false;
    end

end

% Pareto解集合
ParetoResult = Result(isPareto,:);

disp(' ');
disp('================ Pareto非支配解 ================');
disp(ParetoResult);


%% =========================================================
%  三目标归一化
%  用于从Pareto解中寻找一个等权折中方案
% ==========================================================

% ---------- 目标1：总厚度越小越好 ----------
f1_norm = ...
    (Result.H_total_mm - min(Result.H_total_mm)) ./ ...
    (max(Result.H_total_mm) - min(Result.H_total_mm));

% ---------- 目标2：推力最大差值越小越好 ----------
f2_norm = ...
    (Result.F_diff_N - min(Result.F_diff_N)) ./ ...
    (max(Result.F_diff_N) - min(Result.F_diff_N));

% ---------- 目标3：平均推力越大越好 ----------
% 最大平均推力对应归一化值0
f3_norm = ...
    (max(Result.F_avg_N) - Result.F_avg_N) ./ ...
    (max(Result.F_avg_N) - min(Result.F_avg_N));


%% =========================================================
%  三个目标权重
%
%  当前采用等权：
%  总厚度     1/3
%  推力波动   1/3
%  平均推力   1/3
%
%  后续如果更重视推力波动，可例如修改为：
%  w = [0.2 0.5 0.3];
% ==========================================================

w = [1/3, 1/3, 1/3];

% 与理想点 [0 0 0] 的加权欧氏距离
Score = sqrt( ...
    w(1).*f1_norm.^2 + ...
    w(2).*f2_norm.^2 + ...
    w(3).*f3_norm.^2 );


%% =========================================================
%  只在Pareto非支配解中寻找折中最优设计
% ==========================================================

ParetoIndex = find(isPareto);

[~,local_best] = min(Score(ParetoIndex));

bestIndex = ParetoIndex(local_best);

BestResult = Result(bestIndex,:);


%% =========================================================
%  输出多目标优化结果
% ==========================================================

fprintf('\n');
fprintf('================ 三目标优化折中结果 ================\n');

fprintf('永磁体1厚度 hpm1 = %.2f mm\n', ...
    BestResult.hpm1_mm);

fprintf('永磁体2厚度 hpm2 = %.2f mm\n', ...
    BestResult.hpm2_mm);

fprintf('永磁体总厚度      = %.2f mm\n', ...
    BestResult.H_total_mm);

fprintf('平均推力          = %.4f N\n', ...
    BestResult.F_avg_N);

fprintf('最大推力          = %.4f N\n', ...
    BestResult.F_max_N);

fprintf('最小推力          = %.4f N\n', ...
    BestResult.F_min_N);

fprintf('最大差值          = %.4f N\n', ...
    BestResult.F_diff_N);

fprintf('====================================================\n');


%% =========================================================
%  构造三维绘图矩阵
%  不拟合、不平滑，只按照原始离散数据排列
% ==========================================================

hpm1_unique = unique(Result.hpm1_mm);
hpm2_unique = unique(Result.hpm2_mm);

[HPM1,HPM2] = meshgrid(hpm1_unique,hpm2_unique);

FAVG_grid  = nan(size(HPM1));
FDIFF_grid = nan(size(HPM1));

for i = 1:height(Result)

    row = find(abs(hpm2_unique - Result.hpm2_mm(i)) < 1e-10);
    col = find(abs(hpm1_unique - Result.hpm1_mm(i)) < 1e-10);

    FAVG_grid(row,col)  = Result.F_avg_N(i);
    FDIFF_grid(row,col) = Result.F_diff_N(i);

end


%% =========================================================
%  图1：两块永磁体厚度与平均推力三维关系
% ==========================================================

figure;

surf(HPM1,HPM2,FAVG_grid, ...
    'FaceAlpha',0.95, ...
    'EdgeColor',[0.30 0.30 0.30], ...
    'LineWidth',0.5);

hold on;

% 原始离散数据点
plot3(Result.hpm1_mm, ...
      Result.hpm2_mm, ...
      Result.F_avg_N, ...
      '.', ...
      'MarkerSize',8);

% 标记三目标折中解
plot3(BestResult.hpm1_mm, ...
      BestResult.hpm2_mm, ...
      BestResult.F_avg_N, ...
      'p', ...
      'MarkerSize',10, ...
      'LineWidth',1.5);

hold off;


%% 坐标轴设置

set(gca, ...
    'FontName','Times New Roman', ...
    'FontSize',12, ...
    'FontAngle','normal', ...
    'LineWidth',1);

xticks(2:0.4:4);
yticks(2:0.4:4);

xlim([2 4]);
ylim([2 4]);

view(45,30);


%% 坐标标签

xlabel([ ...
    '\fontname{SimSun}永磁体1厚度 ', ...
    '\fontname{Times New Roman}\ith_{\rm pm1}\rm (mm)'], ...
    'FontSize',12, ...
    'Interpreter','tex');

ylabel([ ...
    '\fontname{SimSun}永磁体2厚度 ', ...
    '\fontname{Times New Roman}\ith_{\rm pm2}\rm (mm)'], ...
    'FontSize',12, ...
    'Interpreter','tex');

zlabel([ ...
    '\fontname{SimSun}平均推力 ', ...
    '\fontname{Times New Roman}\itF_{\rm avg}\rm (N)'], ...
    'FontSize',12, ...
    'Interpreter','tex');


%% 网格和边框

grid on;
box on;

set(gca, ...
    'GridLineStyle','--', ...
    'GridAlpha',0.20, ...
    'LineWidth',1);


%% 图形尺寸
% 三维图适当增加高度，便于论文中观察曲面

set(gcf, ...
    'Units','centimeters', ...
    'Position',[10,5,11,8]);


%% =========================================================
%  图2：两块永磁体厚度与推力最大差值三维关系
% ==========================================================

figure;

surf(HPM1,HPM2,FDIFF_grid, ...
    'FaceAlpha',0.95, ...
    'EdgeColor',[0.30 0.30 0.30], ...
    'LineWidth',0.5);

hold on;

% 原始离散数据点
plot3(Result.hpm1_mm, ...
      Result.hpm2_mm, ...
      Result.F_diff_N, ...
      '.', ...
      'MarkerSize',8);

% 标记三目标折中解
plot3(BestResult.hpm1_mm, ...
      BestResult.hpm2_mm, ...
      BestResult.F_diff_N, ...
      'p', ...
      'MarkerSize',10, ...
      'LineWidth',1.5);

hold off;


%% 坐标轴设置

set(gca, ...
    'FontName','Times New Roman', ...
    'FontSize',12, ...
    'FontAngle','normal', ...
    'LineWidth',1);

xticks(2:0.4:4);
yticks(2:0.4:4);

xlim([2 4]);
ylim([2 4]);

view(45,30);


%% 坐标标签

xlabel([ ...
    '\fontname{SimSun}永磁体1厚度 ', ...
    '\fontname{Times New Roman}\ith_{\rm pm1}\rm (mm)'], ...
    'FontSize',12, ...
    'Interpreter','tex');

ylabel([ ...
    '\fontname{SimSun}永磁体2厚度 ', ...
    '\fontname{Times New Roman}\ith_{\rm pm2}\rm (mm)'], ...
    'FontSize',12, ...
    'Interpreter','tex');

zlabel([ ...
    '\fontname{SimSun}推力最大差值 ', ...
    '\fontname{Times New Roman}\it\Delta F\rm (N)'], ...
    'FontSize',12, ...
    'Interpreter','tex');


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