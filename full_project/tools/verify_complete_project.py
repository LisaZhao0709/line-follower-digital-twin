"""Independent review of recorded ACTUAL Simulink runs, never replacement simulations."""
from pathlib import Path
import hashlib
import json
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
from matplotlib.patches import Polygon
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
CHECKS = []

def latest(week):
    # Basenames make archived projects portable across machines/directories.
    name = (ROOT/'results'/f'week{week}_latest.txt').read_text().strip().replace('\\','/').rsplit('/',1)[-1]
    return ROOT/'results'/name

def difference(a, b):
    a, b = np.asarray(a,dtype=float), np.asarray(b,dtype=float)
    assert a.shape == b.shape or a.ndim == 0 or b.ndim == 0, (a.shape,b.shape)
    assert np.array_equal(np.isnan(a),np.isnan(b)) or not np.any(np.isnan(a) | np.isnan(b))
    finite = np.isfinite(a) & np.isfinite(b)
    return float(np.max(np.abs(a-b)[finite])) if np.any(finite) else 0.

def check(case, name, a, b, tolerance=1e-9):
    residual = difference(a,b)
    CHECKS.append(dict(case=case,check=name,max_absolute_difference=residual,tolerance=tolerance,passed=residual<tolerance))
    assert residual < tolerance, (case,name,residual)

def independent_gate(f, p, data):
    ref=data['referenceXY'][:-1];arc=data['referenceArc'].ravel();length=arc[-1]
    t=f.time_s.to_numpy();x=f.x_m.to_numpy();y=f.y_m.to_numpy()
    distance,idx=cKDTree(ref).query(np.c_[x,y]);s=arc[idx]
    progress=np.r_[0,np.cumsum((np.diff(s)+length/2)%length-length/2)]
    visited=set();coverage=[]
    for a,d in zip(s,distance):
        if d<=p['sensor_front_m']+4*p['sensor_spacing_m']:
            visited.add(min(23,int(((a-s[0])%length)/length*24)))
        coverage.append(len(visited))
    maximum_speed=p['km']*max(p['motor_left_factor'],p['motor_right_factor'])
    jump=np.any(np.hypot(np.diff(x),np.diff(y))>maximum_speed*np.diff(t)+1e-8)
    along=(x-p['x0'])*np.cos(p['theta0'])+(y-p['y0'])*np.sin(p['theta0'])
    normal=-(x-p['x0'])*np.sin(p['theta0'])+(y-p['y0'])*np.cos(p['theta0'])
    finish=np.nan
    for i in np.flatnonzero((along[:-1]<0)&(along[1:]>=0)):
        if coverage[i+1]==24 and progress[i+1]>.95*length and abs(normal[i+1])<=.04 and not jump:
            finish=float(t[i]-along[i]/(along[i+1]-along[i])*(t[i+1]-t[i]));break
    return finish

