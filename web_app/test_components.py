"""Offline component contracts; these tests do not claim to verify MQTT exchange.

The actual broker/client end-to-end test remains in test_system.IntegrationTest.
"""
import copy
import csv
import io
import json
import math
from pathlib import Path
import tempfile
import time
import unittest

from commands import CommandService
from model import Config, Simulator, Track
from source import SimulationSource
from storage import ExperimentStore, RECEIVED_COLUMNS, SENSOR_COLUMNS, received_csv
from telemetry import TelemetryReceiver
from twin_model import TwinModel


class TwinModelTests(unittest.TestCase):
    def observation(self, index, **changes):
        frame = dict(sample_index=index, t_sim_s=index * .02, x_m=0., y_m=0., theta_rad=0.,
                     uL=0., uR=1., left_speed_mps=0., right_speed_mps=.35)
        frame.update(changes)
        return frame

    def test_prediction_matches_independent_circular_arc_reference(self):
        twin = TwinModel()
        first = self.observation(0)
        twin.update(first)
        second = self.observation(1)
        state = twin.update(second)
        # Turning about the stationary left wheel gives radius b/2 = .06 m.
        angle = (.35 / .12) * .02
        expected = [.06 * math.sin(angle), .06 * (1 - math.cos(angle))]
        self.assertAlmostEqual(state['prior_xy'][0], expected[0], places=14)
        self.assertAlmostEqual(state['prior_xy'][1], expected[1], places=14)
        self.assertAlmostEqual(state['innovation_m'], math.hypot(*expected), places=14)
        self.assertEqual((state['x_m'], state['y_m']), (0., 0.))

    def test_fault_observation_heartbeat_and_new_run_have_distinct_effects(self):
        twin = TwinModel()
        frame = self.observation(0, uL=.4, uR=.4, left_speed_mps=.112, right_speed_mps=.14)
        twin.update(frame)
        self.assertAlmostEqual(frame['expected_left_mps'], .14)
        self.assertAlmostEqual(frame['residual_mps'], .028)
        previous = copy.deepcopy(twin.state)
        twin.update(copy.deepcopy(frame))
        self.assertEqual(twin.updates, 1)
        self.assertEqual(twin.state['prior_xy'], previous['prior_xy'])
        twin.reset()
        new_run = self.observation(0, x_m=4., y_m=5.)
        twin.update(new_run)
        self.assertEqual(twin.state['prior_xy'], [4., 5.])
        self.assertEqual(twin.state['innovation_m'], 0.)
        self.assertEqual(twin.updates, 2)

    def test_nominal_replay_matches_healthy_asset_and_exposes_unlabelled_fault(self):
        track = Track()
        for factor in (1., .8):
            with self.subTest(factor=factor):
                source = Simulator(track, Config(environment_level=0, motor_left_factor=factor))
                twin = TwinModel()
                maximum_innovation = 0.
                for _ in range(151):
                    frame, _ = source.step()
                    # Hide the injection setting: L5 must derive deviations from measurements.
                    frame['config'] = {'motor_left_factor': 1.}
                    state = twin.update(frame)
                    maximum_innovation = max(maximum_innovation, state['innovation_m'])
                self.assertEqual(twin.updates, 151)
                if factor == 1.:
                    self.assertLess(maximum_innovation, 1e-12)
                    self.assertLess(state['nominal_drift_m'], 1e-12)
                    self.assertAlmostEqual(state['nominal_theta_rad'], frame['theta_rad'], places=12)
                else:
                    self.assertLess(state['residual_left_mps'], -.005)
                    self.assertAlmostEqual(state['residual_right_mps'], 0.)
                    self.assertGreater(maximum_innovation, .0001)
                    self.assertGreater(state['nominal_drift_m'], .005)
                    self.assertEqual((state['x_m'], state['y_m']), (frame['x_m'], frame['y_m']))

    def test_forecast_is_conditional_and_heartbeat_does_not_recompute(self):
        twin = TwinModel()
        frame = self.observation(0, uL=.4, uR=.4, left_speed_mps=.14, right_speed_mps=.14)
        state = twin.update(frame)
        future = state['forecast'][-1]
        self.assertEqual(len(state['forecast']), 11)
        self.assertEqual(future['dt_s'], 1.)
        self.assertAlmostEqual(future['x_m'], .14)
        self.assertAlmostEqual(future['y_m'], 0.)
        previous = copy.deepcopy(state)
        twin.update(copy.deepcopy(frame))
        self.assertEqual(twin.state, previous)
        self.assertFalse(state['prediction_valid'])

    def test_missing_commands_reanchor_reference_without_invented_innovation(self):
        twin = TwinModel()
        twin.update(self.observation(0))
        frame = self.observation(10, x_m=4., y_m=5., gap_before=True)
        state = twin.update(frame)
        self.assertEqual(state['phase'], 'resynced')
        self.assertFalse(state['prediction_valid'])
        self.assertEqual(state['innovation_m'], 0.)
        self.assertEqual(state['nominal_drift_m'], 0.)
        self.assertEqual(state['nominal_elapsed_s'], 0.)
        following = twin.update(self.observation(11, x_m=4., y_m=5.))
        self.assertTrue(following['prediction_valid'])
        self.assertAlmostEqual(following['prediction_dt_s'], .02)

    def test_new_command_does_not_rewrite_previous_motion_interval(self):
        twin = TwinModel()
        twin.update(self.observation(0, uL=.4, uR=.4))
        state = twin.update(self.observation(1, x_m=.14*.02, uL=0., uR=0.))
        self.assertLess(state['innovation_m'], 1e-14)
        self.assertAlmostEqual(state['prior_theta_rad'], 0.)
        self.assertAlmostEqual(state['forecast'][-1]['x_m'], state['x_m'])


class IngestionAndStorageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.track = Track()

    def packet(self, index=0, seq=None, run_id='run-a'):
        simulator = Simulator(self.track, Config(environment_level=0))
        for _ in range(index + 1):
            frame, _ = simulator.step()
        return dict(frame, session='test-session', run_id=run_id,
                    seq=index if seq is None else seq, source_state='running')

    def test_deduplication_gap_detection_new_run_and_data_freshness(self):
        receiver = TelemetryReceiver('test-session')
        self.assertEqual(receiver.freshness(), (None, 'waiting'))
        self.assertTrue(receiver.accept(self.packet()))
        self.assertIsNone(receiver.accept(self.packet()))
        self.assertEqual((receiver.received, receiver.duplicates), (1, 1))
        self.assertFalse(receiver.accept(self.packet(3, seq=3)))
        self.assertTrue(receiver.latest['gap_before'])
        self.assertEqual(receiver.gaps, 2)
        self.assertEqual(receiver.freshness()[1], 'good')
        receiver.last_receive = time.monotonic() - 2
        self.assertEqual(receiver.freshness()[1], 'stale')
        self.assertTrue(receiver.accept(self.packet(0, seq=4, run_id='run-b')))
        self.assertEqual(len(receiver.history), 1)
        self.assertFalse(receiver.latest['gap_before'])

    def test_invalid_and_backward_samples_do_not_replace_latest_observation(self):
        receiver = TelemetryReceiver('test-session')
        receiver.accept(self.packet(2))
        for change in ({'strengths': [0] * 7}, {'x_m': float('nan')}, {'session': 'other'}):
            invalid = self.packet(3)
            invalid.update(change)
            with self.assertRaises(ValueError):
                receiver.accept(invalid)
        with self.assertRaises(ValueError):
            receiver.accept(self.packet(1, seq=4))
        self.assertEqual(receiver.received, 1)
        self.assertEqual(receiver.latest['sample_index'], 2)

    def test_source_files_and_received_export_preserve_separate_schemas(self):
        source = SimulationSource(self.track)
        source.execute('run', dict(environment_level=0, dropout=True))
        while source.state != 'completed':
            source.advance()
        self.assertTrue(source.pending_save)
        self.assertEqual(source.frame['stop_reason'], 1)
        work = Path(__file__).parent / 'runtime'
        work.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=work) as folder:
            store = ExperimentStore(folder)
            summary = store.save_run(source.run_id, source.sim.config, source.frames, source.frame)
            saved = json.loads((Path(folder) / source.run_id / 'summary.json').read_text(encoding='utf-8'))
            self.assertEqual(saved, summary)
            self.assertEqual(store.records[0], summary)
            with (Path(folder) / source.run_id / 'source.csv').open(encoding='utf-8-sig', newline='') as file:
                rows = list(csv.DictReader(file))
            self.assertEqual(len(rows), len(source.frames))
            self.assertAlmostEqual(float(rows[-1]['t_sim_s']), 1.2)
            self.assertNotIn('expected_left_mps', rows[0])

        receiver, twin = TelemetryReceiver('test-session'), TwinModel()
        for index in range(3):
            packet = self.packet(index)
            if receiver.accept(packet):
                twin.reset()
            twin.update(packet)
        output = received_csv(receiver.history)
        self.assertTrue(output.startswith('\ufeff'))
        reader = csv.DictReader(io.StringIO(output.lstrip('\ufeff')))
        self.assertEqual(reader.fieldnames, RECEIVED_COLUMNS + SENSOR_COLUMNS)
        received = list(reader)
        self.assertEqual(len(received), 3)
        self.assertAlmostEqual(float(received[0]['expected_left_mps']), .35 * float(received[0]['uL']))


class CommandLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.track = Track()

    def test_source_executes_only_once_and_ack_matches_the_pending_request(self):
        commands, source = CommandService(), SimulationSource(self.track)
        published = []
        identifier = commands.request('run', {'environment_level': 0}, True,
                                      lambda packet: published.append(packet) or True)
        self.assertEqual(source.state, 'idle')
        commands.enqueue(published[0])
        packet = commands.queue.get_nowait()
        ack = commands.execute(packet, source.execute)
        run_id = source.run_id
        duplicate = commands.execute(packet, source.execute)
        self.assertEqual(ack, duplicate)
        self.assertEqual(source.run_id, run_id)
        self.assertEqual(source.state, 'running')
        self.assertFalse(commands.acknowledge(dict(command_id='unrelated', status='applied')))
        self.assertEqual(commands.current['status'], 'pending')
        self.assertTrue(commands.acknowledge(ack))
        self.assertEqual(commands.snapshot()['status'], 'applied')
        self.assertEqual(commands.snapshot()['command_id'], identifier)
        commands.request('pause', None, True, lambda packet: True)
        commands.current['created'] -= 4
        self.assertEqual(commands.snapshot()['status'], 'timeout')
        self.assertEqual(source.state, 'running')

    def test_rejected_and_disconnected_commands_do_not_change_source_state(self):
        source, commands = SimulationSource(self.track), CommandService()
        with self.assertRaises(ValueError):
            commands.request('run', {}, False, lambda packet: self.fail('Disconnected command was sent'))
        ack = commands.execute(dict(command_id='bad', action='run', config={'Kp': -1}), source.execute)
        self.assertEqual(ack['status'], 'rejected')
        self.assertEqual(source.state, 'idle')


if __name__ == '__main__':
    unittest.main(verbosity=2)
