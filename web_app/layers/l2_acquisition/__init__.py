"""L2 Acquisition Layer: sampling, timestamps and frame packaging.
Outputs raw telemetry observation frames."""
from .sensors import SensorArray, SENSOR_WEIGHTS
from .telemetry_packager import TelemetryPackager
from .simulation_source import SimulationSource

__all__ = [
    'SensorArray',
    'SENSOR_WEIGHTS',
    'TelemetryPackager',
    'SimulationSource',
]

