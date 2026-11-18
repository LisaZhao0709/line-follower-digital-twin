"""Independent SciPy/complex-arithmetic review of frozen ACTUAL Simulink traces.

This checks recorded experiments; it does not substitute Python runs for Simulink.
"""
from pathlib import Path
import hashlib
import json
import math
import platform
import sys
import shutil
from datetime import datetime, timezone, timedelta

import numpy as np
import pandas as pd
import scipy
from scipy import ndimage, signal
from scipy.io import loadmat
from scipy.spatial import cKDTree
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[1]


def sha256(file):
    return hashlib.sha256(file.read_bytes()).hexdigest()


def max_difference(a, b):
    return float(np.max(np.abs(np.asarray(a) - np.asarray(b))))


def independent_gate(frame, p, data):
    ref = data['referenceXY'][:-1]
    arc = data['referenceArc'].ravel()
    length = arc[-1]
    t = frame.time_s.to_numpy()
    x = frame.x_m.to_numpy()
    y = frame.y_m.to_numpy()
    distance, idx = cKDTree(ref).query(np.column_stack((x, y)))
    s = arc[idx]
    progress = np.r_[0, np.cumsum((np.diff(s) + length/2) % length - length/2)]
    angle = p['theta0']
    along = (x-p['x0'])*np.cos(angle)+(y-p['y0'])*np.sin(angle)
    normal = -(x-p['x0'])*np.sin(angle)+(y-p['y0'])*np.cos(angle)
    visited = set()
    coverage = []
    for a, d in zip(s, distance):
        if d <= p['sensor_front_m']+4*p['sensor_spacing_m']:
            visited.add(min(23, int(((a-s[0]) % length)/length*24)))
        coverage.append(len(visited))
    bad_jump = np.any(np.hypot(np.diff(x), np.diff(y)) > p['km']*np.diff(t)+1e-8)
    finish = float('nan')
    for i in np.flatnonzero((along[:-1] < 0) & (along[1:] >= 0)):
        if coverage[i+1] == 24 and progress[i+1] > .95*length and abs(normal[i+1]) <= .04 and not bad_jump:
            f = -along[i]/(along[i+1]-along[i])
            finish = float(t[i]+f*(t[i+1]-t[i]))
            break
    return finish


def verify_trace(frame, p, data):
    t = frame.time_s.to_numpy()
    x, y, th = (frame[n].to_numpy() for n in ('x_m','y_m','theta_rad'))
    image = data['trackReflectance']
    scale = p['meters_per_pixel_x']
    weights = np.arange(3.5, -4, -1)
    sx = x[:,None]+np.cos(th[:,None])*p['sensor_front_m']-np.sin(th[:,None])*weights*p['sensor_spacing_m']
    sy = y[:,None]+np.sin(th[:,None])*p['sensor_front_m']+np.cos(th[:,None])*weights*p['sensor_spacing_m']
    strengths = ndimage.map_coordinates(image, [image.shape[0]-1-sy/scale, sx/scale], order=1, mode='constant', cval=0)
    binary = strengths >= p['sensor_threshold']
    detected = np.any(binary, axis=1)
    raw = (strengths @ weights)/(3.5*np.maximum(strengths.sum(axis=1), 1e-12))
    held = np.zeros_like(raw)
    last = 0.
    loss_start = None
    stopped = False
    off = np.zeros_like(raw)
    for i, valid in enumerate(detected):
        if valid:
            held[i] = raw[i]
            loss_start = None
        else:
            held[i] = last
            if loss_start is None: loss_start = t[i]
        if loss_start is not None and t[i]-loss_start >= p['loss_timeout_s']-1e-12:
            stopped = True
        off[i] = stopped
        last = held[i]
    alpha = p['Ts']/(p['derivative_tau']+p['Ts'])
    derivative = signal.lfilter([alpha], [1,-(1-alpha)], np.diff(np.r_[0,held])/p['Ts'])
    pp = p['Kp']*held
    dd = p['Kd']*derivative
    ul = np.clip(p['base_speed']-pp-dd,0,1)*(1-off)
    ur = np.clip(p['base_speed']+pp+dd,0,1)*(1-off)
    v = p['km']*(frame.uL.to_numpy()+frame.uR.to_numpy())/2
    omega = p['km']*(frame.uR.to_numpy()-frame.uL.to_numpy())/p['wheel_base_m']
    # Complex exponential integrates the constant angular rate directly. This is
    # independent of the MATLAB model's midpoint+sinc native-block construction.
    angle_step = omega[:-1]*p['Ts']
    factor = np.ones_like(angle_step, dtype=complex)
    nz = np.abs(angle_step)>1e-10
    factor[nz] = np.expm1(1j*angle_step[nz])/(1j*angle_step[nz])
    if p['integration_method'] == 'euler': factor[:] = 1
    delta = p['Ts']*v[:-1]*np.exp(1j*th[:-1])*factor
    tests = {
        'sample_time': max_difference(np.diff(t),p['Ts']),
        'sensor_strength': max_difference(strengths,frame[[f'strength{k}' for k in range(1,9)]]),
        'sensor_X': max_difference(sx,frame[[f'sensorX{k}_m' for k in range(1,9)]]),
        'sensor_Y': max_difference(sy,frame[[f'sensorY{k}_m' for k in range(1,9)]]),
        'sensor_binary': max_difference(binary,frame[[f'S{k}' for k in range(1,9)]]),
        'detected': max_difference(detected,frame.line_detected),
        'held_error': max_difference(held,frame.sensor_error),
        'P_term': max_difference(pp,frame.P_term),
        'D_term': max_difference(dd,frame.D_term),
        'loss_timer': max_difference(off,frame.off_track),
        'left_command': max_difference(ul,frame.uL),
        'right_command': max_difference(ur,frame.uR),
        'X_update': max_difference(np.diff(x),delta.real),
        'Y_update': max_difference(np.diff(y),delta.imag),
        'theta_update': max_difference(np.diff(th),p['Ts']*omega[:-1]),
    }
    assert max(tests.values()) < 1e-9, (p['case_name'],tests)
    return tests, independent_gate(frame,p,data)


