"""Data management: source samples -> run files; received samples -> CSV text.

This module owns file/column layout, not vehicle or twin calculations.
"""
from collections import deque
from dataclasses import asdict
from pathlib import Path
import csv
import io
import json


SOURCE_COLUMNS = ['t_sim_s', 'x_m', 'y_m', 'theta_rad', 'sensor_error', 'P', 'I', 'D',
                  'uL', 'uR', 'left_speed_mps', 'right_speed_mps', 'stop_reason']
RECEIVED_COLUMNS = ['seq', 'sample_index', 't_sim_s', 'x_m', 'y_m', 'theta_rad',
                    'sensor_error', 'P', 'I', 'D', 'uL', 'uR', 'left_speed_mps', 'right_speed_mps',
                    'expected_left_mps', 'expected_right_mps', 'residual_mps', 'stop_reason',
                    'residual_left_mps', 'residual_right_mps', 'prior_x_m', 'prior_y_m',
                    'prior_theta_rad', 'innovation_m', 'innovation_theta_rad',
                    'prediction_valid', 'prediction_dt_s', 'nominal_x_m', 'nominal_y_m',
                    'nominal_theta_rad', 'nominal_drift_m', 'nominal_elapsed_s']
SENSOR_COLUMNS = [f'strength{index}' for index in range(1, 9)]


def write_samples(file, frames, columns):
    writer = csv.DictWriter(file, fieldnames=columns + SENSOR_COLUMNS)
    writer.writeheader()
    for frame in frames:
        row = {key: frame[key] for key in columns}
        row.update(zip(SENSOR_COLUMNS, frame['strengths']))
        writer.writerow(row)


def received_csv(frames):
    """Return the existing BOM-prefixed MQTT download format, without HTTP."""
    output = io.StringIO(newline='')
    write_samples(output, frames, RECEIVED_COLUMNS)
    return '\ufeff' + output.getvalue()


class ExperimentStore:
    def __init__(self, root):
        self.root = Path(root)
        self.records = deque(maxlen=20)

    def save_run(self, run_id, config, frames, final_frame):
        """Store source.csv/summary.json and return the completed-run summary."""
        folder = self.root / run_id
        folder.mkdir(parents=True, exist_ok=True)
        with (folder / 'source.csv').open('w', encoding='utf-8-sig', newline='') as file:
            write_samples(file, frames, SOURCE_COLUMNS)
        summary = dict(run_id=run_id, config=asdict(config),
                       completed_lap=final_frame['completed_lap'], lap_time_s=final_frame['lap_time_s'],
                       stop_reason=final_frame['stop_reason'], end_time_s=final_frame['t_sim_s'])
        (folder / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
        self.records.appendleft(summary)
        return summary
