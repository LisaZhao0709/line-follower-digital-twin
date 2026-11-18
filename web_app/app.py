"""Start the MQTT broker, Runtime orchestrator and L7 web dashboard."""
import argparse
import atexit
import logging
import threading
import time
import urllib.request
import webbrowser

from layers.l1_physical.track import DATA_DIR as DATA
from layers.l3_communication.broker_process import BrokerProcess
from layers.l7_application.web_api import create_app
from runtime import Runtime


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--broker-port', type=int, default=18884)
    parser.add_argument('--open-browser', action='store_true')
    args = parser.parse_args()
    logging.getLogger('werkzeug').setLevel(logging.ERROR)
    broker = BrokerProcess(args.broker_port)
    runtime = None

    def cleanup():
        if runtime:
            runtime.close()
        broker.close()

    atexit.register(cleanup)
    try:
        runtime = Runtime(args.broker_port)
        if args.open_browser:
            def open_when_ready():
                url = f'http://127.0.0.1:{args.port}'
                for _ in range(60):
                    try:
                        with urllib.request.urlopen(url + '/api/meta', timeout=1):
                            webbrowser.open(url)
                        return
                    except OSError:
                        time.sleep(.2)
            threading.Thread(target=open_when_ready, daemon=True).start()
        print(f'\nLine-Follower Digital Twin started.\nWeb dashboard:http://127.0.0.1:{args.port}\nMQTT broker:127.0.0.1:{args.broker_port}\nPress Ctrl+C to stop the application.\n', flush=True)
        create_app(runtime).run(host='127.0.0.1', port=args.port, threaded=True, use_reloader=False)
    finally:
        cleanup()


if __name__ == '__main__':
    main()
