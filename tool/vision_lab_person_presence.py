#!/usr/bin/env python3
"""Measure person-mask coverage on frames where Face and Pose both disappear.

The video frames are joined to an existing Vision Lab frame-features CSV by
presentation timestamp (PTS).  ``frame_idx`` is retained only as the native
run's row identity because MediaCodec may deterministically drop a source
sample that another decoder emits.  Reports keep the native decoder's real PTS
rather than wall-clock or UI time.

This is an experiment tool only.  It records a raw segmentation signal and
does not convert it to sleep, reading, or away states.
"""

from __future__ import annotations

import argparse
import csv
import math
import statistics
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import cv2
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision


@dataclass(frozen=True)
class SampleRequest:
    frame_idx: int
    timestamp_ms: int


@dataclass(frozen=True)
class GroundTruthInterval:
    state: str
    start_ms: int
    end_ms: int


def _parse_args() -> argparse.Namespace:
    default_model = Path(__file__).resolve().parent / "models" / "selfie_segmenter.tflite"
    parser = argparse.ArgumentParser(
        description=(
            "Sample MediaPipe Selfie Segmentation only when both Face and "
            "Pose are absent in an existing frame_features CSV."
        )
    )
    parser.add_argument("--video", required=True, type=Path)
    parser.add_argument("--features", required=True, type=Path)
    parser.add_argument(
        "--model",
        type=Path,
        default=default_model,
        help=f"Selfie Segmenter model (default: {default_model})",
    )
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--ground-truth", type=Path)
    parser.add_argument("--interval-ms", type=int, default=200)
    return parser.parse_args()


def _is_true(value: str | None) -> bool:
    return (value or "").strip().lower() == "true"


def _load_sample_requests(path: Path, interval_ms: int) -> list[SampleRequest]:
    if interval_ms <= 0:
        raise ValueError("--interval-ms must be greater than zero")

    requests: list[SampleRequest] = []
    last_sample_ms: int | None = None
    previous_frame_idx = -1
    previous_timestamp_ms = -1
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        required = {"frame_idx", "timestamp_ms", "face_detected", "pose_detected"}
        missing = required.difference(reader.fieldnames or [])
        if missing:
            raise ValueError(f"Feature CSV is missing columns: {sorted(missing)}")

        for row in reader:
            frame_idx = int(row["frame_idx"])
            timestamp_ms = int(row["timestamp_ms"])
            if frame_idx <= previous_frame_idx:
                raise ValueError("frame_idx must be strictly increasing")
            if timestamp_ms < previous_timestamp_ms:
                raise ValueError("timestamp_ms must be non-decreasing")
            previous_frame_idx = frame_idx
            previous_timestamp_ms = timestamp_ms

            landmarks_present = _is_true(row["face_detected"]) or _is_true(
                row["pose_detected"]
            )
            if landmarks_present:
                continue
            if last_sample_ms is None or timestamp_ms - last_sample_ms >= interval_ms:
                requests.append(SampleRequest(frame_idx, timestamp_ms))
                last_sample_ms = timestamp_ms

    return requests


def _load_ground_truth(path: Path | None) -> list[GroundTruthInterval]:
    if path is None:
        return []
    intervals: list[GroundTruthInterval] = []
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        required = {"state", "start_ms", "end_ms"}
        missing = required.difference(reader.fieldnames or [])
        if missing:
            raise ValueError(f"Ground-truth CSV is missing columns: {sorted(missing)}")
        for row in reader:
            intervals.append(
                GroundTruthInterval(
                    state=row["state"].strip(),
                    start_ms=int(row["start_ms"]),
                    end_ms=int(row["end_ms"]),
                )
            )
    return intervals


def _state_at(timestamp_ms: int, intervals: Iterable[GroundTruthInterval]) -> str:
    for interval in intervals:
        if interval.start_ms <= timestamp_ms < interval.end_ms:
            return interval.state
    return ""


def _percentile(values: list[float], percentile: float) -> float:
    ordered = sorted(values)
    if not ordered:
        return math.nan
    position = (len(ordered) - 1) * percentile
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    fraction = position - lower
    return ordered[lower] * (1.0 - fraction) + ordered[upper] * fraction


