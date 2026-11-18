# 循迹小车：前四周已实现工程

适用环境：MATLAB R2025b + Simulink。无需 Image Processing Toolbox、Simscape 或机器人相关工具箱。地图和可编辑的 `.slx` 模型已附在工程内。

**后续详细复核已完成。** 最新使用方式见 [复核后使用说明](复核后使用说明.md)：运行 `OPEN_REVIEWED_SIMULATION` 打开单周期解析运动模型和可追溯的实际实验结果。以下介绍保留为原四周教学模型的入门说明；旧圈时和首次验收结果属于历史版本。

## 第一次使用

在 MATLAB 命令窗口粘贴：

```matlab
cd('<repository>\weeks1_4')
START_WEEKS1_4
```

脚本会显示地图、打开闭环模型和已验收的 PD 结果。若尚无验收结果，会先执行完整验收。运行期间不要移动或重命名工程文件。仿真时间 100 s 表示模型中的时间，实际计算通常更快。

之后可以直接比较：

```matlab
run_demo('P', 0.45)             % 比例控制：Kd=0
run_demo('PD', 0.45, 0.03)      % 比例+微分
run_demo('P', 0.05)             % P太弱：在弯道脱线并停止
```

每次调用都是从相同初始位置重新仿真，重新初始化误差、滤波和脱线状态；结果保存到 `results/`。`run_demo` 返回的 `lastRun` 在 MATLAB 工作区可供查看，`lastMetric` 是评价结果。相同模式再次调用时，`demo_P_*` 或 `demo_PD_*` 文件会被新结果更新；验收实验 `P_baseline`、`PD_default`、`P_weak` 保留在各自独立文件中。

看小车沿地图移动：

```matlab
play_run                         % 播放附带的已验收PD轨迹
play_run(lastRun)                % 播放最近一次run_demo结果
```

## 你只需要认识的 Simulink 操作

1. **打开模型**：双击 `models/LF_Week4_PD.slx`，或运行启动脚本。
2. **查看模块内部**：双击一个带名称的大矩形，例如 `DifferentialDrive` 或 `PDController`。
3. **返回上一层**：使用模型窗口的层级导航/返回父系统按钮。
4. **查看算法**：双击 `VirtualSensors` 内的 `ReadMap`，可看到地图采样代码。
5. **查看波形**：双击 `SensorScope`、`ControlScope` 或 `PoseScope`，再按模型的 Run 按钮。
6. **查看块参数**：双击 `Gain`、`Sum`、`Unit Delay`、`Discrete-Time Integrator`；此阶段先观察，不必改连接。

模型已经接好所有线。你不需要先掌握拖放模块才能做实验。完成实验后，再从第二周的小模型学习搭建。

模型自身保存了配置和地图，在按 Run 时能直接运行默认 PD 参数。上面的 `run_demo` 命令临时设置某次实验的参数，不会永久改写模型中的默认参数。

如果以后想练习手动拖一个块：在空白画布双击，输入 `Gain`，选择该块；从一个块右侧输出端口拖到另一个块左侧输入端口即可连线。先在新建的练习模型中操作。

## 第一周：地图、坐标与比例

交付物：

- `data/track_source.png`：用户提供原图的无损读取副本。
- `data/track_mask.png`：只保留内侧黑色闭环、去掉外侧边框的地图。
- `data/track_data.mat`：逻辑掩膜、黑线感应强度、坐标比例和起点。
- `data/map_metadata.json`：比例计算与处理记录。
- `results/figures/week1_map_coordinates.png`：地图和起点放大图。

地图标定使用顶部水平线段：阈值后宽度约 5 px，已知线宽 0.02 m，因此比例取 `0.004 m/px`。图幅约 `2.56 × 1.72 m`。这是来自示意图的尺寸估计；没有把它当作实测场地尺寸。

统一坐标：原点在地图左下角，x 向右，y 向上，theta 逆时针为正。图像第1行在上方。查询关系为：

