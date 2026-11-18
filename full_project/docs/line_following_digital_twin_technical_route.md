# 循迹小车数字孪生仿真器：技术路线与实施指引

本文件是项目计划书的技术实施版。它回答“先做什么、使用哪些 Simulink 模块、每一步如何验证、出现问题怎样降级”。建议把它和 `line_following_digital_twin_project_plan.md` 放在同一个 `docs` 文件夹中使用。

## 1. 技术路线总览

采用“离线地图预处理 + Simulink 离散闭环 + MATLAB 后处理”的三段式路线：

```text
MATLAB脚本
  赛道照片 → 二值地图 → 坐标比例 → MAT/PNG输入
                         ↓
Simulink模型
  地图 → 8路传感器 → 误差 → PID → 电机响应 → 差速运动 → 位姿
    ↑_________________________________________________________↓
                         闭环反馈
                         ↓
MATLAB后处理
  logsout/To Workspace → 指标 → 状态提示 → 曲线和CSV
```

第一版只要求普通仿真模式能运行。不要先做 Simscape、代码生成、ESP32 通信或三维动力学。

推荐的模块顺序是：

```text
TrackMap
 → SensorGeometry
 → GraySensorReadout
 → LineError
 → PIDController
 → MotorResponse
 → DifferentialDrive
 → Evaluation/Logging
```

每个模块完成后单独测试，再连接下一个模块。不要一开始把整条反馈线一次性连完。

## 2. 开始前的环境检查

先在 MATLAB 命令窗口执行：

```matlab
ver
which simulink
license('test','Simulink')
```

确认能够打开 Simulink。若要直接处理照片，检查图像处理相关函数：

```matlab
which imread
which im2gray
which imbinarize
which imwarp
```

`imread` 通常足够读取图片；`im2gray`、`imbinarize`、`imwarp` 的可用性取决于安装的工具箱和版本。如果照片处理函数不完整，先在其他图像工具中把照片处理为黑白 PNG，再从 MATLAB 读取，不能让照片处理阻塞核心建模。

建议使用 MATLAB 脚本初始化模型参数，并把几何量、PID 参数和初始状态集中管理。Simulink 的块参数可以使用工作区变量；后期再用 Dashboard Edit 或 Slider 连接学生可调参数。

## 3. 赛道照片到二维地图

### 3.1 拍照和格式要求

照片不需要重建为三维物体。它只需要成为“黑线在哪里”的二维数据源。

拍摄和处理要求：

- 尽量垂直俯拍，减少透视变形。
- 黑色赛道与浅色背景有明显对比。
- 裁剪掉桌面、阴影和其他黑色物体。
- 记录地图实际宽度和高度，至少在一条边放置尺子。
- 优先保存为 PNG；JPEG 只作为原始照片，不作为最终掩膜。

### 3.2 最小预处理脚本

```matlab
% preprocess_track.m
img = imread("track_photo.jpg");
gray = im2gray(img);

% 黑线为1，白底为0。threshold需要根据照片调整。
threshold = 0.40;
trackMask = im2double(gray) < threshold;

% 如果有小噪点，可在图像工具箱可用时执行：
% trackMask = bwareaopen(trackMask, 30);

imshow(trackMask);
title("Binary track mask: black line = 1");

map_width_m = 1.20;       % 必须替换成实测值
map_height_m = 0.80;      % 必须替换成实测值
meters_per_pixel_x = map_width_m / size(trackMask, 2);
meters_per_pixel_y = map_height_m / size(trackMask, 1);

save("track_data.mat", "trackMask", "map_width_m", "map_height_m", ...
    "meters_per_pixel_x", "meters_per_pixel_y");
imwrite(trackMask, "track_mask.png");
```

### 3.3 透视校正的取舍

如果地图是近似俯拍，先跳过透视校正。若赛道边缘明显呈梯形，再使用四个角点进行透视变换。透视校正需要四个照片像素点和四个目标矩形点；校正后再做阈值化。

