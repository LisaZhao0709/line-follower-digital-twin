# 2026-11-08 模块拆分与验证

## 变更

- 从 `runtime.py` 提取仿真源运行状态、MQTT 通信、遥测接入、孪生模型、命令生命周期、数据存储六部分。
- 将 broker 进程管理从 `app.py` 提取到 `broker_process.py`。
- CSV 列定义和生成逻辑集中到 `storage.py`；HTTP 下载接口调用存储模块生成内容。
- 健康轮速参考系数由 `twin_model.py` 定义，诊断服务复用该公开常量。
- 保留仿真方程、现有网页界面和 API 字段、MQTT 三主题／QoS／非保留设置、保存时机和原启动入口。
- 现有集成测试中的断言保留，内部属性路径更新为所属组件。

模块输入、处理和输出见 [MODULES.md](MODULES.md)。

## 验证结果

| 检查 | 结果 | 证据与范围 |
| --- | --- | --- |
| 拆分前原有数值与诊断测试 | 7 项通过 | 仿真数值、随机复现、保护、故障区分和过期数据 |
| 拆分后原有数值与诊断测试 | 7 项通过 | 原有断言保留 |
| 新增模块测试 | 7 项通过 | 解析圆弧预测、心跳／复位、接入去重与缺口、非法数据、源文件／接收 CSV、命令去重／回执／超时和拒绝执行 |
| 仿真源码语法树对比 | 一致 | 除模块说明文字，`model.py` 的逻辑语法树与备份相同 |
| 接收行为对照 | 3,069 次对照一致 | 健康、左驱动偏差、强灰度扰动、遮挡四种场景；加入重复消息、缺口、心跳与换实验；对比拆分前后的状态、历史、预测、残差与计数，忽略运行时 UTC 字符串 |
| 真实 MQTT 端到端 | 本次未完成 | 拆分前后均在 broker 可达性检查超时；最小本机 TCP 自连接检查返回 Windows 10013（权限拒绝） |

`unittest discover` 共发现 15 项：14 项通过、1 项 MQTT 集成测试因上述环境限制报错。未将集成测试改为模拟消息，也未将其跳过或记录为通过。本次未完成浏览器运行复验。

## 重跑

在 `web_app` 目录执行全部测试：

```powershell
& '.venv\Scripts\python.exe' -B -m unittest discover -v
```

单独运行不需要网络的 14 项测试：

```powershell
& '.venv\Scripts\python.exe' -B -m unittest test_components test_system.PhysicsTests test_system.AnalysisTests -v
```

单独运行真实 MQTT 集成测试：

```powershell
& '.venv\Scripts\python.exe' -B -m unittest test_system.IntegrationTest -v
```

完整链路需要在允许本机 TCP 连接的运行环境中复验。原操作入口仍是 `启动网页.cmd`，新环境的依赖安装步骤见 README。