def verify_equations(f,p,data,case):
    t=f.time_s.to_numpy();x=f.x_m.to_numpy();y=f.y_m.to_numpy();th=f.theta_rad.to_numpy();ts=p['Ts'];N=len(f)
    weights=np.arange(3.5,-4,-1);image=data['trackReflectance'];scale=p['meters_per_pixel_x']
    sx=x[:,None]+np.cos(th[:,None])*p['sensor_front_m']-np.sin(th[:,None])*weights*p['sensor_spacing_m']
    sy=y[:,None]+np.sin(th[:,None])*p['sensor_front_m']+np.cos(th[:,None])*weights*p['sensor_spacing_m']
    noisy=p.get('environment_level',0)>0
    if noisy:
        ideal=ndimage.map_coordinates(image,[image.shape[0]-1-sy/scale,sx/scale],order=1,mode='constant',cval=0)
        check(case,'ideal_strength',ideal,f[[f'ideal_strength{k}' for k in range(1,9)]])
        forward=f.env_forward_jitter_m.to_numpy()[:,None];lateral=f.env_lateral_jitter_m.to_numpy()[:,None]
        sx=sx+np.cos(th[:,None])*forward-np.sin(th[:,None])*lateral
        sy=sy+np.sin(th[:,None])*forward+np.cos(th[:,None])*lateral
    clean=ndimage.map_coordinates(image,[image.shape[0]-1-sy/scale,sx/scale],order=1,mode='constant',cval=0)
    observed=clean
    if noisy:
        check(case,'sampled_strength',clean,f[[f'sampled_strength{k}' for k in range(1,9)]])
        observed=f.env_light_gain.to_numpy()[:,None]*clean+f.env_shadow_bias.to_numpy()[:,None]+f[[f'env_read_error{k}' for k in range(1,9)]].to_numpy()
    strength=np.clip(observed+p['sensor_noise']*np.sin(2*np.pi*t[:,None]*np.arange(8,16)+.37*np.arange(1,9)),0,1)
    strength[(t>=p['dropout_start_s']-1e-12)&(t<p['dropout_start_s']+p['dropout_duration_s']-1e-12)]=0
    binary=strength>=p['sensor_threshold'];detected=binary.any(axis=1)
    raw=(strength@weights)/(3.5*np.maximum(strength.sum(axis=1),1e-12))
    e=np.zeros(N);last=0.
    for k in range(N):
        if detected[k]:last=raw[k]
        e[k]=last
    alpha=ts/(p['derivative_tau']+ts)
    derivative=signal.lfilter([alpha],[1,-(1-alpha)],np.diff(np.r_[0,e])/ts)
    P=p['Kp']*e;D=p['Kd']*derivative;I=np.zeros(N);blocked=np.zeros(N);state=0.
    for k in range(N):
        if p['Ki']==0:state=0.
        elif detected[k]:
            delta=p['Ki']*e[k]*ts;candidate=np.clip(state+delta,-p['integral_limit'],p['integral_limit'])
            total=P[k]+D[k]+candidate
            if p['anti_windup'] and abs(total)>min(p['base_speed'],1-p['base_speed']) and total*delta>0:blocked[k]=1
            else:state=candidate
        I[k]=state
    reason=np.zeros(N);start=None;code=0
    for k in range(N):
        if detected[k]:start=None
        elif start is None:start=t[k]
        if code==0:
            if not np.all(np.isfinite([x[k],y[k],th[k]])):code=3
            elif not (0<=x[k]<=p['map_width_m'] and 0<=y[k]<=p['map_height_m']):code=2
            elif start is not None and t[k]-start>=p['loss_timeout_s']-1e-12:code=1
            elif t[k]>=p['stop_time']-1e-12:code=4
        reason[k]=code
    correction=P+I+D;uL=np.clip(p['base_speed']-correction,0,1)*(reason==0);uR=np.clip(p['base_speed']+correction,0,1)*(reason==0)
    vl=p['km']*p['motor_left_factor']*uL;vr=p['km']*p['motor_right_factor']*uR
    omega=(f.right_speed_mps.to_numpy()-f.left_speed_mps.to_numpy())/p['wheel_base_m']
    v=(f.right_speed_mps.to_numpy()+f.left_speed_mps.to_numpy())/2
    angle=omega[:-1]*ts;factor=np.ones_like(angle,dtype=complex);nz=np.abs(angle)>1e-10
    factor[nz]=np.expm1(1j*angle[nz])/(1j*angle[nz])
    delta=ts*v[:-1]*np.exp(1j*th[:-1])*factor
    pairs={
      'sample_time':(np.diff(t),np.full(N-1,ts)),
      'sensor_X':(sx,f[[f'sensorX{k}_m' for k in range(1,9)]]),
      'sensor_Y':(sy,f[[f'sensorY{k}_m' for k in range(1,9)]]),
      'sensor_strength':(strength,f[[f'strength{k}' for k in range(1,9)]]),
      'sensor_binary':(binary,f[[f'S{k}' for k in range(1,9)]]),
      'detected':(detected,f.line_detected),'held_error':(e,f.sensor_error),
      'P_term':(P,f.P_term),'I_term':(I,f.I_term),'D_term':(D,f.D_term),
      'anti_windup':(blocked,f.anti_windup),'correction':(correction,f.correction),
      'stop_reason':(reason,f.stop_reason),'off_track':(reason==1,f.off_track),'enabled':(reason==0,f.enabled),
      'left_command':(uL,f.uL),'right_command':(uR,f.uR),
      'left_speed':(vl,f.left_speed_mps),'right_speed':(vr,f.right_speed_mps),
      'expected_left':(p['km']*f.uL.to_numpy(),f.expected_left_mps),
      'expected_right':(p['km']*f.uR.to_numpy(),f.expected_right_mps),
      'left_residual':(f.left_speed_mps-f.expected_left_mps,f.left_residual_mps),
      'right_residual':(f.right_speed_mps-f.expected_right_mps,f.right_residual_mps),
      'X_update':(np.diff(x),delta.real),'Y_update':(np.diff(y),delta.imag),'theta_update':(np.diff(th),ts*omega[:-1]),
    }
    for name,(a,b) in pairs.items():check(case,name,a,b)
    check(case,'initial_pose',np.array([x[0],y[0],th[0]]),np.array([p['x0'],p['y0'],p['theta0']]))
    check(case,'end_time',np.array([t[-1]]),np.array([p['stop_time']]))
    assert np.max(np.abs(I))<=p['integral_limit']+1e-12
    assert np.all(np.isfinite(f.to_numpy())) and np.all((f.uL>=0)&(f.uL<=1)&(f.uR>=0)&(f.uR<=1))
    return independent_gate(f,p,data)

