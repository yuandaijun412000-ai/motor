clear;
clc;
close all;


%% =========================================================
% 数据读取
% ==========================================================

data = readtable('F_ANGLE_AVG_RIPPLE.csv', ...
    'VariableNamingRule','preserve');


% 两块永磁体宽度角
angle1 = data.("a_angel [deg]");
angle2 = data.("pm_angel [deg]");


% 位移
x = data.("a [mm]");


% 推力
F = data.("Force_move.Force_z [newton]");



%% =========================================================
% 数据处理
% 每种宽度组合取 a=-10,0,+10 mm
% ==========================================================

[G,angle1_group,angle2_group] = ...
    findgroups(angle1,angle2);


% 平均推力

F_avg = splitapply(@mean,F,G);


% 最大推力

F_max = splitapply(@max,F,G);


% 最小推力

F_min = splitapply(@min,F,G);


% 推力最大差值

F_diff = F_max-F_min;



% 两块永磁体总宽度角

Angle_total = angle1_group + angle2_group;



%% =========================================================
% 结果整理
% ==========================================================

Result = table(...
    angle1_group,...
    angle2_group,...
    Angle_total,...
    F_avg,...
    F_max,...
    F_min,...
    F_diff,...
    'VariableNames',...
    {'angle1_deg',...
     'angle2_deg',...
     'Angle_total_deg',...
     'F_avg_N',...
     'F_max_N',...
     'F_min_N',...
     'F_diff_N'});


disp('================ 推力统计结果 ================')

disp(Result)


writetable(Result,...
    'F_ANGLE_statistics.csv');



%% =========================================================
% 多目标优化
%
% f1: 总角度最小
% f2: 推力波动最小
% f3: 平均推力最大
%
% 转换为最小化：
% [总角度, 推力波动, -平均推力]
% ==========================================================


Objective = [
    Result.Angle_total_deg,...
    Result.F_diff_N,...
    -Result.F_avg_N
];


N=size(Objective,1);


%% Pareto非支配筛选

isPareto=true(N,1);


for i=1:N

    dominate = ...
        all(Objective<=Objective(i,:),2) & ...
        any(Objective<Objective(i,:),2);


    if any(dominate)

        isPareto(i)=false;

    end

end



ParetoResult=Result(isPareto,:);


disp('================ Pareto解 ================')

disp(ParetoResult)



%% =========================================================
% 三目标归一化折中优化
% ==========================================================


f1=(Result.Angle_total_deg-min(Result.Angle_total_deg))...
    /(max(Result.Angle_total_deg)-min(Result.Angle_total_deg));


f2=(Result.F_diff_N-min(Result.F_diff_N))...
    /(max(Result.F_diff_N)-min(Result.F_diff_N));


f3=(max(Result.F_avg_N)-Result.F_avg_N)...
    /(max(Result.F_avg_N)-min(Result.F_avg_N));



% 三目标等权

w=[1/3 1/3 1/3];


Score=sqrt(...
    w(1)*f1.^2+...
    w(2)*f2.^2+...
    w(3)*f3.^2);



ParetoIndex=find(isPareto);


[~,id]=min(Score(ParetoIndex));


BestIndex=ParetoIndex(id);


BestResult=Result(BestIndex,:);



disp('================ 三目标折中结果 ================')

disp(BestResult)



%% =========================================================
% 三维矩阵
% ==========================================================


angle1_unique=unique(Result.angle1_deg);
angle2_unique=unique(Result.angle2_deg);


[A1,A2]=meshgrid(angle1_unique,angle2_unique);


FAVG_grid=zeros(size(A1));

FDIFF_grid=zeros(size(A1));



for i=1:height(Result)

    r=find(angle2_unique==Result.angle2_deg(i));

    c=find(angle1_unique==Result.angle1_deg(i));


    FAVG_grid(r,c)=Result.F_avg_N(i);

    FDIFF_grid(r,c)=Result.F_diff_N(i);

end



%% =========================================================
% 图1 平均推力三维图
% ==========================================================


figure


surf(A1,A2,FAVG_grid,...
    'EdgeColor',[0.3 0.3 0.3],...
    'LineWidth',0.5)


hold on


plot3(Result.angle1_deg,...
      Result.angle2_deg,...
      Result.F_avg_N,...
      '.',...
      'MarkerSize',10)


plot3(BestResult.angle1_deg,...
      BestResult.angle2_deg,...
      BestResult.F_avg_N,...
      'p',...
      'MarkerSize',12,...
      'LineWidth',1.5)


hold off



set(gca,...
    'FontName','Times New Roman',...
    'FontSize',12,...
    'LineWidth',1)



xlabel(['\fontname{SimSun}永磁体1宽度角 ',...
        '\fontname{Times New Roman}\it\alpha_1\rm (deg)'],...
        'FontSize',12,...
        'Interpreter','tex')


ylabel(['\fontname{SimSun}永磁体2宽度角 ',...
        '\fontname{Times New Roman}\it\alpha_2\rm (deg)'],...
        'FontSize',12,...
        'Interpreter','tex')


zlabel(['\fontname{SimSun}平均推力 ',...
        '\fontname{Times New Roman}\itF_{avg}\rm (N)'],...
        'FontSize',12,...
        'Interpreter','tex')



grid on
box on

set(gca,'GridLineStyle','--')

view(45,30)



set(gcf,...
    'Units','centimeters',...
    'Position',[10,5,11,8])



%% =========================================================
% 图2 推力波动三维图
% ==========================================================


figure


surf(A1,A2,FDIFF_grid,...
    'EdgeColor',[0.3 0.3 0.3],...
    'LineWidth',0.5)



hold on


plot3(Result.angle1_deg,...
      Result.angle2_deg,...
      Result.F_diff_N,...
      '.',...
      'MarkerSize',10)



plot3(BestResult.angle1_deg,...
      BestResult.angle2_deg,...
      BestResult.F_diff_N,...
      'p',...
      'MarkerSize',12,...
      'LineWidth',1.5)



hold off



set(gca,...
    'FontName','Times New Roman',...
    'FontSize',12,...
    'LineWidth',1)



xlabel(['\fontname{SimSun}永磁体1宽度角 ',...
        '\fontname{Times New Roman}\it\alpha_1\rm (deg)'],...
        'FontSize',12,...
        'Interpreter','tex')


ylabel(['\fontname{SimSun}永磁体2宽度角 ',...
        '\fontname{Times New Roman}\it\alpha_2\rm (deg)'],...
        'FontSize',12,...
        'Interpreter','tex')


zlabel(['\fontname{SimSun}推力最大差值 ',...
        '\fontname{Times New Roman}\it\Delta F\rm (N)'],...
        'FontSize',12,...
        'Interpreter','tex')



grid on
box on

set(gca,'GridLineStyle','--')


view(45,30)



set(gcf,...
    'Units','centimeters',...
    'Position',[10,5,11,8])