def map_checks(data,directory):
    mask = data['trackMask'].astype(bool)
    labels, count = ndimage.label(mask,np.ones((3,3)))
    holes = ndimage.binary_fill_holes(mask)&~mask
    _, hole_count = ndimage.label(holes)
    border_empty = not any((mask[0].any(),mask[-1].any(),mask[:,0].any(),mask[:,-1].any()))
    assert count == 1 and hole_count == 1 and border_empty
    assert not np.any(mask[np.array([0,-1])])
    scale = float(data['meters_per_pixel_x'].item())
    stroke = mask[60:90,110:210].sum(axis=0)
    assert np.all(stroke==5) and abs(scale-.004)<1e-12
    from PIL import Image
    source=np.asarray(Image.open(directory/'source_snapshot'/'data'/'track_source.png').convert('RGB'),dtype=float)
    luminance=source@np.array([.2989,.5870,.1140])
    source_labels,source_count=ndimage.label(luminance<128,np.ones((3,3)))
    edges=set(np.concatenate((source_labels[0],source_labels[-1],source_labels[:,0],source_labels[:,-1])))
    candidates=[i for i in range(1,source_count+1) if i not in edges]
    selected=max(candidates,key=lambda i:np.count_nonzero(source_labels==i))
    assert np.array_equal(mask,source_labels==selected),'Mask differs from the supplied source image'
    assert np.array_equal(mask,np.asarray(Image.open(directory/'source_snapshot'/'data'/'track_mask.png'))==0)
    assert abs(float(data['map_width_m'].item())-(mask.shape[1]-1)*scale)<1e-12
    assert abs(float(data['map_height_m'].item())-(mask.shape[0]-1)*scale)<1e-12
    return {
        'connected_components':count,'enclosed_regions':hole_count,'border_removed':border_empty,
        'map_height_px':mask.shape[0],'map_width_px':mask.shape[1],
        'mask_pixels':int(mask.sum()),'binary_horizontal_width_px':float(np.median(stroke)),
        'effective_grayscale_width_px':float(data['trackReflectance'][60:90,110:210].sum(axis=0).mean()),
        'meters_per_pixel_assumed':scale,
        'scale_if_width_4px':.02/4,'scale_if_width_6px':.02/6,
        'note':'4/6px values are an illustrative calibration sensitivity, not a measured confidence interval.',
    }


