"""Horizontal Runtime orchestrator.

Assembles L1-L7 components, manages lifecycle and the 20 ms source clock,
coordinates telemetry and command flow, and protects state with an RLock."""
from collections import deque
from datetime import datetime
from pathlib import Path
import queue
import threading
import time
import uuid

# L1 Physical Layer
from layers.l1_physical import PhysicalTrack, VehicleConfig
# L2 Acquisition Layer
from layers.l2_acquisition import SimulationSource
# L3 Communication Layer
from layers.l3_communication import MqttTransport
# L4 Data Management Layer
from layers.l4_data_management import TelemetryReceiver, ExperimentStore, received_csv
# L5 Twin Model Layer
from layers.l5_twin_model import TwinModel
# L6 Service and Feedback Layer
from layers.l6_service_feedback import analyze, CommandService


class Runtime:
    def __init__(self, port=18884, results=None):
        self.lock = threading.RLock()
        self.stop = threading.Event()
        self.events = deque(maxlen=80)

        # 1. Assemble layer components.
        self.track = PhysicalTrack()                             # L1 track environment
        self.asset = SimulationSource(self.track)                # L2 acquisition source and simulator
        self.store = ExperimentStore(results or Path(__file__).parent / 'results') # L4 persistent experiment storage
        self.commands = CommandService()                         # L6 command decision service
        session = uuid.uuid4().hex[:12]
        self.receiver = TelemetryReceiver(session)               # L4 telemetry ingestion and validation
        self.twin_model = TwinModel()                            # L5 virtual twin model
        self.mqtt = MqttTransport(session, port, self._queue_command, self.receive,
                                  self._acknowledge, self._reject) # L3 communication transport

        # 2. Start the shared orchestration worker.
        self.thread = threading.Thread(target=self.work, name='vehicle-source', daemon=True)
        self.thread.start()
        self.event('Runtime ready: MQTT connected; all seven layers initialized.')

    def event(self, text):
        self.events.append({'time': datetime.now().strftime('%H:%M:%S'), 'text': text})

    def _reject(self, channel):
        with self.lock:
            if channel == 'command':
                self.event('The source rejected a malformed command or a full command queue.')
            else:
                self.receiver.rejected += 1
                self.event('The receiver isolated a message with invalid format or numeric values.')

    def _queue_command(self, packet):
        with self.lock:
            try:
                self.commands.enqueue(packet)
            except queue.Full:
                self._reject('command')

    def _acknowledge(self, packet):
        with self.lock:
            if self.commands.acknowledge(packet):
                self.event(f"Source acknowledgement · {packet['status']} · {packet.get('message', '')}")

    def receive(self, packet):
        """Schedule received data from L3 transport through L4 validation to L5 prediction and correction."""
        with self.lock:
            new_run = self.receiver.accept(packet)
            if new_run is None:
                return
            if new_run:
                self.twin_model.reset()
            self.twin_model.update(packet)

    def command(self, action, values=None):
        """Schedule L7 user decisions through L6 command packaging to L3 publication."""
        with self.lock:
            identifier = self.commands.request(action, values, self.mqtt.observer_online,
                                                self.mqtt.publish_command)
            self.event(f'Command sent · {action} · {identifier[:8]}')
            return identifier

    def _save_completed(self):
        if self.asset.pending_save:
            self.store.save_run(self.asset.run_id, self.asset.sim.config,
                                self.asset.frames, self.asset.frame)
            self.asset.pending_save = False
            self.event(f"Experiment completed; simulation time {self.asset.frame['t_sim_s']:.2f} s")

    def _execute_action(self, action, values):
        result = self.asset.execute(action, values)
        self._save_completed()
        if action == 'step':
            self.publish()
        return result

    def apply_command(self, packet):
        ack = self.commands.execute(packet, self._execute_action)
        self.mqtt.publish_ack(ack)
        self.publish()

    def publish(self):
        """Publish the L2 telemetry frame through L3 transport."""
        self.mqtt.publish_observation(self.asset.frame, self.asset.run_id, self.asset.state)

    def advance(self):
        self.asset.advance()
        self._save_completed()
        self.publish()

    def work(self):
        """Coordinate the source clock, physical time steps and idle heartbeats."""
        next_step = last_heartbeat = time.monotonic()
        try:
            while not self.stop.wait(.001):
                with self.lock:
                    while not self.commands.queue.empty():
                        self.apply_command(self.commands.queue.get_nowait())
                        next_step = time.monotonic() + .02 / self.asset.sim.config.speed
                    now = time.monotonic()
                    steps = 0
                    while self.asset.state == 'running' and now >= next_step and steps < 40:
                        self.advance()
                        next_step += .02 / self.asset.sim.config.speed
                        steps += 1
                        now = time.monotonic()
                    if now - next_step > .5:
                        next_step = now
                    if now - last_heartbeat >= .2:
                        if self.asset.state != 'running':
                            self.publish()
                        last_heartbeat = now
        except Exception as error:
            with self.lock:
                self.asset.state = 'paused'
                self.event(f'Source execution failed · {error}')

    def transport(self, channel, enabled):
        self.mqtt.set_channel(channel, enabled)
        with self.lock:
            label = 'Telemetry upload' if channel == 'upload' else 'Command subscription'
            status = ' resumed' if enabled else (' paused' if channel == 'upload' else ' disconnected')
            self.event(label + status)

    def export_received(self):
        with self.lock:
            frames = list(self.receiver.history)
            run_id = self.receiver.latest['run_id'] if self.receiver.latest else 'empty'
        return received_csv(frames), run_id

    def snapshot(self):
        """Aggregate model, data and service state for the L7 dashboard."""
        with self.lock:
            age, quality = self.receiver.freshness()
            frame = self.receiver.latest.copy() if self.receiver.latest else None
            metrics = analyze(self.receiver.history, frame, age)
            history = self.receiver.history
            chart_keys = ('t_sim_s', 'x_m', 'y_m', 'sensor_error', 'P', 'I', 'D',
                          'uL', 'uR', 'left_speed_mps', 'right_speed_mps', 'gap_before',
                          *TwinModel.SAMPLE_OUTPUTS)
            display_frames = [f for i, f in enumerate(history) if i % 5 == 0 or f['gap_before']
                              or (i + 1 < len(history) and history[i + 1]['gap_before'])]
            if history and (not display_frames or display_frames[-1] is not history[-1]):
                display_frames = display_frames + [history[-1]]
            chart_history = [{key: f[key] for key in chart_keys} for f in display_frames]
            mqtt_state = self.mqtt.snapshot()
            mqtt_state.update(received=self.receiver.received, rejected=self.receiver.rejected,
                              duplicates=self.receiver.duplicates, gaps=self.receiver.gaps)
            twin = self.twin_model.state.copy() if self.twin_model.state else None
            return dict(frame=frame, twin=twin, history=chart_history, metrics=metrics,
                        quality=quality, age_s=age, source_time_s=self.asset.frame['t_sim_s'],
                        source_state=self.asset.state, mqtt=mqtt_state,
                        command=self.commands.snapshot(), events=list(self.events)[-20:],
                        payload=frame.copy() if frame else None, records=list(self.store.records))

    def close(self):
        self.stop.set()
        self.thread.join(timeout=3)
        self.mqtt.close()
