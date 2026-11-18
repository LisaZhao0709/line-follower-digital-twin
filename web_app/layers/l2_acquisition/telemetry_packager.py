"""L2: acquire pose, sensors and controller signals every 20 ms and package a timestamped telemetry frame."""
from dataclasses import asdict
import math
import numpy as np

from layers.l1_physical.track import PhysicalTrack, VehicleConfig
from layers.l1_physical.physical_car import DifferentialChassis
from layers.l1_physical.controller import OnboardController
from .sensors import SensorArray, SENSOR_WEIGHTS


class TelemetryPackager:
    """Acquire and package raw observations from the simulated physical vehicle."""
    Ts = 0.02
    km = 0.35
    wheel_base = 0.12

    def __init__(self, track: PhysicalTrack, config: VehicleConfig):
        self.track = track
        self.config = config
        self.chassis = DifferentialChassis(*track.initial)
        self.controller = OnboardController(config.Kp, config.Ki, config.Kd)
        self.x, self.y, self.theta = track.initial
        self.index = 0
        self.last_error = self.derivative = self.integral = 0.
        self.loss_start = None
        self.reason = 0
        self.visited = set()
        self.previous_s = self.previous_along = self.previous_t = None
        self.progress = 0.
        self.lap_time = None
        self.environment = self.make_environment()

    def make_environment(self):
        """Generate colored noise for lighting drift, shadows, mechanical jitter and sensor noise."""
        values = np.zeros((5001, 12))
        values[:, 0] = 1
        level = self.config.environment_level
        if level == 0:
            return values
        random = np.random.default_rng(self.config.environment_seed)
        light, shadow, jitter, noise, bias = (.04, .08, .0006, .015, .005) if level == 1 else (.12, .25, .002, .06, .015)
        alpha = np.exp(-self.Ts / np.array([2, .8, .08, .08]))
        colored = np.zeros((5001, 4))
        colored[0] = random.normal(size=4)
        innovations = random.normal(size=(5000, 4))
        for i in range(1, len(colored)):
            colored[i] = alpha * colored[i - 1] + np.sqrt(1 - alpha**2) * innovations[i - 1]
        values[:, 0] = np.clip(1 + light * colored[:, 0], .5, 1.5)
        values[:, 1] = np.minimum(shadow * np.maximum(colored[:, 1], 0), .6)
        values[:, 2:4] = jitter * colored[:, 2:4]
        values[:, 4:] = noise * random.normal(size=(5001, 8)) + bias * random.normal(size=8)
        return values

    def gate(self, t):
        """Evaluate lap progress and crossing of the start gate."""
        distance, j = self.track.tree.query([self.x, self.y])
        s = float(self.track.arc[j])
        if self.previous_s is None:
            self.start_s = s
        else:
            self.progress += (s - self.previous_s + self.track.length / 2) % self.track.length - self.track.length / 2
        if distance <= .05 + 4 * .008:
            self.visited.add(min(23, int(((s - self.start_s) % self.track.length) / self.track.length * 24)))
        angle = self.track.initial[2]
        along = (self.x - self.track.initial[0]) * math.cos(angle) + (self.y - self.track.initial[1]) * math.sin(angle)
        normal = -(self.x - self.track.initial[0]) * math.sin(angle) + (self.y - self.track.initial[1]) * math.cos(angle)
        if (self.previous_along is not None and self.previous_along < 0 <= along
                and len(self.visited) == 24 and self.progress > .95 * self.track.length and abs(normal) <= .04):
            self.lap_time = self.previous_t - self.previous_along / (along - self.previous_along) * self.Ts
        self.previous_s, self.previous_along, self.previous_t = s, along, t

    def sample_and_pack(self):
        """Sample sensors, execute control and package one raw telemetry frame."""
        c = self.config
        t = self.index * self.Ts
        light, shadow, forward, lateral = self.environment[self.index, :4]
        read_error = self.environment[self.index, 4:]

        # 1. Compute sensor positions and acquire readings.
        nominal_x, nominal_y, sx, sy = SensorArray.compute_positions(
            self.x, self.y, self.theta, forward, lateral
        )
        ideal, strengths, binary, detected, error_val = SensorArray.sample(
            self.track, nominal_x, nominal_y, sx, sy,
            light, shadow, read_error, c.dropout, t
        )
        error = error_val if detected else self.last_error

        # 2. Evaluate controller output and safety conditions.
        self.loss_start = None if detected else (t if self.loss_start is None else self.loss_start)
        self.derivative = .2 * (error - self.last_error) / self.Ts + .8 * self.derivative
        p, d = c.Kp * error, c.Kd * self.derivative

        if c.Ki == 0:
            self.integral = 0.
        elif detected:
            delta = c.Ki * error * self.Ts
            candidate = float(np.clip(self.integral + delta, -.2, .2))
            total = p + d + candidate
            if not (abs(total) > .35 and total * delta > 0):
                self.integral = candidate

        if self.reason == 0:
            if not 0 <= self.x <= self.track.width or not 0 <= self.y <= self.track.height:
                self.reason = 2
            elif self.loss_start is not None and t - self.loss_start >= .2 - 1e-12:
                self.reason = 1
            elif t >= 100 - 1e-12:
                self.reason = 4

        correction = p + self.integral + d
        uL, uR = (float(np.clip(.35 - correction, 0, 1)), float(np.clip(.35 + correction, 0, 1))) if self.reason == 0 else (0., 0.)
        vL, vR = self.km * c.motor_left_factor * uL, self.km * uR

        self.gate(t)

        # 3. Attach t_sim_s and package a complete raw observation frame.
        frame = dict(
            t_sim_s=t,
            sample_index=self.index,
            x_m=self.x,
            y_m=self.y,
            theta_rad=self.theta,
            strengths=strengths.tolist(),
            ideal_strengths=ideal.tolist(),
            sensors=binary.astype(int).tolist(),
            sensor_x=sx.tolist(),
            sensor_y=sy.tolist(),
            sensor_error=error,
            P=p,
            I=self.integral,
            D=d,
            uL=uL,
            uR=uR,
            left_speed_mps=vL,
            right_speed_mps=vR,
            stop_reason=self.reason,
            completed_lap=self.lap_time is not None,
            lap_time_s=self.lap_time,
            light_gain=float(light),
            shadow_bias=float(shadow),
            lateral_jitter_m=float(lateral),
            config=asdict(c)
        )

        finished = self.reason != 0 or self.lap_time is not None
        if not finished:
            v, omega = (vL + vR) / 2, (vR - vL) / self.wheel_base
            half = omega * self.Ts / 2
            factor = math.sin(half) / half if abs(half) > 1e-10 else 1.
            self.x += self.Ts * v * factor * math.cos(self.theta + half)
            self.y += self.Ts * v * factor * math.sin(self.theta + half)
            self.theta += omega * self.Ts
            self.index += 1

        self.last_error = error
        return frame, finished

    # Preserve the original step() interface.
    step = sample_and_pack

