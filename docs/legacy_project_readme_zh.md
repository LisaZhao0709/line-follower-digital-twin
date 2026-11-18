# line_follower_twin

面向中小学生 PID 教学的循迹小车数字孪生仿真器（MATLAB/Simulink 版）。
本目录为 `line_follower_twin/` 项目根目录，按八周计划逐周推进。

当前 Python 网页、MQTT、状态同步与诊断应用位于 `web_app/`，操作见[网页使用说明](web_app/README.md)。目录结构、全部主源码职责和两条运行路线见[项目架构与代码导读](项目架构与代码导读.md)。

## 已实现的前四周工程（2026-10-04）

使用 `weeks1_4/` 中的工程：已附内侧闭环地图、自动生成的开环与 P/PD Simulink 模型、验证脚本、实验曲线与数据。

入口文档：[前四周使用与工作细则](weeks1_4/START_HERE_中文.md)。在 MATLAB 中切换到该目录后运行 `START_WEEKS1_4`。

详细复核后的入口：[复核后使用说明](weeks1_4/复核后使用说明.md)，运行 `OPEN_REVIEWED_SIMULATION`。新增解析运动学模型、严格起终点计时、正确的0.20秒脱线时限、逐样本校验及独立复算记录。

`weeks1_4/` 仅需 MATLAB R2025b + Simulink，不需要 Image Processing Toolbox。下面保留的是早期第一周模板及其环境要求，旧模板中的 NaN 和图像工具箱配置无需用于新工程。

## 环境

- MATLAB R2025a
- 需要工具箱：图像处理工具箱（Image Processing Toolbox）——运行 `license('test','Image_Toolbox')` 应为 1
- Simulink（第 2 周起使用）：`license('test','Simulink')` 应为 1

## 目录结构

```text
line_follower_twin/
├── init_line_follower.m   参数初始化（几何 / 仿真 / PID / 初始姿态）
├── preprocess_track.m     赛道照片 -> 二值地图 track_mask.png + track_data.mat
├── show_track_map.m       显示地图、坐标轴、起点、车体与 8 路传感器点
├── track_mask.png         二值地图（黑线=1）
├── track_data.mat         地图数据 + 像素比例
├── photos/                原始赛道照片
├── results/figures/       验收截图与曲线
└── report/                最终报告
```

## 启动顺序（第 1 周）

1. 把赛道照片放入 `photos/`，例如 `photos/track_photo.jpg`。
2. 用尺子量好实际尺寸（见下方参数表），填入 `preprocess_track.m` 配置区。
3. 运行 `preprocess_track.m`，生成 `track_mask.png` 与 `track_data.mat`。
4. 把实测尺寸与初始姿态填入 `init_line_follower.m`。
5. 运行 `init_line_follower.m`。
6. 运行 `show_track_map.m`，检查传感器点位置。
7. 保存 `results/figures/week1_coordinate_check.png`。

## 坐标约定（全程统一）

```text
世界 x：向右为正       世界 y：向上为正
车体角 theta：逆时针为正
图像列 column：向右为正   图像行 row：向下为正
世界原点：地图左下角
```

像素查询：

```matlab
column = 1 + round(X / meters_per_pixel_x);
row    = H - round(Y / meters_per_pixel_y);
% 越界一律返回 0，并计为脱线
```

## 第 1 周参数表（待实测填写）

| 参数 | 符号/变量 | 单位 | 实测值 |
|---|---|---:|---:|
| 地图实际宽度 | `map_width_m` | m | |
| 地图实际高度 | `map_height_m` | m | |
| 黑线宽度 | `line_width_m` | m | |
| 小车轴距 | `wheel_base_m` | m | |
| 车体长度 | `body_length_m` | m | |
| 车体宽度 | `body_width_m` | m | |
| 传感器前置距离 | `sensor_front_m` | m | |
| 传感器间距 | `sensor_spacing_m` | m | |
| 起点 x | `x0` | m | |
| 起点 y | `y0` | m | |
| 初始车头角 | `theta0` | rad | 0 |

## 默认教学参数

| 参数 | 值 | 说明 |
|---|---:|---|
| `Ts` | 0.02 s | 固定步长 |
| `base_speed` | 0.35 | 基础速度（归一化） |
| `Kp` | 0.80 | 比例增益（学生可调） |
| `Ki` | 0.00 | 积分增益（学生可调） |
| `Kd` | 0.08 | 微分增益（学生可调） |
| `integral_limit` | 0.30 | 积分限幅 |

## 第 1 周验收清单

- [ ] `photos/` 中有一张尽量正俯拍的赛道照片
- [ ] 参数表实测值全部填写
- [ ] `track_mask.png` 黑线连续、背景干净、无大块噪点
- [ ] `track_data.mat` 含 `trackMask`、`map_width_m`、`map_height_m`、像素比例
- [ ] `show_track_map.m` 中 8 个传感器点落在车头前方第一排，且起点合理
- [ ] 截图 `results/figures/week1_coordinate_check.png` 已保存

## 说明

本项目为面向实体扩展的数字孪生仿真原型，未接入真实 ESP32 遥测。
报告中“轮速”等状态一律称为“仿真轮速”或“模型估计”，不称为真实测量。