```matlab
column = 1 + X / scale;
row    = H - Y / scale;
```

像素感应强度采用双线性插值，超出地图返回0。二值地图仅决定黑线的位置；强度图保留原图黑线边缘的灰度过渡，使虚拟灰度传感器变化更平滑。没有改成另一条数学赛道，也没有抹平原图尖角。

你本周需要做：打开坐标图，核对左下角、初始车头向右、传感器在车体前方；在报告中写明“2 cm线宽标定，地图整体尺寸由图像估算”。

## 第二周：开环差速运动

模型：`models/LF_Week2_OpenLoop.slx`。

查看命令：

```matlab
open_system(fullfile(pwd,'models','LF_Week2_OpenLoop.slx'))
```

同侧两个电机先合并成一个等效驱动侧。`DifferentialDrive` 内使用原生模块实现：

```text
vL = km * uL
vR = km * uR
v  = (vL + vR) / 2
w  = (vR - vL) / L
dx = v*cos(theta)
dy = v*sin(theta)
```

`x、y、theta` 分别接一个前向欧拉的 Discrete-Time Integrator。固定步长和各积分器采样时间都是 `Ts=0.02 s`。积分器内部已经包含 Ts，前面不能再重复乘 Ts。

| 块 | 作用 | 本周应该理解的内容 |
|---|---|---|
| Constant | 左右输入 | 命令是归一化值，不是 rpm |
| Gain | 比例换算 | km 把命令换成 m/s |
| Sum | 求和/求差 | 速度和影响前进，速度差影响转向 |
| Trigonometric Function | sin/cos | theta 用弧度 |
| Product | 相乘 | 前进速度投影到 x、y |
| Discrete-Time Integrator | 保存与更新位姿 | 初值、采样时间、单位 |
| Scope | 波形显示 | x、y、theta 随时间变化 |
| To Workspace | 记录数据 | 仿真结束后仍可分析 |

手动输入可双击顶层 `LeftInput`、`RightInput`，把 Value 改成数字。重新运行会恢复同一初始位姿。建议先另存副本再练习。

验收测试用 2 s、`km=0.35 m/s`、`L=0.12 m`、零初始位置：

| 输入 | 理论结果 |
|---|---|
| uL=uR=0 | 位姿不变 |
| uL=uR=0.5 | 向右前进0.35 m |
| uL=0.3，uR=0.6 | 左转，theta增加1.75 rad |
| uL=0.6，uR=0.3 | 右转，theta减少1.75 rad |
| theta0=pi/2，uL=uR=0.5 | 向上前进0.35 m |

`week2_open_loop_tests` 自动比较实际 Simulink 结果与解析解。转弯位置允许前向欧拉离散误差，阈值 0.004 m；直线和角度误差应接近浮点精度。截图和测试表位于 `results/`。

## 第三周：8路灰度传感器

打开闭环模型的 `VirtualSensors`。

车体局部坐标：前方为正x，左侧为正y。**S1在最左边，S8在最右边**。这是对旧初始化模板中“左到右”编号歧义的明确修正；不要再混用旧模板的权重。

| 参数 | 值 | 来源 |
|---|---:|---|
| 前置距离 | 0.05 m | 仿真假设 |
| 相邻间距 | 0.008 m | 仿真假设 |
| 8点阵列总宽 | 0.056 m | 7个间距 |
| 黑线宽度 | 0.020 m | 用户提供 |

阵列先经过旋转和平移得到世界坐标，再从强度图中采样；强度 ≥0.5 时输出二值1。控制误差使用各通道强度的加权平均，显示端同时记录8路二值状态。

```text
weights = [3.5 2.5 1.5 0.5 -0.5 -1.5 -2.5 -3.5]
e = sum(strength .* weights) / sum(strength) / 3.5
```

