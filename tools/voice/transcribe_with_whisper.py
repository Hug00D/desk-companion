#!/usr/bin/env python3
"""Transcribe audio with local Whisper and export the voice JSON shape."""

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
            "Run local Whisper transcription on an audio file or folder and write the "
            "desk companion voice-result JSON format."
        )
    )
    parser.add_argument(
        "audio",
        nargs="?",
        type=Path,
        default=Path("tools/voice/input"),
        help="Path to an audio file or folder. Defaults to tools/voice/input.",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=Path("output/voice"),
        help=(
            "Output JSON file or folder. Defaults to output/voice. "
            "When audio is a folder, this must be a folder."
        ),
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


def find_audio_files(audio_path: Path) -> list[Path]:
    if audio_path.is_file():
        return [audio_path]
    if not audio_path.is_dir():
        return []

    return sorted(
        path
        for path in audio_path.iterdir()
        if path.is_file() and path.suffix.lower() == ".mp3"
    )


def transcribe(
    model: Any,
    audio_path: Path,
    language: str,
) -> tuple[str, float | None, str]:
    segments, info = model.transcribe(
        str(audio_path),
        language=language,
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
    detected_language = getattr(info, "language", None) or language
    return transcript, confidence, detected_language


def build_voice_json(
    args: argparse.Namespace,
    audio_path: Path,
    transcript: str,
    confidence: float | None,
    detected_language: str,
) -> dict[str, Any]:
    case_id = args.case_id or audio_path.stem
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
        print(f"Audio path not found: {args.audio}", file=sys.stderr)
        return 1

    audio_files = find_audio_files(args.audio)
    if not audio_files:
        print(f"No .mp3 files found in: {args.audio}", file=sys.stderr)
        return 1

    input_is_folder = args.audio.is_dir()
    if input_is_folder and args.output.suffix.lower() == ".json":
        print("When audio is a folder, --output must be a folder path.", file=sys.stderr)
        return 1

    try:
        model = load_whisper_model(args.model, args.device, args.compute_type)
    except Exception as exc:
        print(f"Whisper model load failed: {exc}", file=sys.stderr)
        return 1

    output_paths: list[Path] = []
    for audio_path in audio_files:
        try:
            transcript, confidence, detected_language = transcribe(
                model=model,
                audio_path=audio_path,
                language=args.language,
            )
        except Exception as exc:
            print(f"Whisper transcription failed for {audio_path}: {exc}", file=sys.stderr)
            return 1

        payload = build_voice_json(args, audio_path, transcript, confidence, detected_language)
        output_path = (
            args.output / f"{audio_path.stem}_result.json"
            if input_is_folder
            else args.output
        )
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        output_paths.append(output_path)
        print(f"Wrote {output_path}")

    print(f"Processed {len(output_paths)} file(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