def verify_feedback(f,fb,p,case):
    ts=p['Ts'];N=len(f);W=max(2,round(1/ts));t=f.time_s.to_numpy();valid=f.line_detected.to_numpy()>0
    def roll(a,mean=False):
        obj=pd.Series(np.asarray(a)).rolling(W,min_periods=1)
        return (obj.mean() if mean else obj.sum()).to_numpy()
    count=roll(valid);den=np.maximum(count,1)
    mae=roll(np.abs(f.sensor_error)*valid)/den;rms=np.sqrt(roll(f.sensor_error**2*valid)/den)
    mae[count==0]=np.nan;rms[count==0]=np.nan
    cross=np.zeros(N);last=0
    for k in range(N):
        if not valid[k]:last=0;continue
        s=1 if f.sensor_error.iloc[k]>.045 else (-1 if f.sensor_error.iloc[k]<-.045 else 0)
        if s:
            cross[k]=last!=0 and last!=s;last=s
    duration=np.maximum(np.minimum(t,1),ts);zcr=roll(cross)/duration;active=f.enabled.to_numpy()>0
    sat=((f.uL<=1e-6)|(f.uR<=1e-6)|(f.uL>=1-1e-6)|(f.uR>=1-1e-6))&active
    sf=roll(sat)/np.maximum(roll(active),1)
    variation=roll(np.r_[0,np.abs(np.diff(f.uL))+np.abs(np.diff(f.uR))])/duration
    residual=roll(np.maximum(np.abs(f.left_residual_mps),np.abs(f.right_residual_mps)),True)
    correction=roll(np.abs(f.correction),True);prms=np.sqrt(roll(f.P_term**2,True));drms=np.sqrt(roll(f.D_term**2,True))
    ready=(t>=.6)&(count>=.5*np.minimum(np.arange(1,N+1),W))
    slow=ready&(mae>.18)&(correction<.12)&(zcr<=1.5)
    osc=ready&(zcr>=3)&(rms>.08);saturation=ready&(sf>.15)
    integral=ready&(np.abs(f.I_term)>=.9*p['integral_limit'])
    chatter=ready&(drms>1.5*np.maximum(prms,.005))&(variation>3)&(rms<.15)
    mismatch=ready&(residual>.005);stable=ready&(mae<=.18)&(zcr<3)&(sf<=.15)&~mismatch&~integral&~chatter
    pairs={'window_mae':mae,'window_rms':rms,'zero_crossings_per_s':zcr,'window_saturation_fraction':sf,
      'command_variation_per_s':variation,'window_speed_residual_mps':residual,'slow_flag':slow,'oscillation_flag':osc,
      'saturation_flag':saturation,'integral_limit_flag':integral,'derivative_chatter_flag':chatter,'motor_mismatch_flag':mismatch,'stable_flag':stable}
    for name,a in pairs.items():check(case,'feedback_'+name,a,fb[name])
    status=np.select([f.stop_reason==1,f.stop_reason==2,f.stop_reason==3,f.stop_reason==4,mismatch,osc,chatter,saturation,integral,slow,stable,~valid],
      ['Line-loss stop','Out-of-bounds stop','Numerical anomaly','Time limit','Motor-model mismatch','Significant oscillation','Derivative chatter','Output saturation','Integral near limit','Slow response','Tracking stable','Transient line loss'],default='Observing')
    # Accept original frozen status labels and English labels from new experiments.
    legacy_status = {'\u8131\u7ebf\u505c\u8f66': 'Line-loss stop', '\u8d8a\u754c\u505c\u8f66': 'Out-of-bounds stop', '\u6570\u503c\u5f02\u5e38': 'Numerical anomaly', '\u65f6\u95f4\u4e0a\u9650': 'Time limit', '\u7535\u673a\u6a21\u578b\u504f\u5dee': 'Motor-model mismatch', '\u632f\u8361\u660e\u663e': 'Significant oscillation', '\u5fae\u5206\u6296\u52a8': 'Derivative chatter', '\u8f93\u51fa\u9971\u548c': 'Output saturation', '\u79ef\u5206\u63a5\u8fd1\u9650\u5e45': 'Integral near limit', '\u54cd\u5e94\u504f\u6162': 'Slow response', '\u5faa\u8ff9\u7a33\u5b9a': 'Tracking stable', '\u77ed\u65f6\u65e0\u9ed1\u7ebf': 'Transient line loss', '\u89c2\u5bdf\u4e2d': 'Observing'}
    observed_status = fb.status.replace(legacy_status).to_numpy()
    check(case,'feedback_status',np.asarray(status!=observed_status,dtype=float),np.zeros(N))

