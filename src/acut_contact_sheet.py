from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

import cv2
import numpy as np


Box = tuple[int, int, int, int]


@dataclass(frozen=True)
class CropSpec:
    name: str
    box_xyxy: Box | None
    source: str


@dataclass(frozen=True)
class TileSpec:
    name: str
    image_rgb: np.ndarray
    source: str
    box_xyxy: Box | None = None


def generate_contact_sheet_for_candidate(
    candidate: dict[str, Any],
    output_dir: str | Path,
    *,
    jpeg_quality: int = 85,
    max_sheet_long_side: int = 1600,
) -> dict[str, Any]:
    image_path = _first_present(candidate, ("image_path", "path", "file_path"))
    candidate_id = _first_present(candidate, ("candidate_id", "id"))
    rank = _first_present(candidate, ("rank", "primary_rank"))

    if not image_path:
        raise ValueError("missing image path field: image_path/path/file_path")

    source_path = Path(str(image_path)).expanduser()
    if not source_path.exists():
        raise FileNotFoundError(str(source_path))

    image_rgb, exif_orientation = load_image_rgb(source_path)
    height, width = image_rgb.shape[:2]
    candidate_id = str(candidate_id or source_path.stem)
    safe_id = _safe_name(candidate_id)

    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    metadata_available: list[str] = []
    metadata_missing: list[str] = []

    tiles: list[TileSpec] = []
    resize_sizes: dict[str, list[int]] = {}

    global_view = resize_long_side(image_rgb, 1024)
    small_global = resize_long_side(image_rgb, 384)
    tiles.append(TileSpec("global_1024", global_view, "global_resize"))
    tiles.append(TileSpec("global_384", small_global, "global_resize"))
    resize_sizes["global_1024"] = [int(global_view.shape[1]), int(global_view.shape[0])]
    resize_sizes["global_384"] = [int(small_global.shape[1]), int(small_global.shape[0])]

    crop_specs = _resolve_crop_specs(candidate, image_rgb, metadata_available, metadata_missing)
    for spec in crop_specs:
        if spec.box_xyxy is None:
            continue
        crop = crop_image(image_rgb, spec.box_xyxy)
        tiles.append(TileSpec(spec.name, resize_long_side(crop, 512), spec.source, spec.box_xyxy))

    sheet = build_contact_sheet(tiles)
    sheet = resize_long_side(sheet, max_sheet_long_side)

    contact_sheet_path = output_path / f"{safe_id}_contact_sheet.jpg"
    metadata_path = output_path / f"{safe_id}_contact_sheet.json"
    save_jpeg_rgb(contact_sheet_path, sheet, jpeg_quality)

    metadata = {
        "candidate_id": candidate_id,
        "source_image_path": str(source_path),
        "contact_sheet_path": str(contact_sheet_path),
        "rank": _json_safe(rank),
        "selection_state": _json_safe(candidate.get("selection_state")),
        "crop_names": [tile.name for tile in tiles],
        "crop_boxes_xyxy": {
            tile.name: list(tile.box_xyxy) for tile in tiles if tile.box_xyxy is not None
        },
        "crop_source": {tile.name: tile.source for tile in tiles},
        "resize_sizes": {
            **resize_sizes,
            **{tile.name: [int(tile.image_rgb.shape[1]), int(tile.image_rgb.shape[0])] for tile in tiles if tile.box_xyxy is not None},
        },
        "final_sheet_size": [int(sheet.shape[1]), int(sheet.shape[0])],
        "jpeg_quality": int(jpeg_quality),
        "exif_orientation_applied": exif_orientation,
        "metadata_available": sorted(set(metadata_available)),
        "metadata_missing": sorted(set(metadata_missing)),
    }
    metadata_path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return metadata


def load_image_rgb(path: str | Path) -> tuple[np.ndarray, int | None]:
    data = Path(path).read_bytes()
    flags = cv2.IMREAD_COLOR
    if hasattr(cv2, "IMREAD_IGNORE_ORIENTATION"):
        flags = flags | cv2.IMREAD_IGNORE_ORIENTATION
    bgr = cv2.imdecode(np.frombuffer(data, dtype=np.uint8), flags)
    if bgr is None:
        raise ValueError(f"cannot decode image: {path}")
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
    orientation = _read_jpeg_exif_orientation(data)
    if orientation:
        rgb = _apply_exif_orientation(rgb, orientation)
    return rgb, orientation


