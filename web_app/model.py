"""Compatibility exports for model.

Implementations live in the corresponding modules under layers/."""
from layers.l1_physical.track import DATA_DIR as DATA, PhysicalTrack as Track, VehicleConfig as Config
from layers.l2_acquisition.sensors import SENSOR_WEIGHTS as WEIGHTS, SensorArray
from layers.l2_acquisition.telemetry_packager import TelemetryPackager as Simulator

__all__ = [
    'DATA',
    'WEIGHTS',
    'Config',
    'Track',
    'SensorArray',
    'Simulator',
]