误差正：黑线在车的左侧；误差负：黑线在车的右侧。全无黑线时输出 `detected=0`，避免除以0。控制器在短暂丢线期间保留上一有效误差；连续0.2 s丢线后停止，重新仿真复位。

`week3_sensor_tests` 验证居中、车在黑线上方、下方、地图外和90度转向。你需要查看 `week3_sensor_tests.png`，能说明各组图中哪些传感器读到线、为什么误差是正或负。

## 第四周：P / PD闭环

模型：`models/LF_Week4_PD.slx`。

信号顺序：

```text
位姿 → VirtualSensors → LineError → PDController → MotorCommands
 ↑                                                   ↓
 └──────────────── DifferentialDrive ─────────────────┘
```

`PDController` 内的 P支路用 Gain；D支路用差分、除Ts、一阶离散滤波、Gain；最后用 Sum 合并。

```text
P = Kp * e
d_raw = (e[k]-e[k-1]) / Ts
alpha = Ts / (tau+Ts)
d_filtered[k] = alpha*d_raw[k] + (1-alpha)*d_filtered[k-1]
D = Kd * d_filtered
correction = P + D
uL = clamp(base-correction, 0, 1)
uR = clamp(base+correction, 0, 1)
```

基础命令0.35对应理想轮线速度0.1225 m/s；默认 `Kp=0.45`、`Kd=0.03`。Ki暂为0，第五周才加积分支路。

本周三组实验保持地图、速度、起点完全相同：

| 实验 | 参数 | 应观察的结果 |
|---|---|---|
| P弱 | Kp=0.05，Kd=0 | 转弯修正不足，脱线后停止 |
| P基线 | Kp=0.45，Kd=0 | 能完成一圈，D项为0 |
| PD默认 | Kp=0.45，Kd=0.03 | 能完成一圈，D项参与转弯修正 |

结果文件：`results/week4_comparison.csv`、各实验 `_trace.csv`、`_run.mat`、`figures/*.png`。

不要只以圈时评价 PD。需要同时看误差MAE、误差符号变化、输出饱和和命令总变化量。一阶理想电机、低速、提前感知的模型中，P本身可能已很好；D不保证所有指标变好，应如实解释实验结果。

完成一圈要求离线参考边界进度至少达到1.0，同时返回距起点0.08m内；参考曲线没有输入控制器。`sensor_error` 是归一化感应误差，没有米单位。误差MAE只统计有效检测样本；弱P早停后的缺失样本不参与，因此不能把弱P的低MAE当作性能更好。记录的轮速是 `km*u` 得到的仿真量，不是真实小车测量。

## 复查与修改

```matlab
run_acceptance                   % 重新跑四周完整验收
cfg = project_config()           % 查看全部配置和单位
```

几何或默认参数统一在 `project_config.m` 修改。修改后可用 `build_models(true)` 重新生成模型；旧模型自动复制到 `models/backups/`，不会直接丢掉你保存的编辑。若模型仍有未保存修改，生成器会要求先保存。

本工程是课程的数字孪生教学仿真原型。前四周完成地图、运动、传感器、P/PD闭环及数据记录；第五周的积分与完整异常处理、第六周的三参数界面、第七周的教学提示规则继续按原路线推进。真实ESP32与MQTT遥测尚未接入。

## 提交证据清单

- 地图坐标图，并写清线宽已知、整体比例估计。
- 五项开环测试图和CSV。
- 8路传感器测试图和CSV。
- P弱、P基线、PD默认三组轨迹与控制曲线。
- 验收结果 `results/验收结果.md`。
- 两个可编辑 `.slx` 文件与本工程源代码。

程序自动搭建依据 MathWorks 的 [add_block](https://www.mathworks.com/help/simulink/slref/add_block.html)、[MATLAB Function配置](https://www.mathworks.com/help/simulink/ug/configure-matlab-function-blocks-programmatically.html) 和 [Discrete-Time Integrator](https://www.mathworks.com/help/simulink/slref/discretetimeintegrator.html)。