第一版的判断标准是：把初始小车和8个传感器点画在地图上，传感器点必须落在预期位置。如果点的位置不对，先修坐标系，不要调 PID。

## 4. 统一坐标系和图像映射

整个模型只使用一个坐标约定：

```text
世界坐标 x：向右为正
世界坐标 y：向上为正
车体角 theta：逆时针为正
图像列 column：向右为正
图像行 row：向下为正
```

如果图片尺寸为 `H × W`，世界坐标原点放在地图左下角，则：

```matlab
column = 1 + round(X / meters_per_pixel_x);
row    = H - round(Y / meters_per_pixel_y);
```

访问图片前必须做边界保护：

```matlab
inside = column >= 1 && column <= W && row >= 1 && row <= H;
if inside
    value = trackMask(row, column);
else
    value = 0;
end
```

建议在地图上标出：

- 世界坐标原点；
- `x` 轴和 `y` 轴；
- 起点位置；
- 初始车头方向；
- 赛道宽度和传感器阵列宽度。

## 5. Simulink 模型的具体搭建顺序

### 5.1 第一步：只做开环差速运动

新建 `LineFollowerTwin.slx`，先不放地图和传感器。

需要的基础块：

```text
Constant 或 Inport × 2       左右轮命令
Gain                         命令到轮速比例
Sum                          计算平均速度和速度差
Gain                         乘以1/2和1/L
Trigonometric Function        cos(theta)、sin(theta)
Integrator × 3               x、y、theta
Scope                        显示位姿
```

使用以下关系：

```text
vL = km * uL
vR = km * uR
v  = (vL + vR) / 2
w  = (vR - vL) / L
dx = v*cos(theta)
dy = v*sin(theta)
dtheta = w
```

验收方式：

| 输入 | 预期现象 |
|---|---|
| `uL=uR>0` | 沿车头方向直行 |
| `uL>uR` | 按约定方向转弯 |
| `uL<uR` | 向相反方向转弯 |
| `uL=-uR` | 原地旋转 |
| `uL=uR=0` | 位姿保持不变 |

如果左右转向和预期相反，交换差速公式的符号或左右命令连接。此时不要调整 `Kp/Ki/Kd`。

### 5.2 第二步：加入虚拟传感器几何

假设8路传感器位于车头前方，局部坐标为：

```matlab
sensor_x_local = sensor_front_m;
sensor_y_local = sensor_spacing_m * [-3.5 -2.5 -1.5 -0.5 ...
                                      0.5  1.5  2.5  3.5];
```

对每个传感器进行坐标旋转和平移：

```matlab
X = x + cos(theta)*sensor_x_local - sin(theta)*sensor_y_local(i);
Y = y + sin(theta)*sensor_x_local + cos(theta)*sensor_y_local(i);
```

