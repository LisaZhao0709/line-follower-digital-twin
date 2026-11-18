"""L1: track geometry, pixel scale, binary mask, reflectance and reference path."""
from dataclasses import dataclass
import math
from pathlib import Path

from scipy.io import loadmat
from scipy.ndimage import map_coordinates
from scipy.spatial import cKDTree

DATA_DIR = Path(__file__).resolve().parents[3] / 'full_project' / 'data'


@dataclass
class VehicleConfig:
    """Physical vehicle and environment configuration parameters."""
    Kp: float = .45
    Ki: float = .015
    Kd: float = .03
    environment_level: int = 1
    environment_seed: int = 7
    motor_left_factor: float = 1.
    dropout: bool = False
    speed: float = 4.

    @classmethod
    def parse(cls, values):
        if not isinstance(values, dict) or set(values) - set(cls.__dataclass_fields__):
            raise ValueError('Invalid configuration fields.')
        config = cls(**values)
        limits = {
            'Kp': (0, 20), 'Ki': (0, 2), 'Kd': (0, .5),
            'environment_level': (0, 2), 'environment_seed': (0, 2**32 - 1),
            'motor_left_factor': (.5, 1.5), 'speed': (1, 8)
        }
        for name, (lo, hi) in limits.items():
            value = getattr(config, name)
            if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or not lo <= value <= hi:
                raise ValueError(f'{name} must be between {lo} and {hi}.')
        for name in ('environment_level', 'environment_seed'):
            if getattr(config, name) != int(getattr(config, name)):
                raise ValueError(f'{name} must be an integer.')
            setattr(config, name, int(getattr(config, name)))
        if not isinstance(config.dropout, bool):
            raise ValueError('dropout must be a Boolean.')
        return config


class PhysicalTrack:
    """Track environment: metric dimensions, pixel scale, reflectance map and geometric reference line."""
    def __init__(self, data_path=None):
        data_path = Path(data_path) if data_path else (DATA_DIR / 'track_data.mat')
        data = loadmat(data_path, squeeze_me=True)
        self.reflectance = data['trackReflectance']
        self.mask = data['trackMask']
        self.width = float(data['map_width_m'])
        self.height = float(data['map_height_m'])
        self.scale = float(data['meters_per_pixel_x'])
        self.initial = [float(data[k]) for k in ('x0', 'y0', 'theta0')]
        self.reference = data['referenceXY'][:-1]
        self.arc = data['referenceArc'].ravel()
        self.length = float(self.arc[-1])
        self.tree = cKDTree(self.reference)

    def sample_reflectance(self, x, y):
        """Sample reflectance at world coordinates (x, y); black line = 1 and background = 0."""
        row = self.reflectance.shape[0] - 1 - y / self.scale
        col = x / self.scale
        return map_coordinates(self.reflectance, [row, col], order=1, mode='constant', cval=0)

