"""L2: eight-channel reflectance sampling with lighting, shadow, position jitter and injected occlusion."""
import math
import numpy as np

SENSOR_WEIGHTS = np.arange(3.5, -4, -1)


class SensorArray:
    """Eight-channel reflectance sensor array for line tracking."""
    sensor_front_m: float = 0.05    # Sensor array offset: 50 mm ahead of the vehicle centre
    sensor_spacing_m: float = 0.008 # Spacing between adjacent sensors: 8 mm
    weights = SENSOR_WEIGHTS        # Weight coefficients [-3.5, -2.5, ..., 2.5, 3.5]
    threshold: float = 0.5         # Binary detection threshold

    @classmethod
    def compute_positions(cls, x: float, y: float, theta: float, forward_jitter: float = 0.0, lateral_jitter: float = 0.0):
        """Calculate the eight sensor sampling locations (sx, sy) in world coordinates."""
        ct, st = math.cos(theta), math.sin(theta)
        nominal_x = x + ct * cls.sensor_front_m - st * cls.weights * cls.sensor_spacing_m
        nominal_y = y + st * cls.sensor_front_m + ct * cls.weights * cls.sensor_spacing_m
        sx = nominal_x + ct * forward_jitter - st * lateral_jitter
        sy = nominal_y + st * forward_jitter + ct * lateral_jitter
        return nominal_x, nominal_y, sx, sy

    @classmethod
    def sample(cls, track, nominal_x, nominal_y, sx, sy, light: float, shadow: float, read_error, dropout: bool, t: float):
        """Sample reflectance, add optical and electrical noise, and return intensities and binary detections."""
        ideal = track.sample_reflectance(nominal_x, nominal_y)
        actual_sampled = track.sample_reflectance(sx, sy)
        strengths = np.clip(light * actual_sampled + shadow + read_error, 0, 1)

        # Simulate sensor occlusion from 1.0 s to 1.4 s; telemetry is still delivered.
        if dropout and (1.0 - 1e-12 <= t < 1.4 - 1e-12):
            strengths[:] = 0.0

        binary = strengths >= cls.threshold
        detected = bool(binary.any())
        error = float(strengths @ cls.weights / (3.5 * max(strengths.sum(), 1e-12))) if detected else None
        return ideal, strengths, binary, detected, error

