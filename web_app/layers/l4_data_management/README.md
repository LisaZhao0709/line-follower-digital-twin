# L4 数据管理层 (Data Management Layer)

## 1. 核心定位与职责
L4 数据管理层负责接收来自 L3 通信层的网络报文，进行**严格的合法性校验、脏数据清洗、时序去重、网络缺口统计与历史持久化归档**，对应数字孪生五维模型中的“孪生数据（DD）”。

- **核心任务**：数据校验、清洗、去重、存储。
- **核心输入**：L3 接收解码后的 JSON 报文。
- **主要输出**：合规可信的有效遥测数据流、接收历史序列、持久化落盘文件（`source.csv`、`summary.json`）。

## 2. 核心模块与文件分工
- `validator.py`（数据校验与清洗器）：
  - `validate_observation`：执行 Schema 契约校验（会话 ID、字段完整性、物理数值范围约束）。
  - `TelemetryReceiver`：基于消息流水号 `seq` 实现重复帧自动去重；检测并统计网络丢包缺口（`gaps`）；通过数据年龄（`age_s`）动态判定数据新鲜度（`good / stale`）。
- `storage.py`（实验数据归档与存储）：
  - 维护实验历史队列。
  - 在每轮实验完成时将全采样序列持久化写入硬盘（`results/{run_id}/`）。
  - 支持向用户导出符合 UTF-8 BOM 标准的 CSV 历史数据报表。

## 3. 视频讲解英文口播（操作说明保持中文）
> Layer four checks whether a received observation is usable. It validates the session, numeric ranges, sensor array lengths, sequence order and simulation time.
>
> A duplicate message must not become a new measurement or advance the twin again. Missing sample indices are recorded as observation gaps. Data freshness is tracked separately: a new valid message can make the connection fresh even though earlier samples are missing.
>
> These checks provide the accepted observation history used by the model and diagnostics. Completed experiments save their source records. We can export the received observations, together with model results, as a separate CSV file.
>
> Keeping source records and received records distinct helps us see what the asset produced and what the digital side actually observed.