def make_plots(directory, frames, summary, data):
    figures = directory/'figures'
    figures.mkdir(exist_ok=True)
    plt.rcParams.update({'font.size':10,'axes.spines.top':False,'axes.spines.right':False})
    selected = ('Euler_PD_20ms','Exact_P_20ms','Exact_PD_20ms')
    colors = {'Euler_PD_20ms':'#8b939e','Exact_P_20ms':'#d28224','Exact_PD_20ms':'#16709c'}
    fig, ax = plt.subplots(2,2,figsize=(12,8),layout='constrained')
    scale=float(data['meters_per_pixel_x'].item());h,w=data['trackMask'].shape
    ax[0,0].imshow(~data['trackMask'].astype(bool),cmap='gray',vmin=0,vmax=1,
                   extent=[-scale/2,(w-.5)*scale,-scale/2,(h-.5)*scale],origin='upper')
    for name in selected:
        f=frames[name];m=summary[summary.case_name==name].iloc[0]
        f=f[f.time_s<=m.lap_time_s]
        ax[0,0].plot(f.x_m,f.y_m,color=colors[name],lw=1.0,label=name.replace('_',' '))
        ax[0,1].plot(f.time_s,f.sensor_error,color=colors[name],lw=.7,label=name.replace('_',' '))
    f=frames['Exact_PD_20ms'];m=summary[summary.case_name=='Exact_PD_20ms'].iloc[0]
    f=f[f.time_s<=m.lap_time_s]
    ax[1,0].plot(f.time_s,f.uL,label='left',lw=.8);ax[1,0].plot(f.time_s,f.uR,label='right',lw=.8)
    sensors=f[[f'S{k}' for k in range(1,9)]].to_numpy().T
    ax[1,1].imshow(sensors,aspect='auto',origin='upper',cmap='Blues',vmin=0,vmax=1,
                   extent=[f.time_s.iloc[0],f.time_s.iloc[-1],8.5,.5],interpolation='nearest')
    ax[0,0].set(title='Actual Simulink paths (map scale estimated)',xlabel='x (m)',ylabel='y (m)')
    ax[0,0].legend(fontsize=8);ax[0,0].set_aspect('equal')
    ax[0,1].set(title='Normalized sensor error',xlabel='simulation time (s)',ylabel='error (dimensionless)')
    ax[0,1].legend(fontsize=8);ax[0,1].grid(alpha=.2)
    ax[1,0].set(title='Exact ZOH, PD motor commands',xlabel='simulation time (s)',ylabel='command [0,1]',ylim=(-.03,1.03))
    ax[1,0].legend();ax[1,0].grid(alpha=.2)
    ax[1,1].set(title='Eight sensor outputs, exact PD',xlabel='simulation time (s)',ylabel='sensor: left to right',yticks=range(1,9))
    fig.savefig(figures/'reviewed_simulation.png',dpi=170);plt.close(fig)
    # Compare sampling choices at identical times using 5ms results as a numerical reference.
    fine=frames['Exact_PD_5ms'];comparison=[]
    fig, ax=plt.subplots(1,2,figsize=(12,4),layout='constrained')
    for name in ('Exact_PD_20ms','Exact_PD_10ms'):
        f=frames[name];keep=f.time_s<=87.5;times=f.time_s.to_numpy()[keep]
        dx=f.x_m.to_numpy()[keep]-np.interp(times,fine.time_s,fine.x_m)
        dy=f.y_m.to_numpy()[keep]-np.interp(times,fine.time_s,fine.y_m)
        dist=np.hypot(dx,dy)
        m=summary[summary.case_name==name].iloc[0]
        delta_time=float(m.lap_time_s-summary[summary.case_name=='Exact_PD_5ms'].lap_time_s.iloc[0])
        comparison.append({'case_name':name,'reference_case':'Exact_PD_5ms',
                           'comparison_end_s':87.5,'rms_position_difference_m':float(np.sqrt(np.mean(dist**2))),
                           'max_position_difference_m':float(dist.max()),'lap_time_difference_s':delta_time})
        ax[0].plot(times,dist*1000,label=name.replace('_',' '),lw=.8)
    ax[0].set(title='Sampling sensitivity (5ms sampled reference)',xlabel='time (s)',ylabel='position difference (mm)');ax[0].legend();ax[0].grid(alpha=.2)
    step_rows=summary[summary.case_name.isin(['Exact_PD_20ms','Exact_PD_10ms','Exact_PD_5ms'])].sort_values('Ts_s')
    ax[1].plot(step_rows.Ts_s*1000,step_rows.lap_time_s,'o-',color='#16709c')
    ax[1].set(title='Finish-gate lap time versus sample period',xlabel='sample period (ms)',ylabel='lap time (s)');ax[1].grid(alpha=.2)
    fig.savefig(figures/'sampling_sensitivity.png',dpi=170);plt.close(fig)
    pd.DataFrame(comparison).to_csv(directory/'sampling_sensitivity.csv',index=False)
    return comparison


