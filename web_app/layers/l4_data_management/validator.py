"""Data ingestion: decoded telemetry -> validated, ordered observation history.

No MQTT clients, model equations, source execution or disk writes live here.
"""
import math
import time

from layers.l1_physical import VehicleConfig as Config


def validate_observation(packet, session):
    """Check the existing telemetry schema; raise on invalid observations."""
    if not isinstance(packet, dict) or packet.get('session') != session:
        raise ValueError('Session mismatch.')
    if type(packet['seq']) is not int or packet['seq'] < 0 or not isinstance(packet.get('run_id'), str):
        raise ValueError('Invalid sequence number or run ID.')
    keys = ('t_sim_s', 'sample_index', 'x_m', 'y_m', 'theta_rad', 'sensor_error',
            'P', 'I', 'D', 'uL', 'uR', 'left_speed_mps', 'right_speed_mps')
    if not all(type(packet[key]) in (int, float) and math.isfinite(packet[key]) for key in keys):
        raise ValueError('Invalid numeric value.')
    for name in ('strengths', 'ideal_strengths', 'sensors', 'sensor_x', 'sensor_y'):
        values = packet[name]
        if not isinstance(values, list) or len(values) != 8 or not all(
                type(value) in (int, float) and math.isfinite(value) for value in values):
            raise ValueError('Sensor arrays must contain eight finite numeric values.')
    if (not all(value in (0, 1) for value in packet['sensors'])
            or not all(0 <= value <= 1 for value in packet['strengths'] + packet['ideal_strengths'])
            or not 0 <= packet['uL'] <= 1 or not 0 <= packet['uR'] <= 1
            or packet['stop_reason'] not in (0, 1, 2, 4)
            or packet['source_state'] not in ('idle', 'running', 'paused', 'completed')):
        raise ValueError('Data value out of range.')
    Config.parse(packet['config'])
    if (packet['t_sim_s'] < 0 or type(packet['sample_index']) is not int
            or packet['sample_index'] < 0 or not isinstance(packet['completed_lap'], bool)):
        raise ValueError('Invalid simulation time or sample index.')


class TelemetryReceiver:
    def __init__(self, session):
        self.session = session
        self.latest = None
        self.history = []
        self.last_receive = None
        self.last_seq = -1
        self.received = self.rejected = self.duplicates = self.gaps = 0

    def accept(self, packet):
        """Return whether a new run began, or None for a duplicate message.

        Runtime enriches the accepted dictionary with model outputs immediately
        afterward, under the same lock. History holds that same dictionary.
        """
        validate_observation(packet, self.session)
        seq = packet['seq']
        if seq <= self.last_seq:
            self.duplicates += 1
            return None
        new_run = self.latest is None or packet['run_id'] != self.latest['run_id']
        if not new_run and (packet['sample_index'] < self.latest['sample_index']
                            or packet['t_sim_s'] < self.latest['t_sim_s']):
            raise ValueError('Source time moved backwards within the same run.')
        packet['gap_before'] = bool(not new_run and packet['sample_index'] > self.latest['sample_index'] + 1)
        if self.last_seq >= 0:
            self.gaps += max(0, seq - self.last_seq - 1)
        self.last_seq = seq
        self.received += 1
        self.last_receive = time.monotonic()
        if new_run:
            self.history = []
        self.latest = packet
        if not self.history or packet['sample_index'] != self.history[-1]['sample_index']:
            self.history.append(packet)
        return new_run

    def freshness(self):
        age = None if self.last_receive is None else time.monotonic() - self.last_receive
        quality = 'waiting' if age is None else ('stale' if age > 1.2 else 'good')
        return age, quality