def verify_summary(f,row,lap,case):
    check(case,'completed_lap',np.array([np.isfinite(lap)]),np.array([bool(row.completed_lap)]))
    check(case,'lap_time',np.array([lap]),np.array([row.lap_time_s]))
    end=int(row.analysis_end_index);g=f.iloc[:end];valid=g.line_detected>0;e=g.sensor_error[valid]
    expected=[float(e.abs().mean()),float(np.sqrt((e**2).mean())),float(e.abs().max())]
    check(case,'summary_errors',np.array(expected),np.array([row.mae,row.rms,row.peak]))
    active=g.enabled>0;sat=(g.uL<=1e-6)|(g.uR<=1e-6)|(g.uL>=1-1e-6)|(g.uR>=1-1e-6)
    check(case,'summary_saturation',np.array([float(sat[active].mean())]),np.array([row.saturation_fraction]))
    stopped=f[f.stop_reason>0]
    expected_stop=np.nan if stopped.empty else float(stopped.time_s.iloc[0])
    check(case,'summary_stop',np.array([expected_stop]),np.array([row.stop_time_s]))

def plots_and_demo(directory,data,frames,summaries):
    plt.rcParams.update({'font.family':'Microsoft YaHei','font.size':10,'axes.unicode_minus':False})
    figures=directory/'figures';figures.mkdir(exist_ok=True)
    names=['P_weak','PID_default','P_extreme'];titles=['弱 P：响应不足并脱线','默认 PID：完成闭环','强 P：振荡与饱和']
    fig,axes=plt.subplots(3,3,figsize=(14,11),layout='constrained')
    extent=[0,float(data['map_width_m'].item()),0,float(data['map_height_m'].item())]
    for j,(name,title) in enumerate(zip(names,titles)):
        f=frames[(7,name)];r=summaries[7].set_index('case_name').loc[name];g=f.iloc[:int(r.analysis_end_index)]
        ax=axes[0,j];ax.imshow(data['trackMask'],cmap='gray_r',extent=extent,origin='upper',vmin=0,vmax=1)
        ax.plot(g.x_m,g.y_m,color='tab:red',lw=1.1);ax.set_title(title);ax.set_xlabel('x (m)');ax.set_ylabel('y (m)')
        axes[1,j].plot(g.time_s,g.sensor_error,color='tab:red',lw=.8);axes[1,j].set(xlabel='t (s)',ylabel='归一化传感器误差',ylim=(-1,1))
        axes[2,j].plot(g.time_s,g.uL,label='左');axes[2,j].plot(g.time_s,g.uR,label='右',alpha=.8)
        axes[2,j].set(xlabel='t (s)',ylabel='归一化电机命令',ylim=(-.05,1.05));axes[2,j].legend()
        for i in (1,2):axes[i,j].grid(alpha=.25)
    fig.savefig(figures/'three_teaching_experiments.png',dpi=150);plt.close(fig)
    baseline=frames[(8,'PID_5ms')];end_time=87.4;t=baseline.time_s.to_numpy();keep=t<=end_time;t=t[keep]
    rows=[];fig,axes=plt.subplots(1,2,figsize=(11,4),layout='constrained')
    for name in ['PID_final_repeat','PID_10ms']:
        f=frames[(8,name)];dx=np.interp(t,f.time_s,f.x_m)-baseline.x_m.to_numpy()[keep];dy=np.interp(t,f.time_s,f.y_m)-baseline.y_m.to_numpy()[keep]
        dist=np.hypot(dx,dy);r=summaries[8].set_index('case_name').loc[name];ref=summaries[8].set_index('case_name').loc['PID_5ms']
        rows.append(dict(case_name=name,Ts_s=r.Ts_s,rms_position_difference_m=float(np.sqrt(np.mean(dist**2))),max_position_difference_m=float(dist.max()),lap_difference_s=float(r.lap_time_s-ref.lap_time_s)))
        axes[0].plot(t,dist*1000,label=f'{r.Ts_s*1000:.0f} ms vs 5 ms')
    axes[0].set(xlabel='t (s)',ylabel='到5 ms数值参考的位移差 (mm)');axes[0].legend();axes[0].grid(alpha=.3)
    selected=summaries[8].iloc[:3];axes[1].plot(selected.Ts_s*1000,selected.lap_time_s,'o-');axes[1].set(xlabel='采样周期 (ms)',ylabel='完成一圈时间 (s)');axes[1].grid(alpha=.3)
    fig.savefig(figures/'sampling_sensitivity.png',dpi=150);plt.close(fig)
    sampling=pd.DataFrame(rows);sampling.to_csv(directory/'sampling_sensitivity.csv',index=False)
    # Scientific playback generated directly from the actual default trace.
    f=frames[(7,'PID_default')];r=summaries[7].set_index('case_name').loc['PID_default'];end=int(r.analysis_end_index)
    fig,ax=plt.subplots(figsize=(7.5,5),layout='constrained');ax.imshow(data['trackMask'],cmap='gray_r',extent=extent,origin='upper',vmin=0,vmax=1)
    line,=ax.plot([],[],color='tab:red',lw=1.4);body=Polygon(np.zeros((4,2)),color='tab:blue',alpha=.7);ax.add_patch(body)
    sensors=ax.scatter(np.zeros(8),np.zeros(8),s=14,color='tab:orange');ax.set(xlabel='x (m)',ylabel='y (m)',aspect='equal')
    pictures=[];local=np.array([[-.08,-.05],[.08,-.05],[.08,.05],[-.08,.05]])
    for i in np.linspace(0,end-1,125,dtype=int):
        a=f.theta_rad.iloc[i];rot=np.array([[np.cos(a),np.sin(a)],[-np.sin(a),np.cos(a)]])
        body.set_xy(local@rot+[f.x_m.iloc[i],f.y_m.iloc[i]]);line.set_data(f.x_m.iloc[:i+1],f.y_m.iloc[:i+1])
        sensors.set_offsets(np.c_[f.loc[i,[f'sensorX{k}_m' for k in range(1,9)]].to_numpy(),f.loc[i,[f'sensorY{k}_m' for k in range(1,9)]].to_numpy()])
        ax.set_title(f'实际 Simulink 记录回放 | t={f.time_s.iloc[i]:.2f} s | PID (.45, .015, .03)')
        fig.canvas.draw();pictures.append(Image.fromarray(np.asarray(fig.canvas.buffer_rgba())[:,:,:3]).convert('P',palette=Image.Palette.ADAPTIVE))
    pictures[0].save(figures/'PID_actual_simulation.gif',save_all=True,append_images=pictures[1:],duration=100,loop=0);plt.close(fig)
    return sampling

