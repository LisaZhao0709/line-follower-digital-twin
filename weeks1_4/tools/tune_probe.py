"""Exploratory numerical rehearsal; final acceptance runs the actual Simulink model."""
from pathlib import Path
import json
import numpy as np
from scipy.io import loadmat
from scipy.ndimage import map_coordinates
from scipy.spatial import cKDTree

ROOT = Path(__file__).resolve().parents[1]
M = loadmat(ROOT / 'data/track_data.mat')
IMAGE = M['trackReflectance']
SCALE = float(M['meters_per_pixel_x'].item())
REF = M['referenceXY']
TREE = cKDTree(REF[:-1])
ARC = M['referenceArc'].ravel()
WEIGHTS = np.arange(3.5, -4, -1)


def simulate(kp=.25, kd=.025, base=.22, front=.05, spacing=.008, duration=190):
    ts, km, wheelbase, tau = .02, .35, .12, .08
    alpha = ts / (tau + ts)
    x, y, th = (float(M[k].item()) for k in ('x0', 'y0', 'theta0'))
    last, filt, missing, progress, laps = 0., 0., 0, 0., 0
    trajectory = []
    prev_s = 0.
    lost_at = None
    for step in range(round(duration/ts) + 1):
        sx = x + np.cos(th)*front - np.sin(th)*WEIGHTS*spacing
        sy = y + np.sin(th)*front + np.cos(th)*WEIGHTS*spacing
        strength = map_coordinates(IMAGE, [IMAGE.shape[0]-1-sy/SCALE, sx/SCALE], order=1, mode='constant', cval=0)
        detected = np.any(strength >= .5)
        e = np.dot(strength, WEIGHTS)/max(strength.sum(), 1e-9)/3.5 if detected else last
        filt += alpha * ((e-last)/ts-filt)
        missing = 0 if detected else missing+1
        correction = kp*e+kd*filt
        enabled = missing < 10 and lost_at is None
        ul = np.clip(base-correction, 0, 1) if enabled else 0
        ur = np.clip(base+correction, 0, 1) if enabled else 0
        if not enabled and lost_at is None:
            lost_at = step*ts
        if step % 5 == 0:
            distance, idx = TREE.query([x,y])
            s = ARC[idx]
            ds = s - prev_s
            if ds < -.5*ARC[-1]: ds += ARC[-1]
            if ds > .5*ARC[-1]: ds -= ARC[-1]
            progress += ds
            prev_s = s
            trajectory.append([step*ts,x,y,th,e,ul,ur,distance,progress])
            if progress > .985*ARC[-1] and np.hypot(x-float(M['x0'].item()), y-float(M['y0'].item())) < .10:
                laps = 1
                break
        v = km*(ul+ur)/2
        x += ts*v*np.cos(th)
        y += ts*v*np.sin(th)
        th += ts*km*(ur-ul)/wheelbase
        last = e
        if lost_at is not None: break
    trajectory = np.array(trajectory)
    return {'kp':kp,'kd':kd,'base':base,'front':front,'spacing':spacing,'lap':laps,'time':step*ts,'progress':float(progress/ARC[-1]),'lost_at':lost_at,'mae':float(np.mean(np.abs(trajectory[:,4]))),'max_distance_inner_edge':float(np.max(trajectory[:,7]))}, trajectory


if __name__ == '__main__':
    runs = []
    for base, kp, kd in [(.22,.25,.025),(.22,.35,.025),(.22,.45,.03),(.18,.3,.03),(.18,.45,.035),(.16,.4,.035),(.22,.35,0),(.18,.4,0),(.22,.05,0),(.22,.7,0)]:
        r, traj = simulate(kp,kd,base)
        print(json.dumps(r), flush=True)
        runs.append(r)
        if r['lap']:
            np.savetxt(ROOT/'data'/f'probe_{base}_{kp}_{kd}.csv',traj,delimiter=',')
    (ROOT/'data'/'probe_summary.json').write_text(json.dumps(runs,indent=2))
