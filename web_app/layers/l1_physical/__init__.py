"""L1 Physical Layer: geometry, motion state and onboard execution.
Outputs pose, wheel speeds and normalized motor commands."""
from .physical_car import DifferentialChassis, PhysicalCarState
from .track import PhysicalTrack, VehicleConfig
from .controller import OnboardController

__all__ = [
    'DifferentialChassis',
    'PhysicalCarState',
    'PhysicalTrack',
    'VehicleConfig',
    'OnboardController',
]

