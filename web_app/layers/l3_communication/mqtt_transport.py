"""Communication only: JSON dictionaries <-> MQTT telemetry/command/ack topics.

Owns two independent Paho clients and protocol settings. Numerical modeling,
schema validation, command execution and file persistence are other modules.
"""
from datetime import datetime, timezone
import json
import threading

import paho.mqtt.client as mqtt


class MqttTransport:
    def __init__(self, session, port, on_command, on_telemetry, on_ack, on_invalid):
        self.session, self.port = session, port
        self.prefix = f'dt/car01/{session}'
        self.on_command, self.on_telemetry = on_command, on_telemetry
        self.on_ack, self.on_invalid = on_ack, on_invalid
        self.source_online = self.observer_online = False
        self.upload_enabled = self.feedback_enabled = True
        self.seq = self.sent = 0
        self.source_ready = threading.Event()
        self.observer_ready = threading.Event()
        self.subscription_ready = threading.Event()
        self.source = self._client('source', self._source_connect, self._source_message)
        self.observer = self._client('observer', self._observer_connect, self._observer_message)
        self.source.on_subscribe = lambda *args: (self.source_ready.set(), self.subscription_ready.set())
        self.source.on_unsubscribe = lambda *args: self.subscription_ready.set()
        self.observer.on_subscribe = lambda *args: self.observer_ready.set()
        self.source.on_disconnect = lambda *args: setattr(self, 'source_online', False)
        self.observer.on_disconnect = lambda *args: setattr(self, 'observer_online', False)
        try:
            for client in (self.source, self.observer):
                client.connect('127.0.0.1', port, keepalive=10)
                client.loop_start()
            if not self.source_ready.wait(5) or not self.observer_ready.wait(5):
                raise ConnectionError('MQTT subscription was not acknowledged. Check the broker.')
        except Exception:
            self.close()
            raise

    def _client(self, suffix, connect, message):
        client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,
                             client_id=f'car-{self.session}-{suffix}', clean_session=True)
        client.on_connect, client.on_message = connect, message
        client.reconnect_delay_set(1, 3)
        client.max_queued_messages_set(200)
        return client

    def _source_connect(self, client, userdata, flags, reason, properties):
        self.source_online = not reason.is_failure
        if self.source_online and self.feedback_enabled:
            client.subscribe(self.prefix + '/command', qos=1)

    def _observer_connect(self, client, userdata, flags, reason, properties):
        self.observer_online = not reason.is_failure
        if self.observer_online:
            client.subscribe([(self.prefix + '/telemetry', 1), (self.prefix + '/ack', 1)])

    def _source_message(self, client, userdata, message):
        try:
            self.on_command(json.loads(message.payload))
        except (ValueError, TypeError, KeyError, OverflowError):
            self.on_invalid('command')

    def _observer_message(self, client, userdata, message):
        try:
            value = json.loads(message.payload)
            if message.topic.endswith('/ack'):
                self.on_ack(value)
            else:
                self.on_telemetry(value)
        except (ValueError, TypeError, KeyError, OverflowError):
            self.on_invalid('telemetry')

    def _publish(self, client, topic, packet):
        result = client.publish(self.prefix + '/' + topic,
                                json.dumps(packet, allow_nan=False), qos=1, retain=False)
        return result.rc == mqtt.MQTT_ERR_SUCCESS

    def publish_observation(self, frame, run_id, source_state):
        packet = dict(frame, session=self.session, run_id=run_id, seq=self.seq,
                      sent_utc=datetime.now(timezone.utc).isoformat(), source_state=source_state)
        # Advance even while disabled, so resumed telemetry exposes sequence gaps.
        self.seq += 1
        if self.upload_enabled and self.source_online:
            self.sent += int(self._publish(self.source, 'telemetry', packet))

    def publish_command(self, packet):
        return self._publish(self.observer, 'command', packet)

    def publish_ack(self, packet):
        return self._publish(self.source, 'ack', packet)

    def set_channel(self, channel, enabled):
        if type(enabled) is not bool or channel not in ('upload', 'feedback'):
            raise ValueError('Invalid channel-switch parameters.')
        if channel == 'upload':
            self.upload_enabled = enabled
            return
        self.subscription_ready.clear()
        self.feedback_enabled = enabled
        operation = (self.source.subscribe(self.prefix + '/command', qos=1) if enabled
                     else self.source.unsubscribe(self.prefix + '/command'))
        if operation[0] != mqtt.MQTT_ERR_SUCCESS or not self.subscription_ready.wait(3):
            raise ValueError('MQTT did not acknowledge the command-subscription change.')

    def snapshot(self):
        return dict(connected=self.source_online and self.observer_online,
                    port=self.port, prefix=self.prefix, sent=self.sent,
                    upload=self.upload_enabled, feedback=self.feedback_enabled)

    def close(self):
        for client in (self.source, self.observer):
            client.disconnect()
            client.loop_stop()
