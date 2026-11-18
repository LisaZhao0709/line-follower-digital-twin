# L5 孪生模型层 (Twin Model Layer)

> 2026-11-18 更新：使用[第五层检查与演示说明](../../第五层检查与演示说明.md)中的操作步骤与口播。原有单步预测并不是一辆永久独立运行的闭环虚拟车；现在明确区分“单步预测后直接观测校正”“连续健康指令回放”和“一秒恒指令条件预测”。

## 当前可验证的输出

- `residual_left_mps` / `residual_right_mps` 是左右轮的有符号残差；兼容字段 `residual_mps` 仍是最大绝对残差这个标量。
- `prior_xy` / `prior_theta_rad` 是根据上一条控制量计算的本帧先验；`innovation_m` 以毫米显示，航向创新度为 `innovation_theta_rad`。
- `nominal_*` 是从首次观测或最近缺口重同步点开始的健康指令回放，不逐帧校正位置，也没有另一个独立循迹 PID。`nominal_drift_m` 显示实测与参考的持续偏移。
- `forecast` 包含当前位姿到一秒后共11个条件预测点，前提是当前控制量不变。
- `prediction_valid` 只在20ms连续观测间为真。缺口后重新对齐，不使用未知的缺失指令来制造创新度。暂停心跳不增加 `updates`，也不刷新模型计算时间。
- 模型输出进入 L6 窗口分析、历史轨迹、接收 CSV 和分析 JSON。页面的两种实验由源端命令回执确认执行。

## 1. 核心定位与职责
L5 孪生模型层是数字孪生系统的**核心算法大脑**，对应数字孪生五维模型中的“虚拟实体（VE）”。
在这一层，我们构建了一个小车的**无故障健康标称模型**。它在接收端独立运行，不知道物理端是否被注入了故障，通过对比虚拟期望与物理实际，发掘潜在的性能劣化与异常偏差。

- **核心任务**：状态更新、模型预测、偏差计算、同步修正。
- **核心输入**：L4 管理层输出的有效遥测数据（包含小车控制指令 $u_L, u_R$ 与物理轮速 $v_L, v_R$）。
- **主要输出**：小车的虚拟孪生状态（包含标称期望轮速、轮速残差 $e_v$、先验预测位置 `prior_xy`、预测偏差创新度 `innovation_m`）。

## 2. 核心模块与文件分工
- `twin_model.py`（虚拟实体与预测校正器）：
  - `TwinModel`：基于小车标称参数（$k_m=0.35$，$L=0.12\text{ m}$），根据控制指令计算理论上健康小车应达到的左右轮速。
  - **轮速残差计算**：对比实际测量轮速与理论期望轮速，得出驱动残差 `residual_mps`。
  - **状态先验推演与创新度更新**：利用离散运动学推演小车的先验位置 `prior_xy`，并与实际回传位置比较，输出几何跟踪创新度 `innovation_m`。

## 3. 视频讲解英文口播（操作说明保持中文）
> Layer five provides a healthy model that we can compare with the received observations. It does not read the source fault settings. Its nominal wheel speed is always zero point three five multiplied by the corresponding motor command.
>
> First, I will start the healthy baseline. The update count increases while the measured trajectory and healthy reference overlap. Both wheel-speed residuals are close to zero. Zero residual is the correct result when the simulated asset agrees with the nominal model; it does not mean that the model is inactive.
>
> Next, I will start the left-wheel reduction experiment. This creates a new run from the same initial state, with the same PID settings, ideal sensor environment and seed. Only the simulated left-wheel response is reduced by twenty percent. The left measured speed is now below its nominal value, producing a negative residual. The right-wheel residual remains close to zero.
>
> There are two different position comparisons. The one-step prediction uses the previous commands and is corrected by each new pose observation. Its position innovation is shown in millimetres. The orange healthy replay starts from the initial observation and continues without position correction between consecutive samples. Its growing separation from the blue measured trajectory demonstrates persistent model mismatch.
>
> The purple dashed curve is a conditional forecast: it assumes that the current commands remain constant for one second. The actual PID will update those commands, so this is not a guaranteed future route.
>
> When upload is interrupted, the twin retains its last observation. After recovery, missing commands cannot be reconstructed, so the reference is realigned and the missing interval is not treated as a valid prediction error. Layer six then uses the healthy reference and residuals as evidence for its diagnostic window.

