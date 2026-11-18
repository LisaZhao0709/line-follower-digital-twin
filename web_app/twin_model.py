"""Compatibility exports for twin_model.

Implementations live in the corresponding modules under layers/."""
from layers.l5_twin_model.twin_model import TwinModel, NOMINAL_GAIN, WHEEL_BASE_M

__all__ = [
    'TwinModel',
    'NOMINAL_GAIN',
    'WHEEL_BASE_M',
]
