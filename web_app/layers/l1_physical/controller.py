"""L1: onboard PID control and line-loss, boundary and time-limit safety stops."""
import numpy as np


class OnboardController:
    """Onboard control and safety protection for the vehicle."""
    Ts: float = 0.02
    base_speed: float = 0.35

    def __init__(self, Kp: float = 0.45, Ki: float = 0.015, Kd: float = 0.03):
        self.Kp = Kp
        self.Ki = Ki
        self.Kd = Kd
        self.integral = 0.0
        self.derivative = 0.0
        self.last_error = 0.0
        self.loss_start = None
        self.stop_reason = 0  # 0: normal; 1: line-loss timeout; 2: map boundary exit; 4: simulation time limit

    def compute_pid(self, error: float, detected: bool):
        """Calculate discrete PID output with a filtered derivative."""
        self.derivative = 0.2 * (error - self.last_error) / self.Ts + 0.8 * self.derivative
        p = self.Kp * error
        d = self.Kd * self.derivative

        if self.Ki == 0:
            self.integral = 0.0
        elif detected:
            delta = self.Ki * error * self.Ts
            candidate = float(np.clip(self.integral + delta, -0.2, 0.2))
            total = p + d + candidate
            # Conditional integration for anti-windup
            if not (abs(total) > 0.35 and total * delta > 0):
                self.integral = candidate

        correction = p + self.integral + d
        self.last_error = error
        return p, self.integral, d, correction

    def check_safety(self, t: float, x: float, y: float, map_width: float, map_height: float, detected: bool):
        """Latch a safety stop after 0.20 s of line loss, on a map boundary exit, or at the time limit."""
        if detected:
            self.loss_start = None
        else:
            if self.loss_start is None:
                self.loss_start = t

        if self.stop_reason == 0:
            if not (0 <= x <= map_width and 0 <= y <= map_height):
                self.stop_reason = 2  # Outside the map
            elif self.loss_start is not None and (t - self.loss_start >= 0.2 - 1e-12):
                self.stop_reason = 1  # Line lost continuously for 0.20 s
            elif t >= 100 - 1e-12:
                self.stop_reason = 4  # Safety time limit reached

        return self.stop_reason

    def compute_motor_commands(self, correction: float):
        """Convert steering correction to normalized left/right commands; output zero when stopped."""
        if self.stop_reason != 0:
            return 0.0, 0.0
        uL = float(np.clip(self.base_speed - correction, 0.0, 1.0))
        uR = float(np.clip(self.base_speed + correction, 0.0, 1.0))
        return uL, uR