def resize_long_side(image_rgb: np.ndarray, long_side: int) -> np.ndarray:
    height, width = image_rgb.shape[:2]
    current = max(width, height)
    if current <= 0 or current == long_side:
        return image_rgb.copy()
    scale = long_side / current
    new_width = max(1, int(round(width * scale)))
    new_height = max(1, int(round(height * scale)))
    return cv2.resize(image_rgb, (new_width, new_height), interpolation=cv2.INTER_AREA)


def crop_image(image_rgb: np.ndarray, box: Box) -> np.ndarray:
    x1, y1, x2, y2 = clamp_box(box, image_rgb.shape[1], image_rgb.shape[0])
    return image_rgb[y1:y2, x1:x2].copy()


def save_jpeg_rgb(path: str | Path, image_rgb: np.ndarray, quality: int) -> None:
    bgr = cv2.cvtColor(image_rgb, cv2.COLOR_RGB2BGR)
    ok = cv2.imwrite(str(path), bgr, [int(cv2.IMWRITE_JPEG_QUALITY), int(quality)])
    if not ok:
        raise ValueError(f"failed to write JPEG: {path}")


def build_contact_sheet(tiles: list[TileSpec]) -> np.ndarray:
    if not tiles:
        raise ValueError("at least one tile is required")

    tile_w = 512
    tile_h = 384
    label_h = 34
    pad = 16
    cols = 2 if len(tiles) <= 4 else 3
    rows = math.ceil(len(tiles) / cols)
    sheet_w = cols * tile_w + (cols + 1) * pad
    sheet_h = rows * (tile_h + label_h) + (rows + 1) * pad
    sheet = np.full((sheet_h, sheet_w, 3), 245, dtype=np.uint8)

    for index, tile in enumerate(tiles):
        row = index // cols
        col = index % cols
        x = pad + col * (tile_w + pad)
        y = pad + row * (tile_h + label_h + pad)
        canvas = _fit_into_canvas(tile.image_rgb, tile_w, tile_h)
        sheet[y : y + tile_h, x : x + tile_w] = canvas
        cv2.rectangle(sheet, (x, y), (x + tile_w - 1, y + tile_h - 1), (210, 210, 210), 1)
        label = f"{tile.name} | {tile.source}"
        cv2.putText(
            sheet,
            label[:62],
            (x, y + tile_h + 23),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            (32, 32, 32),
            1,
            cv2.LINE_AA,
        )
    return sheet


def clamp_box(box: Iterable[float | int], width: int, height: int) -> Box:
    x1, y1, x2, y2 = [float(v) for v in box]
    if x2 < x1:
        x1, x2 = x2, x1
    if y2 < y1:
        y1, y2 = y2, y1
    x1 = int(max(0, min(width - 1, round(x1))))
    y1 = int(max(0, min(height - 1, round(y1))))
    x2 = int(max(x1 + 1, min(width, round(x2))))
    y2 = int(max(y1 + 1, min(height, round(y2))))
    return x1, y1, x2, y2


def expand_box(box: Box, width: int, height: int, scale: float) -> Box:
    x1, y1, x2, y2 = box
    cx = (x1 + x2) / 2.0
    cy = (y1 + y2) / 2.0
    bw = max(1.0, (x2 - x1) * scale)
    bh = max(1.0, (y2 - y1) * scale)
    return clamp_box((cx - bw / 2, cy - bh / 2, cx + bw / 2, cy + bh / 2), width, height)


def center_crop_box(width: int, height: int, fraction: float = 0.58) -> Box:
    side_w = max(1, int(round(width * fraction)))
    side_h = max(1, int(round(height * fraction)))
    x1 = (width - side_w) // 2
    y1 = (height - side_h) // 2
    return clamp_box((x1, y1, x1 + side_w, y1 + side_h), width, height)


def sharpness_crop_box(image_rgb: np.ndarray, grid: int = 4) -> Box:
    height, width = image_rgb.shape[:2]
    gray = cv2.cvtColor(image_rgb, cv2.COLOR_RGB2GRAY)
    best_score = -1.0
    best_box = center_crop_box(width, height)

    for gy in range(grid):
        for gx in range(grid):
            x1 = int(round(gx * width / grid))
            y1 = int(round(gy * height / grid))
            x2 = int(round((gx + 1) * width / grid))
            y2 = int(round((gy + 1) * height / grid))
            tile = gray[y1:y2, x1:x2]
            if tile.size == 0:
                continue
            score = float(cv2.Laplacian(tile, cv2.CV_64F).var())
            center_bias = 1.0 - 0.08 * (abs(gx + 0.5 - grid / 2) + abs(gy + 0.5 - grid / 2))
            score *= max(0.6, center_bias)
            if score > best_score:
                best_score = score
                best_box = clamp_box((x1, y1, x2, y2), width, height)

    return expand_box(best_box, width, height, 1.35)


