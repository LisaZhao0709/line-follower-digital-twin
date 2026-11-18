"""Compatibility exports for analysis.

Implementations live in the corresponding modules under layers/."""
from layers.l6_service_feedback.diagnostics import (
    analyze,
    finding,
    NOMINAL_GAIN,
    WINDOW_S,
    MIN_SAMPLES,
)

__all__ = [
    'analyze',
    'finding',
    'NOMINAL_GAIN',
    'WINDOW_S',
    'MIN_SAMPLES',
]