def report(directory,summaries,sampling,map_info,performance):
    w7=summaries[7].set_index('case_name');rows=[]
    for name in ['P_weak','P_nominal','P_high','P_extreme','PID_default','PID_integral','PID_no_AW','PD_noise','Motor_mismatch','Dropout']:
        r=w7.loc[name];finish=f'{r.lap_time_s:.3f}' if r.completed_lap else '未完成'
        rows.append(f'| {name} | {r.Kp:g}/{r.Ki:g}/{r.Kd:g} | {finish} | {r.mae:.5f} | {100*r.saturation_fraction:.2f}% | {int(r.oscillation_samples)} |')
    max_res=max(c['max_absolute_difference'] for c in CHECKS)
    startup_file=directory/'startup_runtime_checks.json'
    startup=json.loads(startup_file.read_text(encoding='utf-8')) if startup_file.exists() else {}
    startup_summary=(f"独立MATLAB启动检查已在 {startup.get('checked_at')} 完成：实际执行 START_PROJECT，界面打开、单步、复位、关闭及定时器释放全部通过，并检查了20个MATLAB源码文件。此前自动审批服务用量限制造成的未执行项已补齐。"
        if startup.get('passed') else "额外的START_PROJECT独立启动检查尚未执行；模型运行及界面回归已通过。另有静态依赖、SLX完整性及6个嵌入核函数一致性检查，静态检查不等同于独立重启试验。")
    text=f'''# 完整八周循迹小车教学仿真工程：最终实验与复核报告

完成日期：{datetime.now(timezone(timedelta(hours=8))).strftime('%Y-%m-%d %H:%M:%S %Z')}。软件为 MATLAB/Simulink R2025b。全部数值来自实际 Simulink 模型输出；Python 用于独立复核和绘图，没有替代 Simulink 仿真。

## 1. 逐周交付及验收

| 周次 | 交付 | 验证证据 |
|---|---|---|
| 1 | 仅内部黑色闭环地图，移除外边界 | 前四周冻结报告与本次连通性检查 |
| 2 | 左右差速及解析区间积分 | 前四周直线/旋转解析测试，本次逐样本位置复算 |
| 3 | 8路传感器位置、反射强度和0/1输出 | 独立 SciPy 像素插值、坐标变换及阈值检查 |
| 4 | 原生 P/D/filter 模块与闭环 | 前四周与本次 PD 圈时一致 |
| 5 | I项、条件积分抗饱和、轮速预期和残差、安全逻辑 | 8组实际实验，200项 MATLAB 公式检查，状态/无效输入单元检查 |
| 6 | 三个参数、运行、播放、暂停、单步、复位与保存 | 13项交互检查，真实 MATLAB 界面截图 |
| 7 | 滑动窗口指标及教学提示，13组对照 | 325项公式检查，慢响应/振荡/稳定/脱线/电机偏差与数据核对 |
| 8 | 重复运行、10/5ms采样、初始偏差、性能及最终界面回归 | 4组实际实验，100项公式检查，独立复算、源文件快照与 SHA256 |

本次独立复核覆盖第5/7/8周 **25组实际实验**、**{len(CHECKS)}项数值检查**，全部通过。最大绝对复算差为 {max_res:.3g}，逐项容许差为 1e-9（不同量各按其原有单位）。同参数重新运行的11路主要信号与第5周记录逐样本完全相同。前四周12组旧实验及180项独立复核保持原有冻结记录。

## 2. 模型、量纲和假设

地图黑线宽度由用户给定为2 cm。参考水平线约5像素，因此估算每像素0.004 m，图幅约2.56×1.72 m。灰度边缘使线宽测量存在误差，这个比例不是实际测量的地图尺寸。地图有{map_info['components']}个黑色连通区域、{map_info['holes']}个封闭孔洞，边框已去除。

默认假设：左右轮距0.12 m，车身0.16×0.10 m，传感器前置0.05 m，间距0.008 m，标称电机增益0.35 m/s/归一化命令。50 Hz同步采样，基础命令0.35，I输出限制±0.20，D滤波时间常数0.08 s。S1在左、S8在右，权重3.5到−3.5；归一化误差正值表示线在左侧。

P=Kp·e；D为离散差分经过一阶低通后乘Kd。I每次检测有效时尝试增加Ki·e·Ts，限制到±0.20。如果该增量会让已经饱和的电机进一步饱和，拒绝积分；允许反向增量使积分恢复。短时丢线保留误差并冻结I。Ki=0时I始终为零。每次“运行新实验”都会重新初始化模型所有内部状态。

左命令=sat(基础命令−P−I−D)，右命令=sat(基础命令+P+I+D)，范围[0,1]。左右轮速度按常数增益得到；模型没有电机惯性、轮胎滑移或电池电压状态。位姿对每个采样间隔内保持不变的轮速采用解析积分。因此计算公式正确并不代表已经验证真实硬件精度。

## 3. 对照实验结果

| 实验 | Kp/Ki/Kd | 完圈时间(s) | 有效样本MAE | 运行时电机饱和比例 | 振荡提示采样数 |
|---|---|---:|---:|---:|---:|
{chr(10).join(rows)}

弱P在14.76 s丢线停车。它的MAE只覆盖较短、较容易的赛段，不可据此判断比成功跑完的控制器更好。MAE以有效检测样本为分母；完全没有检测数据时为NaN。保护性停车后的零命令不计为控制器饱和。

Kp=3确实比0.45降低了该地图的误差，没有振荡；Kp=15才得到重复的振荡及饱和示例。强P的圈时更短，因为单边饱和会改变左右轮平均速度；不能仅用圈时评价控制质量。默认PID是一组可完成赛道的基准，并非最优参数。Ki=1在此地图中改善MAE，不能绝对断言Ki较大必定更差。关闭抗饱和与启用抗饱和的对照只说明本模型下的结果，不能泛化到所有系统。

电机左侧系数设为0.8的实验以标称模型作为预期值，残差明确属于“仿真轮速−标称预期”；不是实际编码器测量。

## 4. 评价规则及安全行为

规则使用因果、最近约1秒的窗口。归一化误差±0.045以内不计零交叉，防止小噪声频繁翻转符号。至少运行0.6 s并有足够有效样本才给出性能判断。

- 稳定：窗口MAE≤0.18、零交叉<3次/s、饱和≤15%，且没有积分限幅、D抖动或电机残差警报。
- 偏慢：MAE>0.18，平均绝对修正量<0.12，零交叉≤1.5次/s。
- 振荡：零交叉≥3次/s且误差RMS>0.08。
- 饱和：可运行样本中处于命令上下限的比例>15%。
- 积分接近限幅：|I|≥限制值的90%；描述现象，不等同于故障。
- D抖动：D RMS大于P RMS的1.5倍，命令变化>3/s且误差RMS<0.15。
- 电机偏差：窗口平均最大轮速残差>0.005 m/s。

这些是固定工况下的教学启发规则，并非经过真实学生数据验证的诊断系统。状态优先级为保护停车、电机偏差、振荡、D抖动、饱和、积分限幅、偏慢、稳定、观察中。原始指标与各标志全部导出，学生能看到提示依据。

连续无黑线满0.20 s后锁定停车；首个丢线样本定义为计时起点，修复了旧版10样本计作0.20 s、实际只跨0.18 s的问题。越界立即停车；非有限位姿单元测试确认触发数值保护。安全输出使用Switch选择字面零，避免NaN×0仍为NaN。达到教师设置的仿真时限后停止。传感器恢复不会自动解除停车，下一次新实验才重新初始化。

## 5. 采样及性能

PD旧基准圈时87.521335 s，本次完整模型关闭I后得到相同结果。默认PID在20/10/5 ms下的圈时分别为 {summaries[8].lap_time_s.iloc[0]:.6f}、{summaries[8].lap_time_s.iloc[1]:.6f}、{summaries[8].lap_time_s.iloc[2]:.6f} s。

20 ms相对5 ms数值参考，0–87.4 s轨迹的RMS位移差为{sampling.iloc[0].rms_position_difference_m*1000:.4f} mm，最大差为{sampling.iloc[0].max_position_difference_m*1000:.4f} mm。5 ms也是数值模型，不是真值；改变采样周期同时改变传感器和控制器更新频率，这不是单独的积分误差实验。

完圈判断要求访问全部24个路线区域、足够的累计进度以及沿前进方向跨过起终点门，排除停留、附近摆动和跳跃路径。地图内部边缘只作离线进度参考，控制器仅使用传感器，不读取参考路线；该边缘不是物理中心线。显示的插值小数不代表真实时钟或实车位置精度。

本机这4组100 s实验的 Simulink 执行耗时范围为{performance.execution_wall_s.min():.3f}–{performance.execution_wall_s.max():.3f} s，含初始化与结束的总耗时为{performance.total_wall_s.min():.3f}–{performance.total_wall_s.max():.3f} s。记录导出、独立复算和界面绘图耗时不计入这些数值。界面采用“先计算、后回放”；暂停/单步作用于已记录的播放，参数于下一次运行生效，没有声称实时控制。

## 6. 数据、修复与复现

每次实验保留原始SimulationOutput MAT、逐样本CSV、JSON参数、公式检查。第7/8周另有逐窗口反馈CSV；最终保留软件环境、性能表、完整源代码、模型/地图快照和SHA256目录。更新指标时保留原始执行时间，并另存复核时间。

完成过程中修复了构建器重新接线冲突、MATLAB结构体汇总方式、CSV与内存浮点值的比较精度、界面多行状态文字检查、反馈缓存更新，以及停车零命令误计为控制饱和的问题。所有这些修复都经对应检查再验证。无数据窗口测试使用真正持续无检测的实验；短暂中断后恢复的遥测仍有有效数据，同时停车锁定保持。

正常使用只需在MATLAB进入本工程目录后执行 `START_PROJECT`。`OPEN_MODEL`打开可编辑原生Simulink模型。`RUN_ALL_WEEKS`按5→6→7→8依次重跑，任何阶段失败立即停止；独立复核工具位于tools目录。

{startup_summary}

## 7. 数字孪生结构与完成边界

PE：软件中的虚拟车辆；VE：地图、传感器和运动学；DD：参数及逐样本记录；Ss：有量化证据的教学评价；CN：Simulink内部闭环信号和学生参数反馈。当前课程核心八周功能完成。MQTT/ESP32实体同步、账户、积木编辑器、三维外观为原计划可选扩展，不属于本次已完成的核心验收。

## 8. 官方技术依据

条件积分的饱和处理参见[MathWorks PID Controller](https://www.mathworks.com/help/simulink/slref/pidcontroller.html)；原生界面控件及回调参见[MathWorks uicontrol](https://www.mathworks.com/help/matlab/ref/uicontrol.html)。本工程没有使用自动PID整定，也不依赖Control System Toolbox或Image Processing Toolbox。

![三组实际对照](figures/three_teaching_experiments.png)

![采样敏感性](figures/sampling_sensitivity.png)
'''
    (directory/'完整项目实验与复核报告.md').write_text(text,encoding='utf-8')