def _resolve_crop_specs(
    candidate: dict[str, Any],
    image_rgb: np.ndarray,
    metadata_available: list[str],
    metadata_missing: list[str],
) -> list[CropSpec]:
    specs: list[CropSpec] = []
    height, width = image_rgb.shape[:2]

    subject = _find_box(
        candidate,
        width,
        height,
        direct_keys=("subject_box", "subject_bbox", "subject_bounding_box", "object_box", "object_bbox", "main_subject_box"),
        list_keys=("detections", "objects", "yolo_detections", "yolo_results"),
    )
    if subject:
        metadata_available.append("subject_box")
        specs.append(CropSpec("subject_crop", expand_box(subject, width, height, 1.25), "metadata_subject_box"))
    else:
        metadata_missing.append("subject_box")

    face = _find_box(
        candidate,
        width,
        height,
        direct_keys=("face_box", "face_bbox", "face_bounding_box", "main_face_box", "closed_face_box"),
        list_keys=("faces", "face_boxes", "closedFaceRects", "closed_face_rects"),
    )
    if face:
        metadata_available.append("face_box")
        specs.append(CropSpec("face_crop", expand_box(face, width, height, 1.4), "metadata_face_box"))
    else:
        metadata_missing.append("face_box")

    salient = _find_box(
        candidate,
        width,
        height,
        direct_keys=("salient_box", "saliency_box", "salient_bbox", "saliency_bbox"),
        list_keys=("saliency_regions", "salient_regions"),
    )
    if salient:
        metadata_available.append("saliency_box")
        specs.append(CropSpec("salient_crop", expand_box(salient, width, height, 1.2), "metadata_saliency_box"))
    else:
        metadata_missing.append("saliency_box")
        specs.append(CropSpec("center_crop", center_crop_box(width, height), "fallback_center"))

    specs.append(CropSpec("sharpness_crop", sharpness_crop_box(image_rgb), "fallback_sharpness"))

    composition = _find_box(
        candidate,
        width,
        height,
        direct_keys=("composition_roi", "composition_box", "rule_of_thirds_roi", "thirds_roi", "composition_bbox", "roi"),
        list_keys=("composition_regions", "composition_rois"),
    )
    if composition:
        metadata_available.append("composition_roi")
        specs.append(CropSpec("composition_roi_crop", expand_box(composition, width, height, 1.15), "metadata_composition_roi"))
    else:
        metadata_missing.append("composition_roi")

    return specs


def _find_box(
    data: dict[str, Any],
    width: int,
    height: int,
    *,
    direct_keys: tuple[str, ...],
    list_keys: tuple[str, ...],
) -> Box | None:
    for key in direct_keys:
        value = _deep_get(data, key)
        box = _coerce_box(value, width, height)
        if box:
            return box

    best: tuple[float, Box] | None = None
    for key in list_keys:
        raw = _deep_get(data, key)
        values = raw if isinstance(raw, list) else []
        for item in values:
            box = _coerce_box(item, width, height)
            if not box and isinstance(item, dict):
                for nested in ("box", "bbox", "boundingBox", "bounding_box", "normalizedBox", "rect"):
                    box = _coerce_box(item.get(nested), width, height)
                    if box:
                        break
            if box:
                confidence = _number_from_mapping(item, ("confidence", "score", "probability")) if isinstance(item, dict) else 1.0
                area = (box[2] - box[0]) * (box[3] - box[1])
                score = float(confidence or 1.0) * area
                if best is None or score > best[0]:
                    best = (score, box)
    return best[1] if best else None


def _coerce_box(value: Any, width: int, height: int) -> Box | None:
    if value is None:
        return None
    coords: tuple[float, float, float, float] | None = None
    if isinstance(value, dict):
        if all(k in value for k in ("left", "top", "right", "bottom")):
            coords = (float(value["left"]), float(value["top"]), float(value["right"]), float(value["bottom"]))
        elif all(k in value for k in ("x1", "y1", "x2", "y2")):
            coords = (float(value["x1"]), float(value["y1"]), float(value["x2"]), float(value["y2"]))
        elif all(k in value for k in ("x", "y", "w", "h")):
            x, y, w, h = float(value["x"]), float(value["y"]), float(value["w"]), float(value["h"])
            coords = (x, y, x + w, y + h)
        elif all(k in value for k in ("x", "y", "width", "height")):
            x, y, w, h = float(value["x"]), float(value["y"]), float(value["width"]), float(value["height"])
            coords = (x, y, x + w, y + h)
    elif isinstance(value, (list, tuple)) and len(value) >= 4:
        coords = (float(value[0]), float(value[1]), float(value[2]), float(value[3]))

    if coords is None:
        return None

    if max(coords) <= 1.5 and min(coords) >= -0.05:
        coords = (coords[0] * width, coords[1] * height, coords[2] * width, coords[3] * height)
    box = clamp_box(coords, width, height)
    if box[2] - box[0] < 2 or box[3] - box[1] < 2:
        return None
    return box


