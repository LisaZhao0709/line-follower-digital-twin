# L2 数据采集层 (Data Acquisition Layer)

## 1. 核心定位与职责
L2 数据采集层负责从 L1 物理层获取实体运动与环境信息，完成**周期性采样、添加时间戳并打包装帧**，是物理世界走向数字世界的桥梁。

- **核心任务**：数据获取、采样、时间戳、封装。
- **核心输入**：物理小车位姿、赛道环境反射率。
- **主要输出**：标准原始观测数据帧（包含 8 路传感器强度 `strengths`、二值信号 `sensors`、时间戳 `t_sim_s`、样本序号 `sample_index` 及电机控制与轮速）。

## 2. 核心模块与文件分工
- `sensors.py`（传感器阵列建模）：
  - 维护 8 路红外反射传感器的空间几何排布（前伸 50mm，间距 8mm）。
  - 模拟物理世界的噪声环境：环境光漂移、地面阴影、车体机械横向微晃动、电气高斯噪声及传感器丢包掉电。
- `telemetry_packager.py`（采样与帧封装打包器）：
  - 以 20ms（50Hz）为固定基准采样率执行数据获取。
  - 为每一帧打上单调递增的仿真时间戳 `t_sim_s` 和全局采样序号 `sample_index`。
  - 封装为完整的 Python 字典结构，供通信层上报。
- `simulation_source.py`（采集源调度器）：
  - 管理数据采集源的运行状态机（`idle / running / paused / completed`）。
  - 支持单步采集推进（`advance`）和连续采集控制。

## 3. 视频讲解英文口播（操作说明保持中文）
> Layer two turns the physical state into observations. Eight reflectance sensors are positioned across the front of the vehicle. Each sensor samples the track map at its current world position.
>
> The simulation can add changes in lighting, shadows, sensor position and measurement noise. A threshold converts sensor strengths into binary line detections. These observations are then combined with the pose, wheel speeds and controller signals in a telemetry frame.
>
> Each sample carries simulation time and a sample index. The transport adds the session and message sequence information before publication. The sampling period is twenty milliseconds, or fifty samples per simulation second.
>
> The sensor array on the right lets us connect the map geometry with the signals used by the controller. These are simulated sensor readings, rather than measurements from a connected physical sensor board.

