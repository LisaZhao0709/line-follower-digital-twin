"""Command lifecycle: request IDs, queue, execution deduplication and ack state.

Publishing and source execution are explicit injected callables, not imports
of MQTT clients, the Simulator or the runtime orchestrator.
"""
from dataclasses import asdict
import queue
import time
import uuid

from layers.l1_physical import VehicleConfig as Config


class CommandService:
    def __init__(self):
        self.queue = queue.Queue(maxsize=100)
        self.current = None
        self.processed = {}

    def request(self, action, values, connected, publish):
        """Input user action/config; output a published command ID."""
        if action not in ('run', 'pause', 'resume', 'step', 'reset'):
            raise ValueError('Unknown action.')
        config = asdict(Config.parse(values or {})) if action == 'run' else None
        if not connected:
            raise ValueError('MQTT is disconnected; commands cannot be sent.')
        if self.current and self.current['status'] == 'pending' and time.monotonic() - self.current['created'] < 3:
            raise ValueError('The previous command is still awaiting a source acknowledgement.')
        identifier = uuid.uuid4().hex
        packet = dict(command_id=identifier, action=action, config=config)
        self.current = dict(command_id=identifier, action=action, status='pending',
                            created=time.monotonic(), message='Sent; awaiting source acknowledgement.')
        if not publish(packet):
            self.current['status'] = 'failed'
            raise ValueError('Command publication failed.')
        return identifier

    def enqueue(self, packet):
        if not isinstance(packet, dict) or not isinstance(packet.get('command_id'), str):
            raise ValueError('Invalid command format.')
        self.queue.put_nowait(packet)

    def execute(self, packet, apply):
        """Execute once at the source; return the cached or newly produced ack."""
        identifier = packet['command_id']
        if identifier in self.processed:
            return self.processed[identifier]
        try:
            result = apply(packet['action'], packet.get('config'))
            ack = dict(command_id=identifier, status='applied', **result, message='Applied at the source.')
        except (ValueError, TypeError, KeyError) as error:
            ack = dict(command_id=identifier, status='rejected', message=str(error))
        self.processed[identifier] = ack
        if len(self.processed) > 256:
            del self.processed[next(iter(self.processed))]
        return ack

    def acknowledge(self, packet):
        """Accept only an ack matching the currently pending command."""
        if not isinstance(packet, dict):
            raise ValueError('Invalid acknowledgement format.')
        if self.current and packet.get('command_id') == self.current['command_id']:
            if 'status' not in packet:
                raise ValueError('Acknowledgement status is missing.')
            self.current.update(packet)
            return True
        return False

    def snapshot(self):
        command = self.current.copy() if self.current else None
        if command and command['status'] == 'pending' and time.monotonic() - command['created'] >= 3:
            command.update(status='timeout', message='Source acknowledgement timed out; execution outcome is unknown.')
        if command:
            command.pop('created', None)
        return command