def write_report(directory, summary, map_result, independent, sampling):
    analytical=pd.read_csv(directory/'analytic_open_loop.csv')
    exact_max=analytical[analytical.integration=='exact_zoh'].max_position_error_m.max()
    euler_max=analytical[analytical.integration=='euler'].max_position_error_m.max()
    default=summary[summary.case_name=='Exact_PD_20ms'].iloc[0]
    p=summary[summary.case_name=='Exact_P_20ms'].iloc[0]
    weak=summary[summary.case_name=='Exact_P_weak'].iloc[0]
    worst=max(x['max_absolute_difference'] for x in independent)
    lines=[
        '# 前四周模型复核、详细记录与数值精度报告','',
        f'记录目录：`{directory.name}`。执行平台：本机 MATLAB R2025b Update 7 / Simulink，普通仿真模式。',
        '12项开环解析解对比、12组实际闭环仿真、逐样本方程校验、复位一致性与独立Python复算已完成。所有规定的数值和逻辑检查通过。','',
        '## 结论与实际修正','',
        f'- 原教学模型能运行，但转弯采用欧拉积分，在2秒测试中最大位置误差约 **{euler_max*1000:.6f} mm**。',
        f'- 新增 `LF_Week2_OpenLoop_Exact.slx` 和 `LF_Week4_PD_Exact.slx`，采用每周期恒定轮速的解析位姿更新；同一解析测试最大位置差 **{exact_max:.3g} m**，接近浮点舍入。',
        '- 修正脱线计时：首次失线样本定义为起始时刻；50Hz下第11个连续失线样本才到0.20秒。旧10样本计时首尾只相隔0.18秒。原教学模型和新解析模型均已同步。',
        '- 跑圈要求访问24个路线分区后正向跨过起终点门线，并检查不可能的空间跳变；门线内插计时替代0.1秒抽样计时。参考曲线仅用于离线评价。',
        '- 无任何有效黑线检测时，MAE等指标记NaN（未定义），避免报告为零误差。完整原始日志保留全部时段，比较指标截止首圈或首次停止。','',
        '## 实验结果','',
        '|实验|模型|Ts / ms|Kp|Kd|完成一圈|圈时 / s|失线停止 / s|有效检测MAE|',
        '|---|---|---:|---:|---:|---|---:|---:|---:|',
    ]
    for _, r in summary.iterrows():
        lap=f'{r.lap_time_s:.6f}' if np.isfinite(r.lap_time_s) else '未完成'
        stop=f'{r.stop_time_s:.3f}' if np.isfinite(r.stop_time_s) else '无'
        mae=f'{r.mae_sensor_error:.6f}' if np.isfinite(r.mae_sensor_error) else '未定义'
        lines.append(f'|{r.case_name}|{r.integration}|{r.Ts_s*1000:g}|{r.Kp:g}|{r.Kd:g}|{"是" if r.completed_lap else "否"}|{lap}|{stop}|{mae}|')
    lines += ['',
        f'默认解析PD圈时约 **{default.lap_time_s:.2f} s**，P基线约 **{p.lap_time_s:.2f} s**，弱P在 **{weak.stop_time_s:.2f} s** 停止。',
        f'P命令总变化量 {p.command_total_variation:.6f}；PD为 {default.command_total_variation:.6f}。PD不保证全部指标改善，不能用理论预期替代实验数据。',
        '圈时表中的6位小数是门线线性内插的计算显示值，不意味着实车计时达到微秒精度；原始状态间隔为对应Ts。',
        '误差MAE为无量纲传感器加权误差，仅计算仍能检测到黑线的样本。早停弱P没经历完整赛道，其较小MAE不能证明性能更好。','',
        '## 数值正确性与独立复核','',
        '- 解析测试：停止、直行、左右转、朝上直行、原地旋转；两类运动模型各6项。每项保留理论轨迹和实际轨迹。',
        '- MATLAB逐样本独立 `interp2` 读取地图，核对八路强度/二值值、传感器坐标、检测、误差保持、P/D、停止逻辑、左右命令和位姿更新。',
        '- Python从冻结地图与原始CSV独立复算，使用SciPy插值和滤波；解析运动增量用复数指数积分，与Simulink的中点角度+sinc实现不同。',
        f'- Python共执行 {len(independent)} 个检查，最大全局绝对差 {worst:.3g}，统一通过阈值1e-9。各量单位不同，详细差值须按检查名称解读。',
        '- 10类关键输出重复运行差值均小于1e-12；复位没有继承上一轮误差、滤波器或停止状态。',
        '- 负例测试包括静止、起点附近摆动和不可能的跳跃；均不能被误判为一圈。',
        '- “一开始即无黑线”实际模型测试：0.20 s才停止，没有有效检测的MAE为未定义。','',
        '## 采样周期敏感性','',
        '|采样实验|对照|位置RMS差 / mm|最大位置差 / mm|圈时差 / ms|',
        '|---|---|---:|---:|---:|',
    ]
    for r in sampling:
        lines.append(f'|{r["case_name"]}|5ms采样|{r["rms_position_difference_m"]*1000:.6f}|{r["max_position_difference_m"]*1000:.6f}|{r["lap_time_difference_s"]*1000:.6f}|')
    lines += ['',
        '比较时段为0–87.5 s。5ms结果是更细采样的数值参考，不是真值。改变Ts同时改变传感器和控制器更新频率，因此这是完整闭环的采样敏感性检验，不应称为独立的积分器阶次证明。',
        '精确ZOH位姿更新消除了当前理想运动学中单周期恒定命令积分的截断误差；仍存在控制采样、像素地图、模型参数和物理理想化误差。','',
        '## 地图核对与精度边界','',
        f'- 黑色掩膜有 {map_result["connected_components"]} 个连通分量、{map_result["enclosed_regions"]} 个封闭内部区域；四边无外框像素；共 {map_result["mask_pixels"]} 个赛道像素。',
        '- 图像431×641 px，顶部水平黑线阈值宽度5 px；用户给定2cm，因此比例采用4mm/px，图幅约2.56×1.72m。尖角与急弯保留。',
        f'- 原图灰度过渡的等效线宽约 {map_result["effective_grayscale_width_px"]:.6f} px，与阈值线宽不同；图片自身不足以唯一决定真实物理比例。',
        '- 仅作比例敏感性说明：若有效标定宽度取4px或6px，则对应5mm/px或3.333mm/px。这不是实测置信区间，也不能把浮点误差当作整体场地误差。',
        '- 内侧边界是路线进度参考，不是真实赛道中心线；“到参考边界的距离”不应称为真实横向循迹误差。','',
        '## 参数来源与单位','',
        '|参数|当前值|单位|证据类型|',
        '|---|---:|---|---|',
        '|黑线宽度|0.02|m|用户提供|',
        '|地图宽/高|2.56 / 1.72|m|图像比例估算|',
        '|左右轮距|0.12|m|仿真假设|',
        '|传感器前置距离|0.05|m|仿真假设|',
        '|相邻传感器间距|0.008|m|仿真假设|',
        '|电机命令→轮线速度系数|0.35|m/s per unit command|理想比例模型假设|',
        '|基础命令|0.35|无量纲|教师配置；对应0.1225m/s|',
        '|Kp / Kd|0.45 / 0.03|无量纲 / s|本图上的示例参数|',
        '|Ki|0|1/s|第五周的积分项尚未实现|',
        '|微分滤波时间常数|0.08|s|教师配置|',
        '|脱线时限|0.20|s|从首次失线采样时刻起计时|','',
        '同侧两电机合并成等效轮侧；未建模侧滑、电机惯性、死区、摩擦、电池变化、噪声或真实硬件通信。当前结论是数值模型计算正确、实验可重复；实车准确性须由实测几何和命令–轮速数据进一步标定。','',
        '## 详细记录的查阅顺序','',
        '1. `simulation_summary.csv`：完整参数组合和评价结果。',
        '2. `*_parameters.json`：每次实验的参数、单位对应变量、时间和模型名称。',
        '3. `*_trace.csv`：每个采样点的位姿、控制量、8路二值/强度、传感器世界坐标和离线进度。',
        '4. `*_run.mat`：实际SimulationOutput与配置、指标、校验表；可在MATLAB重新加载。',
        '5. `*_equation_checks.csv` 与 `independent_equation_checks.csv`：逐公式最大差值、容差和通过状态。',
        '6. `analytic_open_loop.csv`、`safety_and_lap_checks.csv`、`repeatability.csv`、`sampling_sensitivity.csv`：分项证据。',
        '7. `source_snapshot/` 与 `file_manifest.csv`：本轮代码、实际模型、地图快照和SHA-256指纹。',
        '8. `environment.json`、`matlab_run.log`、`matlab_status.json`、`independent_status.json`：软件环境和执行记录。','',
        '修改参数后重新运行 `run_detailed_review` 会新建一个时间戳目录，不覆盖本轮记录。旧第一轮验收和初次复核属于历史版本，最终判断以本报告对应冻结快照为准。','',
        '## 官方定义与本报告的推导','',
        '欧拉积分的更新关系见 [MathWorks Discrete-Time Integrator](https://www.mathworks.com/help/simulink/slref/discretetimeintegrator.html)。',
        '差速车辆运动关系见 [MathWorks Mobile Robot Kinematics Equations](https://www.mathworks.com/help/robotics/ug/mobile-robot-kinematics-equations.html)。',
        '本文解析ZOH增量由该运动关系在单周期恒定v、omega假设下积分得到；它不是MathWorks对本项目实车精度的认证。','',
        '![实际模型轨迹与输出](figures/reviewed_simulation.png)','',
        '![采样周期敏感性](figures/sampling_sensitivity.png)','',
    ]
    (directory/'复核与准确仿真报告.md').write_text('\n'.join(lines),encoding='utf-8')


