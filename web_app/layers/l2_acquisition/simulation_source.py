"""Acquisition source: experiment actions -> simulated vehicle observations.

SimulationSource owns source state; it neither sends MQTT nor writes files.
The numerical sensor/PID/vehicle equations remain in model.Simulator.
"""
from dataclasses import asdict
from datetime import datetime
import uuid

from layers.l1_physical import VehicleConfig as Config
from .telemetry_packager import TelemetryPackager as Simulator


class SimulationSource:
    def __init__(self, track):
        self.track = track
        self.sim = Simulator(track, Config())
        self.frame, _ = self.sim.step()
        # Preserve the original initial-state/idle-preview behavior.
        self.sim = Simulator(track, Config())
        self.frames = []
        self.run_id = 'ready'
        self.state = 'idle'
        self.pending_save = False

    def execute(self, action, values):
        """Execute one validated action; return source run/config for its ack."""
        if action in ('run', 'reset'):
            config = Config.parse(values) if action == 'run' else self.sim.config
            self.sim = Simulator(self.track, config)
            self.run_id = datetime.now().strftime('%Y%m%d_%H%M%S_') + uuid.uuid4().hex[:6]
            self.frames = []
            self.frame, _ = self.sim.step()
            self.frames.append(self.frame.copy())
            self.state = 'running' if action == 'run' else 'paused'
            self.pending_save = False
        elif action == 'pause':
            if self.state == 'running':
                self.state = 'paused'
        elif action in ('resume', 'step'):
            if self.state not in ('paused', 'running'):
                raise ValueError('Run or reset an experiment first.')
            if action == 'resume':
                self.state = 'running'
            else:
                self.state = 'paused'
                self.advance()
        else:
            raise ValueError('Unknown action.')
        return dict(run_id=self.run_id, config=asdict(self.sim.config))

    def advance(self):
        """Acquire one new 20 ms sample and mark a completed run for storage."""
        self.frame, done = self.sim.step()
        self.frames.append(self.frame.copy())
        if done:
            self.pending_save = True
            self.state = 'completed'