def _print_summary(rows: list[dict[str, object]]) -> None:
    by_state: dict[str, list[float]] = defaultdict(list)
    for row in rows:
        by_state[str(row["ground_truth_state"]) or "(unlabeled)"].append(
            float(row["person_mask_area_ratio"])
        )

    print("\nPerson-mask area by ground-truth state")
    print("state,count,min,p10,median,p90,max")
    for state, values in sorted(by_state.items()):
        print(
            f"{state},{len(values)},{min(values):.4f},"
            f"{_percentile(values, 0.10):.4f},{statistics.median(values):.4f},"
            f"{_percentile(values, 0.90):.4f},{max(values):.4f}"
        )


def main() -> int:
    args = _parse_args()
    for input_path in (args.video, args.features, args.model):
        if not input_path.is_file():
            raise FileNotFoundError(input_path)
    if args.ground_truth is not None and not args.ground_truth.is_file():
        raise FileNotFoundError(args.ground_truth)

    requests = _load_sample_requests(args.features, args.interval_ms)
    if not requests:
        raise ValueError("No frames have both face_detected=false and pose_detected=false")
    ground_truth = _load_ground_truth(args.ground_truth)

    options = vision.ImageSegmenterOptions(
        base_options=python.BaseOptions(model_asset_path=str(args.model)),
        running_mode=vision.RunningMode.IMAGE,
        output_category_mask=False,
        output_confidence_masks=True,
    )
    capture = cv2.VideoCapture(str(args.video))
    if not capture.isOpened():
        raise RuntimeError(f"Could not open video: {args.video}")

    rows: list[dict[str, object]] = []
    request_cursor = 0
    decoded_frame_idx = 0
    try:
        with vision.ImageSegmenter.create_from_options(options) as segmenter:
            while request_cursor < len(requests):
                ok, bgr = capture.read()
                if not ok:
                    break
                video_timestamp_ms = int(
                    math.floor(capture.get(cv2.CAP_PROP_POS_MSEC) + 1e-6)
                )
                request = requests[request_cursor]
                pts_delta_ms = video_timestamp_ms - request.timestamp_ms
                if pts_delta_ms < -1:
                    decoded_frame_idx += 1
                    continue
                if pts_delta_ms > 1:
                    raise RuntimeError(
                        "Could not match native PTS "
                        f"{request.timestamp_ms} ms; video advanced to "
                        f"{video_timestamp_ms} ms at source frame {decoded_frame_idx}"
                    )

                if abs(pts_delta_ms) <= 1:
                    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
                    image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
                    result = segmenter.segment(image)
                    if not result.confidence_masks:
                        raise RuntimeError("Selfie Segmenter returned no confidence mask")
                    mask = result.confidence_masks[0].numpy_view()
                    foreground_y, foreground_x = (mask >= 0.5).nonzero()
                    person_pixels = int(foreground_x.size)
                    pixel_count = int(mask.shape[0] * mask.shape[1])
                    area_ratio = person_pixels / pixel_count if pixel_count else 0.0
                    centroid_x = (
                        float(foreground_x.mean() / max(mask.shape[1] - 1, 1))
                        if person_pixels
                        else math.nan
                    )
                    centroid_y = (
                        float(foreground_y.mean() / max(mask.shape[0] - 1, 1))
                        if person_pixels
                        else math.nan
                    )
                    rows.append(
                        {
                            "frame_idx": request.frame_idx,
                            "timestamp_ms": request.timestamp_ms,
                            "source_video_frame_idx": decoded_frame_idx,
                            "source_video_timestamp_ms": video_timestamp_ms,
                            "pts_delta_ms": pts_delta_ms,
                            "ground_truth_state": _state_at(
                                request.timestamp_ms, ground_truth
                            ),
                            "person_mask_mean_confidence": float(mask.mean()),
                            "person_mask_area_ratio": area_ratio,
                            "person_mask_centroid_x": centroid_x,
                            "person_mask_centroid_y": centroid_y,
                        }
                    )
                    request_cursor += 1
                decoded_frame_idx += 1
    finally:
        capture.release()

    if len(rows) != len(requests):
        raise RuntimeError(
            f"Video ended after frame {decoded_frame_idx - 1}; "
            f"expected {len(requests)} samples, produced {len(rows)}"
        )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
                "frame_idx",
                "timestamp_ms",
                "source_video_frame_idx",
                "source_video_timestamp_ms",
                "pts_delta_ms",
                "ground_truth_state",
                "person_mask_mean_confidence",
                "person_mask_area_ratio",
                "person_mask_centroid_x",
                "person_mask_centroid_y",
            ],
        )
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote {len(rows)} samples to {args.output}")
    _print_summary(rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
