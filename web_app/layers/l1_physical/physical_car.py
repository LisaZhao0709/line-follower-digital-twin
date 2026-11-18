"""L1: differential-drive chassis geometry, motor response and exact pose integration."""
from dataclasses import dataclass
import math


@dataclass
class PhysicalCarState:
    """Current physical state of the vehicle."""
    x: float
    y: float
    theta: float
    vL: float = 0.0
    vR: float = 0.0
    uL: float = 0.0
    uR: float = 0.0


class DifferentialChassis:
    """Physical model of a two-wheel differential-drive chassis."""
    Ts: float = 0.02          # Physical step: 20 ms
    km: float = 0.35          # Nominal motor gain (m/s per normalized command)
    wheel_base: float = 0.12  # Wheel separation: 12 cm

    def __init__(self, x0: float, y0: float, theta0: float):
        self.state = PhysicalCarState(x=x0, y=y0, theta=theta0)

    def drive(self, uL: float, uR: float, motor_left_factor: float = 1.0):
        """Calculate actual actuator wheel speeds in metres per second."""
        vL = self.km * motor_left_factor * uL
        vR = self.km * uR
        self.state.uL = uL
        self.state.uR = uR
        self.state.vL = vL
        self.state.vR = vR
        return vL, vR

    def update_pose(self, vL: float, vR: float, dt: float = 0.02):
        """Advance (x, y, theta) using an exact constant-command circular arc."""
        v = (vL + vR) / 2.0
        omega = (vR - vL) / self.wheel_base
        half = omega * dt / 2.0
        factor = math.sin(half) / half if abs(half) > 1e-10 else 1.0

        self.state.x += dt * v * factor * math.cos(self.state.theta + half)
        self.state.y += dt * v * factor * math.sin(self.state.theta + half)
        self.state.theta += omega * dt
        return self.state.x, self.state.y, self.state.theta

