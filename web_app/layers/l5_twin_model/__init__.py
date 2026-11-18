"""L5 Twin Model Layer: nominal prediction, residuals and observation correction.
Outputs corrected state, healthy references, innovation and conditional forecasts."""
from .twin_model import TwinModel, NOMINAL_GAIN, WHEEL_BASE_M

__all__ = [
    'TwinModel',
    'NOMINAL_GAIN',
    'WHEEL_BASE_M',
]

