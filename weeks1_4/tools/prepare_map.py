"""Extract numerical track data from the supplied diagram; no image toolbox needed."""
from pathlib import Path
import json

import numpy as np
from PIL import Image
from scipy import ndimage
from scipy.io import savemat
from skimage.measure import find_contours


ROOT = Path(__file__).resolve().parents[1]
ATTACHMENT = Path(r"C:\Users\Xiaol\AppData\Local\Temp\codex-clipboard-a9d81006-c729-4171-a190-d887126159d7.webp")
SOURCE = ROOT / 'data' / 'track_source.png'


def main():
    data = ROOT / "data"
    data.mkdir(parents=True, exist_ok=True)
    image = Image.open(SOURCE if SOURCE.exists() else ATTACHMENT).convert("RGB")
    image.save(data / "track_source.png")
    rgb = np.asarray(image, dtype=float)
    luminance = rgb @ np.array([0.2989, 0.5870, 0.1140])
    labels, count = ndimage.label(luminance < 128, np.ones((3, 3)))
    edge_ids = set(np.concatenate((labels[0], labels[-1], labels[:, 0], labels[:, -1])))
    candidates = [i for i in range(1, count + 1) if i not in edge_ids]
    assert candidates, "No interior track component found"
    track_id = max(candidates, key=lambda i: np.count_nonzero(labels == i))
    mask = labels == track_id
    # A known horizontal segment, selected from the supplied diagram.
    widths = mask[60:90, 110:210].sum(axis=0)
    stroke_px = float(np.median(widths[widths > 0]))
    assert stroke_px > 0
    line_width = 0.02
    scale = line_width / stroke_px
    h, w = mask.shape
    # Preserve antialiasing only near the retained track; outer frame is zero.
    near_track = ndimage.binary_dilation(mask, iterations=1)
    reflectance = np.where(near_track, (255 - luminance) / 255, 0)
    reflectance = np.clip(reflectance, 0, 1)
    # Inner boundary serves ONLY as an offline lap/progress reference.
    contours = find_contours(mask.astype(float), 0.5)
    assert len(contours) == 2, "The retained line must enclose one region"
    boundary = min(contours, key=len)[:-1]
    bottom_rows = np.flatnonzero(mask[:, 120])
    start_row = float(np.median(bottom_rows[bottom_rows > h * 0.8]))
    start_px = np.array([start_row, 120.0])
    idx = int(np.argmin(np.sum((boundary - start_px) ** 2, axis=1)))
    boundary = np.roll(boundary, -idx, axis=0)
    if boundary[5, 1] < boundary[0, 1]:
        boundary = np.concatenate((boundary[:1], boundary[:0:-1]), axis=0)
    reference = np.column_stack((boundary[:, 1] * scale, (h - 1 - boundary[:, 0]) * scale))
    reference = np.vstack((reference, reference[0]))
    arc = np.concatenate(([0.0], np.cumsum(np.linalg.norm(np.diff(reference, axis=0), axis=1))))
    metadata = {
        "source": SOURCE.name,
        "line_width_m": line_width,
        "measured_binary_stroke_px": stroke_px,
        "meters_per_pixel": scale,
        "map_width_m": (w - 1) * scale,
        "map_height_m": (h - 1) * scale,
        "scale_method": "2 cm / median thresholded horizontal stroke width; diagram estimate, not field measurement",
        "retained_component_count": 1,
        "border_removed": True,
        "track_pixels": int(mask.sum()),
        "reference_boundary_length_m": float(arc[-1]),
        "note": "Lap reference is the inner edge, not ground truth centerline; never fed to controller.",
    }
    Image.fromarray(np.where(mask, 0, 255).astype(np.uint8)).save(data / "track_mask.png")
    savemat(data / "track_data.mat", {
        "trackMask": mask,
        "trackReflectance": reflectance,
        "map_width_m": metadata["map_width_m"],
        "map_height_m": metadata["map_height_m"],
        "meters_per_pixel_x": scale,
        "meters_per_pixel_y": scale,
        "line_width_m": line_width,
        "stroke_width_px": stroke_px,
        "referenceXY": reference,
        "referenceArc": arc,
        "x0": 120 * scale,
        "y0": (h - 1 - start_row) * scale,
        "theta0": 0.0,
    }, do_compression=True)
    (data / "map_metadata.json").write_text(json.dumps(metadata, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(metadata, ensure_ascii=False))


if __name__ == "__main__":
    main()
