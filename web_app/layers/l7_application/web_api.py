"""L7: REST API routes, browser commands, static dashboards and analysis downloads."""
import json
from pathlib import Path
from flask import Flask, Response, jsonify, request, send_file

from layers.l1_physical.track import DATA_DIR


def create_app(runtime, static_folder=None):
    """Create the Flask web application."""
    if static_folder is None:
        local_static = Path(__file__).parent / 'static'
        static_folder = str(local_static if local_static.exists() else Path(__file__).resolve().parents[1] / 'static')

    app = Flask(__name__, static_folder=static_folder, static_url_path='/static')
    app.config['MAX_CONTENT_LENGTH'] = 16 * 1024

    @app.get('/')
    def index():
        return app.send_static_file('index.html')

    @app.get('/api/state')
    def state():
        response = jsonify(runtime.snapshot())
        response.headers['Cache-Control'] = 'no-store'
        return response

    @app.get('/api/map')
    def track_image():
        return send_file(DATA_DIR / 'track_mask.png')

    @app.get('/api/meta')
    def meta():
        return jsonify(
            width=runtime.track.width,
            height=runtime.track.height,
            Ts=.02,
            telemetry_hz=50,
            initial=runtime.track.initial,
            units={'position': 'm', 'speed': 'm/s', 'time': 's', 'angle': 'rad', 'strength': '[0,1]'}
        )

    @app.post('/api/command')
    def command():
        value = request.get_json()
        try:
            if not isinstance(value, dict):
                raise ValueError('The request must be a JSON object.')
            action, config = value.get('action'), value.get('config')
            if action == 'recommend':
                current = runtime.snapshot()
                recommendation = current['metrics']['recommendation']
                if current['quality'] != 'good' or not recommendation:
                    raise ValueError('No executable recommendation is available from fresh observations.')
                action, config = 'run', recommendation['config']
            identifier = runtime.command(action, config)
            return jsonify(command_id=identifier, status='pending')
        except (ValueError, TypeError) as error:
            return jsonify(error=str(error)), 400

    @app.post('/api/transport')
    def transport():
        value = request.get_json()
        try:
            if not isinstance(value, dict):
                raise ValueError('The request must be a JSON object.')
            runtime.transport(value.get('channel'), value.get('enabled'))
            return jsonify(ok=True)
        except ValueError as error:
            return jsonify(error=str(error)), 400

    @app.get('/api/export')
    def export():
        content, run_id = runtime.export_received()
        return Response(content, mimetype='text/csv',
                        headers={'Content-Disposition': f'attachment; filename="mqtt_{run_id}.csv"'})

    @app.get('/api/analysis')
    def analysis_report():
        current = runtime.snapshot()
        frame = current['frame']
        report = dict(
            asset='car01',
            run_id=frame['run_id'] if frame else None,
            t_sim_s=frame['t_sim_s'] if frame else None,
            quality=current['quality'],
            analysis=current['metrics'],
            twin=current['twin'],
            basis='L5 fixed healthy model and residuals; L6 last-second receiver observations and teaching thresholds. The forecast assumes constant current commands.'
        )
        return Response(
            json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False),
            mimetype='application/json',
            headers={'Content-Disposition': 'attachment; filename="car01_analysis.json"'}
        )

    @app.get('/showcase')
    def showcase():
        """Serve the seven-layer architecture teaching dashboard."""
        from pathlib import Path as _P
        p = _P(static_folder) / 'showcase.html'
        return send_file(str(p))

    @app.get('/api/code/<layer_id>/<filename>')
    def code_source(layer_id, filename):
        """Return a layer source file as plain text for browser syntax highlighting."""
        from pathlib import Path as _P
        allowed = {
            'l1': 'l1_physical', 'l2': 'l2_acquisition',
            'l3': 'l3_communication', 'l4': 'l4_data_management',
            'l5': 'l5_twin_model', 'l6': 'l6_service_feedback',
            'l7': 'l7_application'
        }
        if layer_id not in allowed:
            return '', 404
        base = _P(__file__).parent.parent / allowed[layer_id]
        fp = base / filename
        if not fp.exists() or fp.suffix != '.py':
            return '', 404
        return Response(fp.read_text(encoding='utf-8'),
                        mimetype='text/plain; charset=utf-8')

    return app

