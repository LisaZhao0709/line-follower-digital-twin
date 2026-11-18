"""Numerical regression and real MQTT end-to-end checks. No mocked transport."""
import copy
import csv
import json
from pathlib import Path
import tempfile
import time
import unittest

import numpy as np

from app import create_app
from broker_process import BrokerProcess
from model import Config, Simulator, Track
from runtime import Runtime
from analysis import analyze


def until(predicate, timeout=7):
    deadline = time.monotonic()+timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(.03)
    raise AssertionError('Timed out waiting for the experiment condition.')


class PhysicsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.track = Track()

    def test_ideal_matches_matlab_frozen_trace(self):
        path = Path(__file__).resolve().parents[1]/'full_project/results/week5_20261005_005312/PID_default_trace.csv'
        pairs = [('x_m','x_m'),('y_m','y_m'),('theta_rad','theta_rad'),('sensor_error','sensor_error'),('P','P_term'),('I','I_term'),('D','D_term'),('uL','uL'),('uR','uR')]
        source = Simulator(self.track, Config(environment_level=0))
        worst = 0.
        with path.open(encoding='utf-8-sig') as file:
            for row in csv.DictReader(file):
                frame, done = source.step()
                worst = max(worst, *(abs(frame[a]-float(row[b])) for a,b in pairs))
                if done:
                    break
        self.assertTrue(frame['completed_lap'])
        self.assertLess(abs(frame['lap_time_s']-87.5034772424523), 1e-10)
        self.assertLess(worst, 1e-10)

    def test_random_observations_reproducible_and_affect_motion(self):
        sources = [Simulator(self.track, Config(environment_seed=seed)) for seed in (7,7,8)]
        frames = [[source.step()[0] for _ in range(300)] for source in sources]
        self.assertEqual(frames[0], frames[1])
        self.assertNotEqual(frames[0][-1]['strengths'], frames[2][-1]['strengths'])
        self.assertNotEqual(frames[0][-1]['x_m'], frames[2][-1]['x_m'])
        self.assertTrue(all(0 <= s <= 1 for run in frames for f in run for s in f['strengths']))

    def test_dropout_stop_and_parameter_validation(self):
        source = Simulator(self.track, Config(environment_level=0, dropout=True))
        frame, done = source.step()
        while not done:
            frame, done = source.step()
        self.assertAlmostEqual(frame['t_sim_s'], 1.2)
        self.assertEqual((frame['stop_reason'],frame['uL'],frame['uR']), (1,0,0))
        self.assertEqual(source.step()[0]['uL'], 0)
        for values in ({'Kp':float('nan')},{'Ki':-1},{'environment_seed':.5},{'environment_level':3},{'dropout':'yes'}):
            with self.assertRaises(ValueError):
                Config.parse(values)


