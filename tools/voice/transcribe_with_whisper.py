#!/usr/bin/env python3
"""Transcribe an audio file with local Whisper and export the voice JSON shape."""

from __future__ import annotations

import argparse
import json
import math
import sys
import time
import uuid
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Run local Whisper transcription on an audio file and write the "
            "desk companion voice-result JSON format."
        )
    )
    parser.add_argument("audio", type=Path, help="Path to an audio file, such as .mp3.")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=Path("voice_result.json"),
        help="Output JSON path. Defaults to voice_result.json.",
    )
    parser.add_argument(
        "--model",
        default="base",
        help="Whisper model size/name. Try tiny, base, small, medium, or large-v3.",
    )
    parser.add_argument(
        "--language",
        default="zh",
        help="Language hint passed to Whisper. Use zh for Mandarin Chinese.",
    )
    parser.add_argument(
        "--device",
        default="cpu",
        choices=("cpu", "cuda", "auto"),
        help="Inference device. Defaults to cpu for portable closed tests.",
    )
    parser.add_argument(
        "--compute-type",
        default="int8",
        help="faster-whisper compute type. int8 is CPU friendly.",
    )
    parser.add_argument("--source", default="whisper-local")
    parser.add_argument("--case-id", default=None)
    parser.add_argument("--session-id", default=None)
    return parser.parse_args()


def load_whisper_model(model_name: str, device: str, compute_type: str) -> Any:
    try:
        from faster_whisper import WhisperModel
    except ImportError as exc:
        raise RuntimeError(
            "Unable to import faster-whisper or one of its dependencies. "
            "Install dependencies with: "
            "python -m pip install -r tools\\voice\\requirements.txt. "
            f"Original error: {exc}"
        ) from exc

    return WhisperModel(model_name, device=device, compute_type=compute_type)


def confidence_from_avg_logprob(avg_logprob: float | None) -> float | None:
    if avg_logprob is None:
        return None

    return round(max(0.0, min(1.0, math.exp(avg_logprob))), 2)


def format_transcript(text: str, language: str) -> str:
    stripped = text.strip()
    if not stripped:
        return stripped

    if language.lower().startswith("zh") and stripped[-1] not in "。！？!?":
        return f"{stripped}。"
    return stripped


def language_tag(language: str | None) -> str:
    if not language:
        return "zh-TW"
    normalized = language.lower()
    if normalized.startswith("zh"):
        return "zh-TW"
    if normalized.startswith("en"):
        return "en-US"
    return language


def alternatives_for(language: str | None) -> list[str]:
    tag = language_tag(language)
    if tag == "zh-TW":
        return ["zh-CN", "en-US"]
    if tag == "en-US":
        return ["zh-TW", "zh-CN"]
    return ["zh-TW", "en-US"]


def transcribe(args: argparse.Namespace) -> tuple[str, float | None, str]:
    model = load_whisper_model(args.model, args.device, args.compute_type)
    segments, info = model.transcribe(
        str(args.audio),
        language=args.language,
        beam_size=5,
        vad_filter=True,
    )

    segment_list = list(segments)
    transcript = "".join(segment.text for segment in segment_list).strip()
    confidences = [
        confidence_from_avg_logprob(segment.avg_logprob)
        for segment in segment_list
        if confidence_from_avg_logprob(segment.avg_logprob) is not None
    ]
    confidence = round(sum(confidences) / len(confidences), 2) if confidences else None
    detected_language = getattr(info, "language", None) or args.language
    return transcript, confidence, detected_language


def build_voice_json(
    args: argparse.Namespace,
    transcript: str,
    confidence: float | None,
    detected_language: str,
) -> dict[str, Any]:
    case_id = args.case_id or args.audio.stem
    session_id = args.session_id or f"voice-session-{uuid.uuid4().hex[:12]}"
    formatted = format_transcript(transcript, detected_language)

    return {
        "schemaVersion": 1,
        "source": args.source,
        "description": "Single voice result generated from local Whisper transcription.",
        "results": [
            {
                "caseId": case_id,
                "sessionId": session_id,
                "eventType": "final",
                "timestampMs": int(time.time() * 1000),
                "transcript": transcript,
                "formattedTranscript": formatted,
                "isFinal": True,
                "candidates": [
                    {
                        "text": transcript,
                        "confidence": confidence,
                    }
                ],
                "audio": {
                    "rmsDb": None,
                    "isSpeechDetected": bool(transcript),
                },
                "language": {
                    "tag": language_tag(detected_language),
                    "confidenceLevel": "confident" if transcript else "unknown",
                    "alternatives": alternatives_for(detected_language),
                },
                "recognitionParts": [],
                "alternatives": [],
            }
        ],
    }


def main() -> int:
    args = parse_args()
    args.audio = args.audio.expanduser().resolve()
    args.output = args.output.expanduser().resolve()

    if not args.audio.exists():
        print(f"Audio file not found: {args.audio}", file=sys.stderr)
        return 1

    try:
        transcript, confidence, detected_language = transcribe(args)
    except Exception as exc:
        print(f"Whisper transcription failed: {exc}", file=sys.stderr)
        return 1

    payload = build_voice_json(args, transcript, confidence, detected_language)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