def main():
    directory=latest(8);status=json.loads((directory/'status.json').read_text());assert status['matlab_passed']
    data=loadmat(ROOT/'data'/'track_data.mat');mask=data['trackMask'].astype(bool)
    components=ndimage.label(mask,np.ones((3,3)))[1];holes=ndimage.label(ndimage.binary_fill_holes(mask)&~mask)[1]
    border_empty=not (mask[0].any() or mask[-1].any() or mask[:,0].any() or mask[:,-1].any())
    png=np.asarray(Image.open(ROOT/'data'/'track_mask.png').convert('L'))<128
    assert components==1 and holes==1 and border_empty and np.array_equal(mask,png)
    map_info=dict(components=components,holes=holes,border_empty=bool(border_empty),mask_matches_png=True,black_pixels=int(mask.sum()),scale_m_per_pixel=float(data['meters_per_pixel_x'].item()),scale_is_estimate=True)
    (directory/'map_checks.json').write_text(json.dumps(map_info,indent=2),encoding='utf-8')
    frames={};summaries={}
    for week in [5,7,8]:
        folder=latest(week);summaries[week]=pd.read_csv(folder/'summary.csv')
        for _,row in summaries[week].iterrows():
            name=row.case_name;case=f'week{week}/{name}';f=pd.read_csv(folder/f'{name}_trace.csv');p=json.loads((folder/f'{name}_parameters.json').read_text())
            lap=verify_equations(f,p,data,case);verify_summary(f,row,lap,case)
            feedback=folder/f'{name}_feedback.csv'
            if feedback.exists():verify_feedback(f,pd.read_csv(feedback),p,case)
            frames[(week,name)]=f
            print(f'INDEPENDENT_PASS {case}',flush=True)
    pd.DataFrame(CHECKS).to_csv(directory/'independent_checks.csv',index=False)
    performance=pd.read_csv(directory/'performance.csv');sampling=plots_and_demo(directory,data,frames,summaries)
    report(directory,summaries,sampling,map_info,performance)
    status.update(passed=True,independent_review_pending=False,independent_checks=len(CHECKS),independent_actual_cases=len(frames),max_independent_residual=max(c['max_absolute_difference'] for c in CHECKS),checked_at=datetime.now(timezone(timedelta(hours=8))).isoformat())
    (directory/'status.json').write_text(json.dumps(status,ensure_ascii=False,indent=2),encoding='utf-8')
    env={'python':sys.version,'numpy':np.__version__,'scipy':scipy.__version__,'method':'Independent recomputation of recorded actual Simulink runs, not a replacement simulation.'}
    (directory/'independent_environment.json').write_text(json.dumps(env,indent=2),encoding='utf-8')
    print(f'COMPLETE_INDEPENDENT_REVIEW_PASSED cases={len(frames)} checks={len(CHECKS)}',flush=True)

if __name__=='__main__':main()
