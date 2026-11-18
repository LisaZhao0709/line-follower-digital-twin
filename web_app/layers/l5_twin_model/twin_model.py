"""L5: nominal command replay, prediction/correction and measured residuals.

Only accepted observations enter here. The model never reads source fault settings.
"""
from datetime import datetime, timezone
import math


NOMINAL_GAIN = .35
WHEEL_BASE_M = .12
SAMPLE_PERIOD_S = .02


def predict_pose(x, y, theta, left, right, dt):
    """Exact differential-drive arc for wheel speeds held over dt seconds."""
    half = (right - left) / WHEEL_BASE_M * dt / 2
    factor = math.sin(half) / half if abs(half) > 1e-10 else 1.
    distance = dt * (left + right) / 2 * factor
    return [x + distance * math.cos(theta + half),
            y + distance * math.sin(theta + half), theta + 2 * half]


class TwinModel:
    """Keep a corrected twin and an independent nominal command-replay reference."""

    # Flat fields are also added to received samples for L6, charts and CSV export.
    SAMPLE_OUTPUTS = (
        'expected_left_mps', 'expected_right_mps', 'residual_left_mps',
        'residual_right_mps', 'residual_mps', 'prior_x_m', 'prior_y_m',
        'prior_theta_rad', 'innovation_m', 'innovation_theta_rad',
        'prediction_valid', 'prediction_dt_s', 'nominal_x_m', 'nominal_y_m',
        'nominal_theta_rad', 'nominal_drift_m', 'nominal_elapsed_s')

    def __init__(self):
        self.state = None
        self.updates = 0

    def reset(self):
        # Lifetime counter survives runs; all pose/reference state is reinitialized.
        self.state = None

    def update(self, observation):
        """Predict from the PREVIOUS command, then correct with the new pose.

        A repeated sample is a transport heartbeat, not a new model step. Missing
        commands across a gap cannot be reconstructed: reanchor both references
        and mark that interval invalid instead of inventing a long prediction.
        """
        previous = self.state
        if previous and observation['sample_index'] == previous['sample_index']:
            observation.update({key: previous[key] for key in self.SAMPLE_OUTPUTS})
            return previous

        expected_left = NOMINAL_GAIN * observation['uL']
        expected_right = NOMINAL_GAIN * observation['uR']
        left_residual = observation['left_speed_mps'] - expected_left
        right_residual = observation['right_speed_mps'] - expected_right
        measured = [observation['x_m'], observation['y_m'], observation['theta_rad']]
        dt = observation['t_sim_s'] - previous['t_sim_s'] if previous else 0.
        if dt < 0:
            raise ValueError('Source time moved backwards within the same run.')
        continuous = bool(previous and not observation.get('gap_before', False)
                          and observation['sample_index'] == previous['sample_index'] + 1
                          and math.isclose(dt, SAMPLE_PERIOD_S, abs_tol=1e-8))
        if continuous:
            # u[k-1] drives [t[k-1], t[k]); u[k] drives the next interval.
            prior = predict_pose(previous['x_m'], previous['y_m'], previous['theta_rad'],
                                 previous['expected_left_mps'], previous['expected_right_mps'], dt)
            nominal = predict_pose(previous['nominal_x_m'], previous['nominal_y_m'],
                                   previous['nominal_theta_rad'], previous['expected_left_mps'],
                                   previous['expected_right_mps'], dt)
            elapsed = previous['nominal_elapsed_s'] + dt
        else:
            prior, nominal, elapsed = measured[:], measured[:], 0.

        innovation = math.hypot(prior[0] - measured[0], prior[1] - measured[1])
        angle_error = math.atan2(math.sin(measured[2] - prior[2]), math.cos(measured[2] - prior[2]))
        self.updates += 1
        self.state = dict(
            x_m=measured[0], y_m=measured[1], theta_rad=measured[2],
            t_sim_s=observation['t_sim_s'], sample_index=observation['sample_index'],
            expected_left_mps=expected_left, expected_right_mps=expected_right,
            residual_left_mps=left_residual, residual_right_mps=right_residual,
            residual_mps=max(abs(left_residual), abs(right_residual)),
            prior_xy=prior[:2], prior_x_m=prior[0], prior_y_m=prior[1], prior_theta_rad=prior[2],
            innovation_m=innovation, innovation_theta_rad=angle_error,
            prediction_valid=continuous, prediction_dt_s=dt,
            phase='tracking' if continuous else ('resynced' if previous else 'initialized'),
            nominal_x_m=nominal[0], nominal_y_m=nominal[1], nominal_theta_rad=nominal[2],
            nominal_drift_m=math.hypot(nominal[0] - measured[0], nominal[1] - measured[1]),
            nominal_elapsed_s=elapsed,
            # Conditional future: assume the current command remains unchanged.
            forecast=[dict(dt_s=i / 10, x_m=pose[0], y_m=pose[1], theta_rad=pose[2])
                      for i in range(11)
                      for pose in [predict_pose(*measured, expected_left, expected_right, i / 10)]],
            updated_utc=datetime.now(timezone.utc).isoformat(), updates=self.updates)
        observation.update({key: self.state[key] for key in self.SAMPLE_OUTPUTS})
        return self.state