class IntegrationTest(unittest.TestCase):
    def test_real_mqtt_observation_model_analysis_and_decision(self):
        with tempfile.TemporaryDirectory() as results:
            broker = BrokerProcess(18885)
            runtime = None
            try:
                runtime = Runtime(18885, results)
                client = create_app(runtime).test_client()
                until(lambda: runtime.receiver.latest is not None)
                with client.get('/') as page:
                    self.assertEqual(page.status_code, 200)
                self.assertEqual(client.post('/api/command',json={'action':'run','config':{'Kp':-1}}).status_code,400)
                response = client.post('/api/command',json={'action':'run','config':{'environment_level':0,'speed':8}})
                self.assertEqual(response.status_code,200)
                until(lambda: runtime.commands.current['status']=='applied' and runtime.asset.frame['t_sim_s']>1)
                self.assertEqual(runtime.receiver.latest['run_id'],runtime.asset.run_id)
                self.assertEqual(runtime.twin_model.state['x_m'],runtime.receiver.latest['x_m'])
                self.assertGreater(runtime.twin_model.state['updates'],1)
                runtime.command('pause')
                until(lambda: runtime.asset.state=='paused' and runtime.commands.current['status']=='applied')
                index = runtime.asset.frame['sample_index']
                runtime.command('step')
                until(lambda: runtime.asset.frame['sample_index']>index and runtime.commands.current['status']=='applied')
                runtime.command('resume')
                until(lambda: runtime.asset.state=='running' and runtime.commands.current['status']=='applied')
                runtime.transport('upload',False)
                # Let any already-published messages arrive before freezing the reference.
                time.sleep(.25)
                frozen_time = runtime.receiver.latest['t_sim_s']
                frozen_updates = runtime.twin_model.state['updates']
                until(lambda: runtime.snapshot()['quality']=='stale')
                self.assertGreater(runtime.asset.frame['t_sim_s'],frozen_time)
                self.assertEqual(runtime.receiver.latest['t_sim_s'],frozen_time)
                self.assertEqual(runtime.twin_model.state['updates'],frozen_updates)
                self.assertEqual(client.post('/api/command',json={'action':'recommend'}).status_code,400)
                runtime.transport('upload',True)
                until(lambda: runtime.snapshot()['quality']=='good' and runtime.receiver.latest['t_sim_s']>frozen_time)
                self.assertGreater(runtime.receiver.gaps,0)
                self.assertTrue(any(f['gap_before'] for f in runtime.receiver.history))
                runtime.transport('feedback',False)
                old_run = runtime.asset.run_id
                runtime.command('reset')
                until(lambda: runtime.snapshot()['command']['status']=='timeout')
                self.assertEqual(runtime.asset.run_id,old_run)
                self.assertEqual(runtime.snapshot()['quality'],'good')
                runtime.transport('feedback',True)
                runtime.command('run',{'environment_level':0,'Kp':.05,'Ki':0,'Kd':0,'speed':8})
                # Snapshot takes the Runtime lock, so completion includes persisted run files.
                until(lambda: runtime.snapshot()['source_state']=='completed'
                      and runtime.commands.current['status']=='applied')
                self.assertAlmostEqual(runtime.asset.frame['t_sim_s'],14.76)
                self.assertTrue((Path(results)/runtime.asset.run_id/'source.csv').is_file())
                until(lambda: runtime.snapshot()['metrics']['recommendation'] is not None)
                failed_run = runtime.asset.run_id
                self.assertEqual(client.post('/api/command',json={'action':'recommend'}).status_code,200)
                until(lambda: runtime.commands.current['status']=='applied' and runtime.asset.run_id!=failed_run)
                self.assertEqual(runtime.asset.sim.config.Kp,.45)
                runtime.command('run',{'environment_level':0,'motor_left_factor':.8,'speed':8})
                until(lambda: runtime.commands.current['status']=='applied' and runtime.asset.frame['t_sim_s']>1)
                until(lambda: runtime.snapshot()['metrics']['residual']>.005)
                self.assertEqual(runtime.snapshot()['metrics']['status'],'Motor-model mismatch')
                runtime.command('pause')
                until(lambda: runtime.commands.current['status']=='applied')
                duplicate = copy.deepcopy(runtime.receiver.latest)
                before = runtime.receiver.duplicates
                runtime.mqtt.source.publish(runtime.mqtt.prefix+'/telemetry',json.dumps(duplicate),qos=1)
                until(lambda: runtime.receiver.duplicates>before)
                invalid = copy.deepcopy(runtime.receiver.latest);invalid['seq']+=100;invalid['strengths']=[0]*7
                before = runtime.receiver.rejected
                runtime.mqtt.source.publish(runtime.mqtt.prefix+'/telemetry',json.dumps(invalid),qos=1)
                until(lambda: runtime.receiver.rejected>before)
                self.assertEqual(client.get('/api/export').status_code,200)
                self.assertIn(b'expected_left_mps',client.get('/api/export').data)
                report = client.get('/api/analysis').get_json()
                self.assertEqual(report['quality'],'good')
                self.assertTrue(any(f['code']=='drive_left_low' for f in report['analysis']['findings']))
                self.assertLess(report['twin']['residual_left_mps'], 0.)
                self.assertEqual(len(report['twin']['forecast']), 11)
                state = client.get('/api/state').get_json()
                self.assertIn('residual_left_mps', state['history'][-1])
                self.assertIn('nominal_drift_m', state['history'][-1])
                columns = client.get('/api/export').data.decode('utf-8-sig').splitlines()[0].split(',')
                self.assertIn('innovation_m', columns)
                self.assertIn('prediction_valid', columns)
                self.assertIn('residual_right_mps', columns)
                with client.get('/showcase') as page:
                    self.assertEqual(page.status_code, 200)
                print('MQTT_CHAIN_VERIFIED source -> broker -> twin update -> analysis -> command -> source')
            finally:
                if runtime:
                    runtime.close()
                broker.close()


class AnalysisTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.track = Track()

    def observe(self, values, seconds=3):
        source = Simulator(self.track, Config.parse(values))
        frames = []
        for _ in range(round(seconds/.02)+1):
            frame, done = source.step()
            frame['source_state'] = 'completed' if done else 'running'
            frame['gap_before'] = False
            frames.append(frame)
            if done:
                break
        return frames

    def test_healthy_and_single_spike_do_not_raise_drive_fault(self):
        frames = self.observe({'environment_level':0})
        metrics = analyze(frames,frames[-1],.01)
        self.assertEqual(metrics['status'],'Tracking stable')
        frames[-1]['left_speed_mps'] += .4
        metrics = analyze(frames,frames[-1],.01)
        self.assertGreater(metrics['residual'],.005)
        self.assertFalse(any(f['code'].startswith('drive_') for f in metrics['findings']))

    def test_left_and_right_response_localization_without_fault_labels(self):
        frames = self.observe({'environment_level':0,'motor_left_factor':.8})
        for frame in frames:
            frame['config']['motor_left_factor'] = 1.
        metrics = analyze(frames,frames[-1],.01)
        codes = [f['code'] for f in metrics['findings']]
        self.assertIn('drive_left_low',codes)
        self.assertNotIn('drive_right_low',codes)
        self.assertAlmostEqual(metrics['drive']['left']['response_ratio'],.8)
        self.assertAlmostEqual(metrics['drive']['right']['response_ratio'],1.)
        self.assertIsNone(metrics['recommendation'])
        frames = self.observe({'environment_level':0})
        for frame in frames:
            frame['right_speed_mps'] *= .8
        metrics = analyze(frames,frames[-1],.01)
        self.assertIn('drive_right_low',[f['code'] for f in metrics['findings']])

    def test_sensor_noise_and_dropout_are_distinct_from_drive_deviation(self):
        frames = self.observe({'environment_level':2})
        metrics = analyze(frames,frames[-1],.01)
        self.assertIn('sensor_reference_difference',[f['code'] for f in metrics['findings']])
        self.assertFalse(any(f['code'].startswith('drive_') for f in metrics['findings']))
        frames = self.observe({'environment_level':0,'dropout':True,'Kp':.05,'Ki':0,'Kd':0})
        metrics = analyze(frames,frames[-1],.01)
        codes = [f['code'] for f in metrics['findings']]
        self.assertIn('stop_1',codes)
        self.assertIn('sensor_reference_difference',codes)
        self.assertIsNone(metrics['recommendation'])

    def test_stale_and_missing_data_suspend_fresh_diagnosis(self):
        frames = self.observe({'environment_level':0,'motor_left_factor':.8})
        metrics = analyze(frames,frames[-1],2.)
        self.assertEqual([f['code'] for f in metrics['findings']],['telemetry_stale'])
        self.assertIsNone(metrics['recommendation'])
        frames[-10]['gap_before'] = True
        metrics = analyze(frames,frames[-1],.01)
        self.assertFalse(any(f['code'].startswith('drive_') for f in metrics['findings']))
        self.assertIn('insufficient_window',[f['code'] for f in metrics['findings']])


if __name__ == '__main__':
    unittest.main(verbosity=2)