def main():
    stored=Path((ROOT/'results'/'review_latest.txt').read_text(encoding='utf-8').strip())
    directory=ROOT/'results'/stored.name
    assert directory.is_relative_to(ROOT/'results')
    status=json.loads((directory/'matlab_status.json').read_text(encoding='utf-8'))
    assert status['all_mandatory_checks_passed']
    data=loadmat(directory/'source_snapshot'/'data'/'track_data.mat')
    summary=pd.read_csv(directory/'simulation_summary.csv')
    map_result=map_checks(data,directory)
    (directory/'map_checks.json').write_text(json.dumps(map_result,indent=2),encoding='utf-8')
    frames={};checks=[]
    for _, row in summary.iterrows():
        name=row.case_name
        frame=pd.read_csv(directory/f'{name}_trace.csv')
        p=json.loads((directory/f'{name}_parameters.json').read_text(encoding='utf-8'))
        result,gate=verify_trace(frame,p,data)
        assert bool(row.completed_lap)==np.isfinite(gate),name
        if np.isfinite(gate):assert abs(row.lap_time_s-gate)<1e-9,(name,gate,row.lap_time_s)
        for check,value in result.items():
            checks.append({'case_name':name,'check':check,'max_absolute_difference':value,'tolerance':1e-9,'passed':True})
        frames[name]=frame
        print(f'INDEPENDENT_PASS {name} residual={max(result.values()):.3g}',flush=True)
    pd.DataFrame(checks).to_csv(directory/'independent_equation_checks.csv',index=False)
    sampling=make_plots(directory,frames,summary,data)
    write_report(directory,summary,map_result,checks,sampling)
    result={'all_checks_passed':True,'checks':len(checks),'actual_simulink_cases':len(summary),
            'python':sys.version,'numpy':np.__version__,'scipy':scipy.__version__,
            'platform':platform.platform(),'checked_at':datetime.now(timezone(timedelta(hours=8))).isoformat(),
            'method':'Independent recomputation of frozen actual Simulink traces; not a substitute simulation.'}
    (directory/'independent_status.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    tool_snapshot=directory/'source_snapshot'/'tools';tool_snapshot.mkdir(exist_ok=True)
    shutil.copy2(Path(__file__),tool_snapshot/'independent_review.py')
    catalogue=[]
    for file in sorted(directory.rglob('*')):
        if file.is_file() and file.name!='file_manifest.csv':
            catalogue.append({'relative_path':file.relative_to(directory).as_posix(),'bytes':file.stat().st_size,'sha256':sha256(file)})
    pd.DataFrame(catalogue).to_csv(directory/'file_manifest.csv',index=False)
    print(f'INDEPENDENT_REVIEW_PASSED checks={len(checks)} records={len(catalogue)} directory={directory}',flush=True)


if __name__=='__main__':main()