def _fit_into_canvas(image_rgb: np.ndarray, width: int, height: int) -> np.ndarray:
    resized = resize_long_side(image_rgb, max(width, height))
    rh, rw = resized.shape[:2]
    scale = min(width / rw, height / rh)
    resized = cv2.resize(resized, (max(1, int(rw * scale)), max(1, int(rh * scale))), interpolation=cv2.INTER_AREA)
    rh, rw = resized.shape[:2]
    canvas = np.full((height, width, 3), 250, dtype=np.uint8)
    x = (width - rw) // 2
    y = (height - rh) // 2
    canvas[y : y + rh, x : x + rw] = resized
    return canvas


def _read_jpeg_exif_orientation(data: bytes) -> int | None:
    if not data.startswith(b"\xff\xd8"):
        return None
    offset = 2
    while offset + 4 <= len(data):
        if data[offset] != 0xFF:
            return None
        marker = data[offset + 1]
        offset += 2
        if marker == 0xDA:
            return None
        length = int.from_bytes(data[offset : offset + 2], "big")
        segment = data[offset + 2 : offset + length]
        offset += length
        if marker == 0xE1 and segment.startswith(b"Exif\x00\x00"):
            return _parse_tiff_orientation(segment[6:])
    return None


def _parse_tiff_orientation(tiff: bytes) -> int | None:
    if len(tiff) < 8:
        return None
    endian = "little" if tiff[:2] == b"II" else "big" if tiff[:2] == b"MM" else None
    if endian is None:
        return None
    if int.from_bytes(tiff[2:4], endian) != 42:
        return None
    ifd_offset = int.from_bytes(tiff[4:8], endian)
    if ifd_offset + 2 > len(tiff):
        return None
    count = int.from_bytes(tiff[ifd_offset : ifd_offset + 2], endian)
    entry_offset = ifd_offset + 2
    for index in range(count):
        start = entry_offset + index * 12
        if start + 12 > len(tiff):
            return None
        tag = int.from_bytes(tiff[start : start + 2], endian)
        if tag == 0x0112:
            value = int.from_bytes(tiff[start + 8 : start + 10], endian)
            return value if 1 <= value <= 8 else None
    return None


def _apply_exif_orientation(image_rgb: np.ndarray, orientation: int) -> np.ndarray:
    if orientation == 2:
        return cv2.flip(image_rgb, 1)
    if orientation == 3:
        return cv2.rotate(image_rgb, cv2.ROTATE_180)
    if orientation == 4:
        return cv2.flip(image_rgb, 0)
    if orientation == 5:
        return cv2.rotate(cv2.flip(image_rgb, 1), cv2.ROTATE_90_COUNTERCLOCKWISE)
    if orientation == 6:
        return cv2.rotate(image_rgb, cv2.ROTATE_90_CLOCKWISE)
    if orientation == 7:
        return cv2.rotate(cv2.flip(image_rgb, 1), cv2.ROTATE_90_CLOCKWISE)
    if orientation == 8:
        return cv2.rotate(image_rgb, cv2.ROTATE_90_COUNTERCLOCKWISE)
    return image_rgb


def _first_present(data: dict[str, Any], keys: tuple[str, ...]) -> Any:
    for key in keys:
        if key in data and data[key] not in (None, ""):
            return data[key]
    return None


def _deep_get(data: Any, target_key: str) -> Any:
    if isinstance(data, dict):
        if target_key in data:
            return data[target_key]
        for value in data.values():
            found = _deep_get(value, target_key)
            if found is not None:
                return found
    elif isinstance(data, list):
        for value in data:
            found = _deep_get(value, target_key)
            if found is not None:
                return found
    return None


def _number_from_mapping(data: dict[str, Any], keys: tuple[str, ...]) -> float | None:
    for key in keys:
        value = data.get(key)
        if isinstance(value, (int, float)):
            return float(value)
    return None


def _safe_name(value: str) -> str:
    safe = "".join(ch if ch.isalnum() or ch in ("-", "_", ".") else "_" for ch in value)
    return safe[:96] or "candidate"


def _json_safe(value: Any) -> Any:
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    return str(value)
