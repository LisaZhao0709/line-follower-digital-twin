"""L3: start, probe and stop the local MQTT broker in a separate process."""
import os
from pathlib import Path
import socket
import subprocess
import sys
import time

WEB_APP_ROOT = Path(__file__).resolve().parents[2]


class BrokerProcess:
    def __init__(self, port):
        self.process = None
        self.log = None
        with socket.socket() as probe:
            if probe.connect_ex(('127.0.0.1', port)) == 0:
                raise RuntimeError(f'MQTT port {port} is in use. Close the previous application or choose another --broker-port.')
        (WEB_APP_ROOT / 'runtime').mkdir(exist_ok=True)
        self.log = (WEB_APP_ROOT / 'runtime' / 'broker.log').open('a', encoding='utf-8')
        broker_script = Path(__file__).parent / 'broker.py'
        options = {'creationflags': subprocess.CREATE_NO_WINDOW} if os.name == 'nt' else {}
        self.process = subprocess.Popen([sys.executable, '-B', str(broker_script), '--port', str(port)],
                                        stdout=self.log, stderr=self.log, cwd=str(WEB_APP_ROOT), **options)
        for _ in range(100):
            if self.process.poll() is not None:
                self.close()
                raise RuntimeError('MQTT broker failed to start. See runtime/broker.log.')
            with socket.socket() as probe:
                if probe.connect_ex(('127.0.0.1', port)) == 0:
                    return
            time.sleep(.1)
        self.close()
        raise RuntimeError('MQTT broker startup timed out.')

    def close(self):
        if self.process and self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=3)
        if self.log:
            self.log.close()

