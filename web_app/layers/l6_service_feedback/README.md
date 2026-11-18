# L6 服务反馈层 (Service Feedback Layer)

## 1. 核心定位与职责
L6 服务反馈层是数字孪生应用真正产生**业务价值与闭环控制赋能**的层次，对应数字孪生五维模型中的“服务（Ss）”。
该层利用 L5 孪生模型推导的残差、偏差和历史序列，进行**深层次的状态健康体检、故障根因追溯、控制性能评估并自动生成调优决策**，进而将控制指令反向注入到物理实体中，形成“虚实双向闭环”。

- **核心任务**：状态监测、分析、预测、控制决策。
- **核心输入**：L4 的干净历史观测序列、L5 的虚拟预测与轮速残差。
- **主要输出**：
  1. 结构化诊断报告（状态判定、证据列表、判定规则、改进措施）；
  2. 智能控制优化指令（自适应调节 PID 参数、小车启停动作）。

## 2. 核心模块与文件分工
- `diagnostics.py`（智能诊断与决策服务）：
  - **电机响应比评估**：计算真实轮速与标称轮速的回归斜率。若左轮输出低于标称值 90%，诊断为“左侧驱动响应衰减”，并给出硬件排查建议。
  - **蛇行摆头（Hunting Oscillation）检测**：统计 1 秒内穿过赛道中心线的过零次数。大于等于 8 次判定为参数失稳摆头，建议调小 $K_p$、调大 $K_d$。
  - **执行饱和与脱线预警**：检测电机占空比是否频繁越界（$\ge 0.99$）以及 8 路传感器失线风险。
  - **闭环参数优化决策**：根据诊断结论，自动生成 `recommendation` 调优方案。
- `command_service.py`（控制决策管理服务）：
  - 维护指令队列，提供带 UUID 防伪标识的控制报文生成。
  - 监听物理端上报的 `ack` 回执，保证指令“发送-排队-执行-确认”的全流程闭环。

## 3. 视频讲解英文口播（操作说明保持中文）
> Layer six turns observations into evidence and possible next steps. It examines a recent window rather than diagnosing a fault from a single speed spike.
>
> In this experiment, the left response ratio is about eighty percent, while the right side remains close to one hundred percent. Together with the signed residual, this supports a finding of reduced drive response on the left. It does not identify a specific failed electrical or mechanical component.
>
> The Clear simulated fault and rerun button restores the simulation coefficient and starts a new comparison. It is not a physical motor repair or an online calibration procedure.
>
> For control problems, the service can propose candidate PID settings using explicit rules and the current observations. These settings still need a comparison run. After sending a command, we wait for the source acknowledgement and check the new run identifier and telemetry. We then compare tracking error, saturation and lap completion instead of assuming that a suggested setting must be better.

