# L1 物理层 (Physical Layer)

## 1. 核心定位与职责
L1 物理层负责小车及其运行环境的**物理实体建模与执行控制**。它反映了现实中受力、运动和电路控制的物理世界，是整个数字孪生系统的真实物理根基（PE 物理实体）。

- **核心任务**：物理建模、状态计算、执行控制。
- **核心输入**：上层控制策略/配置参数、赛道物理地图。
- **主要输出**：小车的真实物理状态（位姿 $x, y, \theta$，左右轮转速 $v_L, v_R$，电机执行占空比 $u_L, u_R$，停机标志 `stop_reason`）。

## 2. 核心模块与文件分工
- `physical_car.py`（物理底盘）：
  - 建模小车轴距（$L=0.12\text{ m}$）及电机转速特性（$k_m=0.35$）。
  - 实现基于解析圆弧解（Exact ZOH / Arc Factor）的差速运动学数值积分，精准推演位姿。
- `track.py`（物理赛道环境）：
  - 维护赛道几何长宽（$2.4\text{ m}\times 1.2\text{ m}$）、地表反射率底图及黑线二值掩膜。
- `controller.py`（板载执行控制）：
  - 运行板载离散带抗饱和滤波的 PID 算法，将偏差换算为左右轮实际执行指令。
  - 实现 0.20 秒脱线安全切断与出界紧急制动。

## 3. 视频讲解英文口播（操作说明保持中文）
> Layer one represents the physical side of this simulation. It defines the track, the differential-drive chassis and the onboard control and safety logic.
>
> The nominal motor gain is zero point three five metres per second per unit command, and the wheel separation is twelve centimetres. Left and right wheel speeds determine the forward velocity and turning rate.
>
> The pose update uses the exact circular arc for wheel speeds held constant during one sampling interval. This avoids the Euler integration error for that interval. It does not mean that the model includes every physical effect. Motor inertia, tyre slip and battery dynamics would require additional models and measurements.
>
> On the right, we can see position, heading and wheel speed change as the simulated car moves along the track.

