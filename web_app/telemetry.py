"""Compatibility exports for telemetry.

Implementations live in the corresponding modules under layers/."""
from layers.l4_data_management.validator import validate_observation, TelemetryReceiver

__all__ = [
    'validate_observation',
    'TelemetryReceiver',
]
