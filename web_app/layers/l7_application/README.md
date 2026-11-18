# L7 应用展示层 (Application Presentation Layer)

## 1. 核心定位与职责
L7 应用展示层是数字孪生系统的**人机交互窗口与沉浸式可视化大屏**。它把深层的物理位姿、传感器电平、通信质量、孪生预测偏差及智能诊断建议，转化为工程师和中小学生能够一目了然看懂的动态图表与交互控件。

- **核心任务**：可视化、交互、实验展示。
- **核心输入**：Runtime 导出的全系统状态快照（`snapshot`，包含实车位姿、孪生先验、误差曲线、诊断卡片）。
- **主要输出**：Web 用户操作界面、Canvas 实时轨迹与车体渲染、动态时域曲线图、诊断建议卡片与数据导出。

## 2. 核心模块与文件分工
- `web_api.py`（Web 后端控制器）：
  - 基于 Flask 框架提供轻量级 RESTful API（如 `/api/state` 状态轮询、`/api/command` 决策交互、`/api/export` CSV 报表导出等）。
- `static/`（前端沉浸式交互资源）：
  - `index.html`：布局完整的七层监控大屏，包含赛道地图视窗、传感器指示灯阵列、时域曲线区、诊断分析卡片区以及参数设置表单。
  - `app.js`：
    - **Canvas 赛道与小车实时渲染**：基于小车位姿 $(x,y,\theta)$ 实时绘制旋转车身框、车头指示箭头以及 8 路红外光电采样点（检测到黑线亮橙色，背景呈浅灰）。
    - **历史轨迹与跳变渲染**：高亮显示小车实际行驶轨迹与丢包断点。
    - **时域图表动态绘制**：实时滚屏绘制循迹偏差曲线及 PID 三项输出曲线。
  - `style.css`：现代深色/高对比工业质感界面样式。

## 3. 视频讲解英文口播（操作说明保持中文）
> Layer seven brings the system together in an interactive dashboard. The experiment lab shows the track, sensor observations, controller terms and diagnostic findings. The Data and twin view makes the source clock, message counts, model updates and communication channels visible. Completed runs appear in Experiment records, and received data can be exported for later analysis.
>
> The Runtime module coordinates these layers. It assembles the components, schedules source sampling, passes accepted observations into the model, manages commands and provides consistent snapshots to the interface.
>
> The complete workflow is observation, communication, validation, model comparison, diagnosis and acknowledged feedback. Each step has an observable input and output. The current result is a tested simulation-based prototype with a live MQTT link. Connecting a physical vehicle would be the next stage, requiring real acquisition hardware, measured parameters and validation against physical observations.