这一部分可以使用 MATLAB Function block，输出8个传感器的世界坐标和0/1结果。MATLAB Function block会在Simulink每个时间步执行函数，也可以把地图矩阵作为参数变量传入；若未来考虑代码生成，需要遵守该模块支持的 MATLAB 语法限制。官方说明见 [MATLAB Function block](https://www.mathworks.com/help/simulink/slref/matlabfunction.html)。

建议函数接口为：

```matlab
function [sensor, sensorX, sensorY] = readTrackSensors( ...
    x, y, theta, trackMask, metersPerPixelX, metersPerPixelY, ...
    sensorFront, sensorSpacing)
```

对于第一版，使用普通仿真模式和固定尺寸 `trackMask`。如果 MATLAB Function block 对图片矩阵参数报尺寸错误，先把地图变成固定尺寸，例如 400×300；不要马上改用更复杂的 S-Function。

### 5.3 第三步：计算线位置和误差

用 `Dot Product`、`Sum` 或 MATLAB Function 计算：

```text
weighted_sum = sum(sensor_i * weight_i)
active_sum = sum(sensor_i)
line_position = weighted_sum / active_sum
```

当 `active_sum==0` 时：

```text
line_detected = 0
off_track = 1
line_error = 0
```

控制器收到 `off_track=1` 后停止命令。该处理比继续使用上一个误差更容易解释和测试。

误差必须做归一化：

```text
error_normalized = line_position / 3.5
```

让误差范围接近 `[-1,1]`，再将它送入 PID。

### 5.4 第四步：建立P、PD和PID三种控制模式

建议先用分支或 Variant Subsystem 保存三个教学状态：

```text
P   : Kp*e
PD  : Kp*e + Kd*de/dt
PID : Kp*e + Ki*integral(e) + Kd*de/dt
```

如果 Variant Subsystem 对当前版本过于复杂，直接在同一个 PIDTeachingController 中保留三个支路，把 `Ki` 默认设为0即可。

每个支路必须输出到显示端：

```text
P_term, I_term, D_term, correction
```

不要只输出最终 `correction`，否则学生看不出三个参数分别做了什么。

### 5.5 第五步：添加电机响应和输出保护

核心版本使用比例响应：

```text
left_speed  = km * left_command
right_speed = km * right_command
```

如果第5周仍有时间，再用 Transfer Fcn 或离散一阶差分表示：

```text
v(k+1) = v(k) + Ts/tau * (km*u(k) - v(k))
```

左右命令分别经过 Saturation：

```text
0 <= left_command <= u_max
0 <= right_command <= u_max
```

如果允许反向旋转，范围改为 `[-u_max,+u_max]`，但循迹小车第一版使用非负前进速度更容易解释。

## 6. PID 实现的工程细节

### 6.1 离散采样

固定步长建议从 `Ts=0.02 s` 开始。控制、传感器和运动模型先全部使用同一采样时间；之后若需要，可以让显示和数据记录降采样，但不要让控制回路出现隐含的不同采样率。

### 6.2 积分限幅

积分项使用：

```text
I_raw(k+1) = I(k) + Ki*e(k)*Ts
I(k+1) = clamp(I_raw(k+1), -I_max, I_max)
```

学生把 `Ki` 调大时，界面应显示 I 项和是否触发限幅。这样“积分过强”的提示有可观察依据。

### 6.3 微分滤波

不要直接把0/1传感器跳变作为理想微分输入。至少使用离散差分加一阶低通，或者使用 Simulink 离散 PID block 的微分滤波设置。微分滤波的作用是抑制传感器跳变带来的命令尖峰，不是掩盖错误的坐标或阈值。

### 6.4 参数范围

先把 `error_normalized` 和命令都限制在 `[-1,1]` 或 `[0,1]`，然后用三组小实验得到增益范围：

```text
Kp：从很小值开始，直到小车能够明显转向
Kd：从0开始，直到摆动被明显抑制
Ki：从0开始，只在存在持续偏差时增加
```

不要直接复制网上的 PID 数值，因为传感器权重、采样时间、基础速度和 `km` 不同，数值没有可比性。

## 7. 信号记录与后处理

### 7.1 优先使用 Signal Logging

将以下信号标记为 logging：

```text
x, y, theta
sensor_vector
line_error
P_term, I_term, D_term
left_command, right_command
left_speed, right_speed
off_track, status_code
```

Simulink 可以把标记的信号保存到 `logsout` 并送入 Simulation Data Inspector，用来比较不同 PID 运行。官方说明见 [Signal logging](https://www.mathworks.com/help/simulink/gui/signallogging.html) 和 [Visualize and Access Signal Logging Data](https://www.mathworks.com/help/simulink/ug/accessing-signal-logging-data.html)。

### 7.2 简单替代：To Workspace

如果 Signal Logging 配置不熟，可以在需要的信号后面接 `To Workspace`，格式先选 `Timeseries` 或 `Structure With Time`。官方文档列出了 `To Workspace` 对标量、向量和数组信号的支持：[To Workspace](https://www.mathworks.com/help/simulink/slref/toworkspace.html)。

第一版只需保存一个 `logsout` 或 `simout`，再用 MATLAB 脚本计算指标，不要同时维护很多互相重复的保存方式。

### 7.3 后处理脚本结构

```matlab
% evaluate_run.m
logs = out.logsout;
t = logs.getElement("line_error").Values.Time;
e = logs.getElement("line_error").Values.Data;
uL = logs.getElement("left_command").Values.Data;
uR = logs.getElement("right_command").Values.Data;

MAE = mean(abs(e), "omitnan");
PeakError = max(abs(e), [], "omitnan");
saturationRatio = mean(uL >= 0.999 | uR >= 0.999);

result = table(MAE, PeakError, saturationRatio);
writetable(result, "results/run_summary.csv");
```

信号名必须在模型中保持一致，否则后处理脚本会因重命名而失效。

## 8. 教学状态提示的实现路线

不要先开发动态文本系统。推荐输出多个数值和布尔信号，再用 Dashboard Display、Lamp 或 Scope 显示。

### 8.1 窗口统计

对最近 `W=1 s` 的误差保存窗口：

```text
MAE_W = mean(abs(e_window))
Peak_W = max(abs(e_window))
zero_crossings_W = count(sign changes)
sat_ratio_W = mean(saturated_window)
```

使用 Moving Average、MinMax Running Resettable 或 MATLAB Function 都可以。第一版如果窗口模块难以配置，可以在仿真结束后由 `evaluate_run.m` 计算，状态灯先使用当前样本的简单条件。

### 8.2 优先级顺序

一个时刻只显示一个主状态，按以下优先级判断：

```text
1. 数值异常
2. 脱线
3. 电机饱和
4. 振荡明显
5. 响应偏慢
6. 稳定
```

这样同一时刻既振荡又饱和时，界面不会出现互相矛盾的主要提示。旁边可以继续显示原始指标。

### 8.3 预期输出的显示

在电机输出面板同时显示：

```text
左命令：0.62       左仿真轮速：0.55       左预期轮速：0.62
右命令：0.38       右仿真轮速：0.35       右预期轮速：0.38
左残差：-0.07      右残差：-0.03
```

当使用无惯性的第一版时，仿真轮速和预期轮速几乎相同，这是正常结果；模型不匹配实验加入电机时间常数或左右 `km` 差异后，残差才具有明显教学意义。

## 9. 验证顺序和通过标准

每完成一个层级就保存一个可运行版本：

### V0：坐标和地图

- 地图可以显示。
- 原点、比例和坐标轴正确。
- 手动放置传感器点时，点的位置可解释。

### V1：开环运动

- 左右相同命令能够直行。
- 速度差能够转弯。
- 停止命令不会继续移动。

### V2：传感器

- 小车沿直线移动时，黑线经过8个传感器的顺序正确。
- 左偏与右偏对应的误差符号正确。
- 地图外采样不会报错。

### V3：闭环

- P控制能够在简单直线或大弯上修正。
- PD控制比同样的P控制有更少的摆动，或至少能产生可解释的差异。
- 左右输出不会超出限制。

### V4：教学界面

- 修改 `Kp/Ki/Kd` 后下一次运行确实使用新值。
- Reset 清空积分、历史、轨迹和指标。
- 三组参数可以导出并比较。

### V5：异常和报告

- 全部传感器失效会停止车辆并显示脱线。
- 电机不一致会产生轮速残差。
- 日志包含参数和单位。
- 报告中不会把仿真轮速写成真实测量。

## 10. 八周按技术依赖排序

| 周 | 技术任务 | 必须留下的文件/证据 |
|---:|---|---|
| 1 | 环境检查、地图预处理、坐标定义 | `track_data.mat`、地图截图、参数表 |
| 2 | 开环差速运动 | V1模型、直行/转弯截图 |
| 3 | 传感器几何和地图采样 | 8路传感器动画或Scope截图 |
| 4 | 误差、P和PD | P/PD对比曲线 |
| 5 | PID、限幅、脱线和电机响应 | 完整二维闭环模型 |
| 6 | Dashboard输入和信号记录 | 三参数界面、`logsout`或`simout` |
| 7 | 指标、状态提示和测试矩阵 | CSV、四种状态截图 |
| 8 | 报告、演示、可选三维 | 最终模型、报告、演示素材 |

每周结束时至少保存一个能运行的版本和一张证据截图，不要等第8周才确认模型是否可运行。

## 11. 时间不够时的降级路线

如果第3周结束仍未能让传感器正确读取照片，采用以下降级顺序：

1. 只取照片中的一段无分叉直线和大弯。
2. 将赛道照片手工处理为固定尺寸二值 PNG。
3. 暂时用中心线坐标或椭圆数学赛道验证控制器。
4. 地图采样成功后再替换回照片掩膜。

如果第5周结束 PID 尚未稳定：

1. 固定 `Ki=0`，只展示P和PD。
2. 使用无惯性电机模型。
3. 只保留稳定、振荡和脱线三种状态。
4. 放弃三维和噪声实验，把时间用于坐标、采样和复位。

如果 Dashboard 连接耗时：

1. 先用 Constant block 的 `Kp/Ki/Kd` 工作区变量。
2. 用 MATLAB 脚本循环运行三组参数。
3. 最后再加 Edit 或 Slider 作为界面改善。

## 12. 本项目中“数字孪生”技术表述的边界

当前仿真有动态 PE、VE、DD、Ss 和 CN：

- PE 是与已选实体硬件对应的虚拟小车。
- VE 是传感器、运动学和电机响应模型。
- DD 是每一步的传感器、控制量、状态、预测和残差。
- Ss 是教学评价、状态和参数建议。
- CN 是闭环信号路径，以及未来替换为 ESP32 的接口。

但当前没有真实物理实体发来的实时数据。因此报告中使用“数字孪生教学仿真原型”或“面向实体扩展的数字孪生模型”，不要写成已经完成了真实设备同步。

## 13. 下一次实验的具体操作清单

下一次只安排2–3小时，按以下顺序做：

1. 新建 `init_line_follower.m`，写入 `Ts、L、sensor_front、sensor_spacing、Kp、Ki、Kd`。
2. 把赛道照片裁剪为一张简单黑线白底图，并保存 `track_mask.png`。
3. 在 MATLAB 中显示图像尺寸、地图坐标轴和实际宽高比例。
4. 新建 `LineFollowerTwin.slx`，只搭 `x、y、theta` 三个积分器。
5. 用左右两个 Constant 输入验证直行和转弯。
6. 暂时不要搭 PID，不要搭三维，不要做界面。
7. 保存开环模型和一张坐标验证截图。

完成这7步后，才进入传感器建模。这样每次实验都能得到一个明确成果，不会同时面对地图、控制器和界面三个不确定因素。

## 14. 官方技术参考

- [MATLAB Function block](https://www.mathworks.com/help/simulink/slref/matlabfunction.html)：在 Simulink 每个时间步执行自定义 MATLAB 算法，也可以声明工作区参数。
- [Signal logging](https://www.mathworks.com/help/simulink/gui/signallogging.html)：把标记信号记录到工作区和 Simulation Data Inspector。
- [Visualize and Access Signal Logging Data](https://www.mathworks.com/help/simulink/ug/accessing-signal-logging-data.html)：从 `SimulationOutput` 和 `logsout` 访问仿真数据。
- [To Workspace](https://www.mathworks.com/help/simulink/slref/toworkspace.html)：将标量、向量或数组信号保存到 MATLAB 工作区。
- [Dashboard Edit](https://www.mathworks.com/help/simulink/slref/edit.html)：在仿真期间输入或修改块参数并建立交互式控制面板。
- [Discrete PID Controller](https://www.mathworks.com/help/simulink/slref/discretepidcontroller.html)：离散 PID、输出限幅和抗积分饱和的官方说明。
