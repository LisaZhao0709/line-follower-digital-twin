"""Explain observations using a fixed healthy reference, without fault labels."""
import math

NOMINAL_GAIN = .35
WINDOW_S = 1.
MIN_SAMPLES = 20


def finding(code, title, evidence, rule, advice, scope, severity='warning'):
    return dict(code=code, title=title, evidence=evidence, rule=rule,
                advice=advice, scope=scope, severity=severity)


def analyze(history, frame, age_s):
    metrics = dict(mae=0., rms=0., zero_crossings=0., saturation=0., residual=0.,
                   status='Waiting for data', message='Analysis starts after a valid observation arrives.', recommendation=None,
                   findings=[], sample_count=0, window_s=WINDOW_S, drive={},
                   sensor_rmse=0., sensor_bit_difference=0.)
    if not frame:
        metrics['findings'] = [finding('waiting', 'Waiting for the first valid observation', [],
            'Valid MQTT telemetry from car01 is required.', 'Start an experiment and check telemetry upload.',
            'No observations yet; vehicle health cannot be assessed.', 'info')]
        return metrics
    if age_s is None or age_s > 1.2:
        metrics.update(status='Data stale', message='The current vehicle state is unknown. Restore telemetry first.')
        metrics['findings'] = [finding('telemetry_stale', 'Telemetry interrupted; current diagnosis suspended',
            [f'Last valid source time {frame["t_sim_s"]:.2f} s',
             f'Receiver data age {age_s:.2f} s' if age_s is not None else 'No valid arrival timestamp is available'],
            'No valid new message has arrived for more than 1.2 seconds of receiver wall time.',
            'Restore upload and confirm that sequence numbers and source time advance before changing parameters.',
            'Stale data alone cannot establish whether the vehicle has stopped or a motor has failed.')]
        return metrics
    window = [f for f in history if f['t_sim_s'] >= frame['t_sim_s']-WINDOW_S]
    if not window:
        window = [frame]
    metrics['sample_count'] = len(window)
    valid = [f for f in window if any(f['sensors'])]
    errors = [f['sensor_error'] for f in valid]
    metrics['mae'] = sum(abs(e) for e in errors)/max(1, len(errors))
    metrics['rms'] = math.sqrt(sum(e*e for e in errors)/max(1, len(errors)))
    crossings = 0
    previous_sign = 0
    for f in window:
        if f.get('gap_before') or not any(f['sensors']):
            previous_sign = 0
        if not any(f['sensors']):
            continue
        error = f['sensor_error']
        sign = 1 if error > .045 else (-1 if error < -.045 else 0)
        if sign:
            crossings += int(previous_sign != 0 and sign != previous_sign)
            previous_sign = sign
    span = max(.02, window[-1]['t_sim_s']-window[0]['t_sim_s'])
    metrics['zero_crossings'] = crossings/span
    active = [f for f in window if f['stop_reason'] == 0]
    metrics['saturation'] = sum(min(f['uL'], f['uR']) <= 1e-6 or max(f['uL'], f['uR']) >= 1-1e-6 for f in active)/max(1, len(active))
    # Runtime supplies L5 results; raw observations remain supported for offline analysis.
    metrics['residual'] = sum(f.get('residual_mps', max(
        abs(f['left_speed_mps']-NOMINAL_GAIN*f['uL']),
        abs(f['right_speed_mps']-NOMINAL_GAIN*f['uR']))) for f in window)/len(window)
    differences = [a-b for f in window for a,b in zip(f['strengths'], f['ideal_strengths'])]
    metrics['sensor_rmse'] = math.sqrt(sum(d*d for d in differences)/len(differences))
    metrics['sensor_bit_difference'] = sum(a != int(b >= .5) for f in window
        for a,b in zip(f['sensors'], f['ideal_strengths']))/(8*len(window))
    complete = not any(f.get('gap_before', False) for f in window[1:])
    ready = len(window) >= MIN_SAMPLES and span >= .38 and complete and frame['t_sim_s'] >= .6
    findings = metrics['findings']
    for side, command, measured, label in (
            ('left', 'uL', 'left_speed_mps', 'Left'),
            ('right', 'uR', 'right_speed_mps', 'Right')):
        powered = [f for f in active if f[command] >= .1]
        expected = [f.get(f'expected_{side}_mps', NOMINAL_GAIN*f[command]) for f in powered]
        observed = [f[measured] for f in powered]
        denominator = sum(v*v for v in expected)
        ratio = sum(a*b for a,b in zip(expected, observed))/denominator if denominator else None
        residual = sum(b-a for a,b in zip(expected, observed))/max(1, len(powered))
        metrics['drive'][side] = dict(samples=len(powered), response_ratio=ratio,
            signed_residual_mps=residual,
            expected_mean_mps=sum(expected)/max(1, len(expected)),
            observed_mean_mps=sum(observed)/max(1, len(observed)))
        direction = 'low' if ratio is not None and ratio < .85 and residual < -.005 else (
                    'high' if ratio is not None and ratio > 1.15 and residual > .005 else None)
        if ready and len(powered) >= 15 and direction:
            values = metrics['drive'][side]
            findings.append(finding(f'drive_{side}_{direction}',
                label+(' drive response low' if direction == 'low' else ' drive response high'),
                [f'Powered samples: {len(powered)}; response ratio: {ratio*100:.1f}%',
                 f'Nominal {values["expected_mean_mps"]:.4f} / observed {values["observed_mean_mps"]:.4f} m/s',
                 f'Signed wheel-speed residual {residual:+.4f} m/s'],
                'At least 15 samples with command >= 0.1 in the last second; response outside 85%-115% and absolute mean residual > 0.005 m/s.',
                'Check the affected drive, power supply, wheel-speed measurement and motor coefficient, then repeat with the same command.',
                'The command-to-speed relationship differs from the healthy model; identifying a mechanical or electrical cause requires more evidence.'))
    sensor_issue = ready and (metrics['sensor_rmse'] > .10 or metrics['sensor_bit_difference'] > .05)
    if sensor_issue:
        findings.append(finding('sensor_reference_difference', 'Sensor readings differ from the simulation reference',
            [f'Eight-channel sensor RMSE {metrics["sensor_rmse"]:.3f}',
             f'Binary disagreement with the reference {metrics["sensor_bit_difference"]*100:.1f}%'],
            'At least 20 valid time samples; sensor RMSE > 0.10 or binary disagreement > 5%.',
            'Check lighting, occlusion, sensor height and map calibration; compare against the ideal environment with a fixed seed.',
            'Ideal sensor values are simulation references; this difference alone cannot distinguish shadows, vibration or sensor damage.'))
    reason = frame['stop_reason']
    if reason:
        title = {1:'Line-loss stop', 2:'Out-of-bounds stop', 4:'Time limit reached'}[reason]
        metrics.update(status=title, message='The source reported a safety stop or time limit. Confirmed evidence is listed below.')
        evidence = [f'Source stop_reason={reason}', f'Current line detection: {sum(frame["sensors"])} / 8 channels']
        if reason == 1:
            missing = []
            for f in reversed(window):
                if any(f['sensors']):
                    break
                missing.append(f)
                if f.get('gap_before'):
                    break
            if missing:
                evidence.append(f'Continuous received observations without a detected line: {frame["t_sim_s"]-missing[-1]["t_sim_s"]:.2f} s')
        findings.insert(0, finding('stop_'+str(reason), title+'; inspect before resetting', evidence,
            {1:'The source latches a stop after 0.20 simulation seconds without a detected line.',2:'The source stops when the reference point leaves the map.',4:'The source has reached the 100-second simulation limit.'}[reason],
            'Review sensor-reference differences and drive residuals before choosing sensor checks or a PID comparison.',
            'A safety stop alone does not establish motor or sensor damage.'))
    drive_issue = any(f['code'].startswith('drive_') for f in findings)
    oscillation = ready and metrics['zero_crossings'] >= 3 and metrics['rms'] > .08
    saturation = ready and metrics['saturation'] > .15
    slow = ready and metrics['mae'] > .18
    if oscillation or saturation or slow:
        title = 'Significant control oscillation' if oscillation else ('Frequent motor-command saturation' if saturation else 'High tracking error')
        findings.append(finding('control_oscillation' if oscillation else ('control_saturation' if saturation else 'control_error'), title,
            [f'MAE for valid detections: {metrics["mae"]:.3f}, RMS {metrics["rms"]:.3f}',
             f'Error zero crossings: {metrics["zero_crossings"]:.1f} /s; command saturation {metrics["saturation"]*100:.1f}%'],
            'Oscillation: >= 3 zero crossings/s and RMS > 0.08; saturation > 15%; high error: MAE > 0.18.',
            'First exclude sensor and drive deviations, then compare the default PID using error, saturation and lap time.',
            'This evaluates control performance; parameters, sensing and drive issues may cause similar symptoms.'))
    if not reason:
        if frame['completed_lap']:
            metrics.update(status='Lap completed', message=f'Lap time: {frame["lap_time_s"]:.2f} s. Review the evidence for this window below.')
        elif drive_issue:
            metrics.update(status='Motor-model mismatch', message='The response ratio and signed residual indicate a drive deviation on one side. See the evidence below.')
        elif sensor_issue:
            metrics.update(status='Sensor-reference mismatch', message='Check sensing conditions before evaluating PID parameters.')
        elif oscillation:
            metrics.update(status='Significant oscillation', message='The error changes sign frequently and RMS is elevated.')
        elif saturation:
            metrics.update(status='Output saturation', message='Commands frequently reach their upper or lower bounds.')
        elif slow:
            metrics.update(status='High tracking error', message='Use the evidence below to distinguish sensing, drive and control issues.')
        elif frame['source_state'] in ('idle', 'paused'):
            metrics.update(status='Ready' if frame['source_state']=='idle' else 'Paused', message='Choose parameters for a new run or resume the current experiment.')
        elif ready:
            metrics.update(status='Tracking stable', message='The current window does not meet the significant-anomaly criteria.')
        else:
            metrics.update(status='Observing', message='Collecting enough consecutive observations.')
    if not findings:
        findings.append(finding('normal' if ready else 'insufficient_window',
            'No significant anomaly in the current window' if ready else 'Insufficient diagnostic window',
            [f'Window: {len(window)} samples over {span:.2f} s',
             f'MAE {metrics["mae"]:.3f}; sensor RMSE {metrics["sensor_rmse"]:.3f}'],
            'Uses the last second of observations, with at least 20 samples and no known gaps inside the window.',
            'Observe another condition or compare parameters with a fixed seed.',
            'The result covers only the received window and current model; unobserved faults cannot be excluded.', 'info'))
    gains = frame['config']
    kp_cur, ki_cur, kd_cur = gains['Kp'], gains['Ki'], gains['Kd']
    different = (kp_cur, ki_cur, kd_cur) != (.45, .015, .03)

    # Generate candidate parameters from the current observations and gains.
    # These rule-based candidates require comparison in a new experiment.
    if ready and not drive_issue and not sensor_issue and (
            reason == 1 or oscillation or saturation or slow or different):
        
        # For frequent zero crossings, reduce Kp and increase derivative damping Kd.
        if oscillation:
            rec_kp = round(max(0.25, kp_cur * 0.70), 3)
            rec_kd = round(min(0.08, (kd_cur * 1.30 if kd_cur > 0 else 0.04)), 3)
            rec_ki = round(max(0.005, ki_cur * 0.80), 3)
            label = f'Candidate oscillation-damping settings (Kp={rec_kp}, Kd={rec_kd})'
            reason_text = f'The observed zero-crossing rate is high at {metrics["zero_crossings"]:.1f} Hz. Reduce the current Kp={kp_cur} and increase derivative damping.'
        # For frequent actuator saturation:
        elif saturation:
            rec_kp = round(max(0.30, kp_cur * 0.85), 3)
            rec_ki = round(max(0.005, ki_cur * 0.75), 3)
            rec_kd = round(kd_cur, 3)
            label = f'Candidate saturation-reduction settings (Kp={rec_kp})'
            reason_text = f'Observed actuator saturation is {metrics["saturation"]*100:.1f}%. Reduce proportional and integral gains for comparison.'
        # For weak tracking response or a line-loss stop:
        # Use the nominal Kp=0.45 comparison when very weak gains are associated with line loss.
        # Otherwise adjust the current gains using the observed performance.
        elif slow or reason == 1:
            if different and kp_cur <= 0.15:
                rec_kp, rec_ki, rec_kd = .45, .015, .03
                label = 'Run the recommended default PID comparison'
                reason_text = 'Weak current gains are associated with line loss. Repeat from the same initial state using reference PID (.45, .015, .03).'
            else:
                rec_kp = round(min(0.75, max(0.40, kp_cur * 1.35)), 3)
                rec_ki = round(min(0.025, max(0.010, ki_cur + 0.005)), 3)
                rec_kd = round(max(0.025, kd_cur), 3)
                label = f'Candidate tracking-response settings (Kp={rec_kp}, Ki={rec_ki})'
                reason_text = f'Observed MAE={metrics["mae"]:.3f} is high or the line was lost. Increase proportional and integral gains relative to the current settings for comparison.'
        else:
            rec_kp, rec_ki, rec_kd = .45, .015, .03
            label = 'Run the recommended default PID comparison'
            reason_text = 'No persistent drive or sensor-reference mismatch was found. Repeat from the same initial state with the reference PID.'

        metrics['recommendation'] = dict(
            label=label,
            reason=reason_text,
            config=dict(gains, Kp=rec_kp, Ki=rec_ki, Kd=rec_kd)
        )
    return metrics
