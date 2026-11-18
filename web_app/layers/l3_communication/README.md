# L3 通信层 (Communication Layer)

## 1. 核心定位与职责
L3 通信层负责建立**物理端（采集源）与虚拟端（数字孪生模型）之间的工业物联网通信通道**，对应数字孪生五维模型中的“连接（CN）”。

- **核心任务**：MQTT / OPC UA 配置、网络拓扑搭建、消息序列化与双向可靠传输。
- **核心输入**：L2 封装的原始观测数据、L6 决策产生的控制指令。
- **主要输出**：在网络中传输的结构化 JSON 消息报文（`telemetry` 遥测、`command` 指令、`ack` 回执）。

## 2. 核心模块与文件分工
- `broker.py` & `broker_process.py`（MQTT 消息代理服务）：
  - 启动并维护基于 loopback 本地回路的高性能 MQTT 3.1.1 代理服务器。
  - 具备独立进程守护、端口防冲突检测与异常退出告警能力。
- `mqtt_transport.py`（消息传输客户端与通道管理）：
  - 维护两个独立的客户端：小车侧发布客户端（`source`）与孪生侧订阅客户端（`observer`）。
  - 基于 QoS 1 服务质量实现遥测上报（`dt/car01/{session}/telemetry`）、指令下发（`.../command`）与执行回执（`.../ack`）。
  - 支持动态软切断上传链路（模拟网络丢包、掉线）与反馈链路。

## 3. 视频讲解英文口播（操作说明保持中文）
> Layer three connects the source and the receiver through a local MQTT three point one point one broker. Telemetry, commands and acknowledgements use separate topics under the same session prefix.
>
> QoS one provides at-least-once delivery semantics, so duplicate messages remain possible. The next layer must handle them. The field inspector shows selected values from the received message, including its sequence, simulation time, wheel speeds and sensor array.
>
> I will now interrupt telemetry upload. The source can continue moving, but the receiver no longer gets new observations. Its model must retain the last known state. After one point two seconds without a valid message, the data is marked stale.
>
> Restoring upload delivers new observations and exposes the missing interval as a gap. The command channel can be interrupted separately. A submitted request is not proof of execution: the source acknowledgement is what confirms that a command was applied.

