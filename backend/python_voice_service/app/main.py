from __future__ import annotations

import argparse
import json
import math
import os
import random
import subprocess
import struct
import sys
import tempfile
import threading
import time
import wave
from datetime import datetime
from pathlib import Path

import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from starlette.background import BackgroundTask

from gpt_sovits_engine import GptSoVitsEngine


SERVICE_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = SERVICE_ROOT / "output"
TRANSIENT_AUDIO_MAX_AGE_SECONDS = 10 * 60
AUDIO_DELETE_GRACE_SECONDS = 30.0
GENERATION_QUEUE_WAIT_SECONDS = float(
    os.getenv("VOICE_GENERATION_QUEUE_WAIT_SECONDS", "15")
)
DEFAULT_VOICE_NAME: str | None = None
DEFAULT_VOICE_CULTURE: str | None = None
GPT_SOVITS_ENABLED = True
GPT_SOVITS_ENGINE = GptSoVitsEngine()
_generation_slot = threading.Lock()
_generation_state_lock = threading.Lock()
_generation_in_progress = False
_generation_waiting_requests = 0
_catalog_lock = threading.Lock()
_last_catalog_text: dict[str, str] = {}

app = FastAPI(title="Desk Companion Voice Service")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

REMINDER_CATALOG: dict[str, tuple[str, ...]] = {
    "attention": (
        "眼睛有點累了，眨眨眼，讓視線休息一下。",
        "眨眼變得比較頻繁，讓眼睛休息一下吧。",
        "先把視線移開幾秒，眼睛會舒服一點。",
    ),
    "fatigue": (
        "你看起來有點累，先休息一下再繼續。",
        "別勉強自己，喝口水，稍微喘口氣吧。",
        "專注很久了，現在休息一下也沒關係。",
    ),
    "distracted": (
        "注意力跑掉了，先回來專注一下。",
        "注意力回來囉，接著把眼前這件事完成。",
        "好像分心了，重新找回剛才的節奏吧。",
    ),
    "drowsy": (
        "快睡著了喔，坐直一點，醒醒精神。",
        "先起來動一動吧，你需要清醒一下。",
        "看起來很想睡，休息幾分鐘再繼續吧。",
    ),
    "postureDown": (
        "你趴下了，先坐起來再繼續。",
        "先把身體坐正，別讓自己趴著睡著了。",
        "起來伸展一下吧，換個姿勢會舒服一點。",
    ),
}

REMINDER_STYLE = {
    "attention": "normal",
    "fatigue": "low",
    "distracted": "normal",
    "drowsy": "high",
    "postureDown": "high",
}


def _configure_utf8_stdio() -> None:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="backslashreplace")
        except (AttributeError, ValueError):
            pass


def _safe_log(message: str) -> None:
    try:
        print(message, flush=True)
    except UnicodeEncodeError:
        encoding = getattr(sys.stdout, "encoding", None) or "ascii"
        safe_message = message.encode(
            encoding,
            errors="backslashreplace",
        ).decode(encoding, errors="replace")
        print(safe_message, flush=True)


def _generation_status() -> dict:
    with _generation_state_lock:
        return {
            "inProgress": _generation_in_progress,
            "waitingRequests": _generation_waiting_requests,
            "queueWaitSeconds": GENERATION_QUEUE_WAIT_SECONDS,
        }


def _normalize_voice_name(value: object) -> str | None:
    if value is None:
        return None
    normalized = str(value).strip()
    return normalized or None


def _transient_audio_path(prefix: str = "voice") -> Path:
    timestamp = datetime.now().strftime("%Y%m%dT%H%M%S_%f")
    return OUTPUT_DIR / f"{prefix}_{timestamp}.wav"


def _select_reminder_text(
    requested_text: str,
    status: str | None,
    source: str,
) -> str:
    options = REMINDER_CATALOG.get(status or "")
    if source != "vision" or not options:
        return requested_text

    with _catalog_lock:
        previous = _last_catalog_text.get(status or "")
        candidates = [text for text in options if text != previous] or list(options)
        selected = random.choice(candidates)
        _last_catalog_text[status or ""] = selected
        return selected


def _duration_of_wav(output_path: Path) -> float | None:
    try:
        with wave.open(str(output_path), "rb") as wav_file:
            frame_count = wav_file.getnframes()
            frame_rate = wav_file.getframerate()
            if frame_rate <= 0:
                return None
            return frame_count / frame_rate
    except wave.Error:
        return None


def _is_valid_audio(text: str, output_path: Path) -> bool:
    if not output_path.exists() or output_path.stat().st_size < 1024:
        return False

    duration = _duration_of_wav(output_path)
    if duration is None:
        return False

    spoken_character_count = sum(character.isalnum() for character in text)
    minimum_duration = max(0.8, min(2.2, spoken_character_count * 0.12))
    return duration >= minimum_duration


def _synthesize_gpt_sovits_validated(
    text: str,
    output_path: Path,
    style: str,
    attempts: int = 2,
) -> float:
    for attempt in range(1, attempts + 1):
        duration = GPT_SOVITS_ENGINE.synthesize(text, output_path, style=style)
        if _is_valid_audio(text, output_path):
            return duration

        output_path.unlink(missing_ok=True)
        print(
            f"[voice-service] incomplete GPT-SoVITS audio; retry={attempt}/{attempts}",
            flush=True,
        )
    raise RuntimeError("GPT-SoVITS repeatedly returned incomplete audio")


def _generate_mock_wav(text: str, output_path: Path) -> float:
    """Generate a tiny placeholder wav so the full request path is testable."""
    sample_rate = 24000
    duration_seconds = max(0.5, min(2.4, 0.08 * max(len(text), 4)))
    total_samples = int(sample_rate * duration_seconds)
    base_frequency = 420 + (len(text) % 11) * 18
    amplitude = 0.20

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(output_path), "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)

        frames = bytearray()
        for sample_index in range(total_samples):
            t = sample_index / sample_rate
            envelope = min(1.0, sample_index / (sample_rate * 0.04))
            envelope *= min(1.0, (total_samples - sample_index) / (sample_rate * 0.08))
            wave_value = math.sin(2 * math.pi * base_frequency * t)
            wave_value += 0.35 * math.sin(2 * math.pi * (base_frequency * 1.5) * t)
            pcm = int(max(-1.0, min(1.0, wave_value * amplitude * envelope)) * 32767)
            frames.extend(struct.pack("<h", pcm))

        wav_file.writeframes(bytes(frames))

    return duration_seconds


def _generate_windows_tts_wav(
    text: str,
    output_path: Path,
    voice_name: str | None,
    voice_culture: str | None,
) -> float | None:
    if sys.platform != "win32":
        return None

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "w",
        encoding="utf-8",
        suffix=".txt",
        delete=False,
    ) as text_file:
        text_file.write(text)
        text_path = Path(text_file.name)

    script = """
param(
    [string]$OutputPath,
    [string]$TextPath,
    [string]$VoiceName,
    [string]$VoiceCulture
)
Add-Type -AssemblyName System.Speech
$text = Get-Content -LiteralPath $TextPath -Raw -Encoding UTF8
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer

if (-not [string]::IsNullOrWhiteSpace($VoiceName)) {
    try {
        $synth.SelectVoice($VoiceName)
    } catch {
        # Fall back to culture / automatic selection below.
    }
}

if ($synth.Voice.Name -ne $VoiceName) {
    if (-not [string]::IsNullOrWhiteSpace($VoiceCulture)) {
        $voice = $synth.GetInstalledVoices() |
            Where-Object { $_.VoiceInfo.Culture.Name -eq $VoiceCulture } |
            Select-Object -First 1
        if ($voice -ne $null) {
            $synth.SelectVoice($voice.VoiceInfo.Name)
        }
    } elseif ($text -match '[\u3400-\u9FFF]') {
        $voice = $synth.GetInstalledVoices() |
            Where-Object { $_.VoiceInfo.Culture.Name -eq 'zh-TW' } |
            Select-Object -First 1
        if ($voice -ne $null) {
            $synth.SelectVoice($voice.VoiceInfo.Name)
        }
    }
}

if ($synth.Voice.Name -ne $VoiceName -and $text -match '[\u3400-\u9FFF]') {
    $voice = $synth.GetInstalledVoices() |
        Where-Object { $_.VoiceInfo.Culture.Name -eq 'zh-TW' } |
        Select-Object -First 1
    if ($voice -ne $null) {
        $synth.SelectVoice($voice.VoiceInfo.Name)
    }
}
$synth.Rate = 0
$synth.Volume = 100
$synth.SetOutputToWaveFile($OutputPath)
$synth.Speak($text)
$synth.Dispose()
""".strip()
    with tempfile.NamedTemporaryFile(
        "w",
        encoding="utf-8-sig",
        suffix=".ps1",
        delete=False,
    ) as script_file:
        script_file.write(script)
        script_path = Path(script_file.name)

    try:
        result = subprocess.run(
            [
                "powershell",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(script_path),
                "-OutputPath",
                str(output_path),
                "-TextPath",
                str(text_path),
                "-VoiceName",
                voice_name or "",
                "-VoiceCulture",
                voice_culture or "",
            ],
            capture_output=True,
            text=True,
            timeout=12,
            check=False,
        )
        if result.returncode != 0 or not output_path.exists():
            return None
        duration = _duration_of_wav(output_path)
        if duration is None or duration <= 0.1 or output_path.stat().st_size < 1024:
            try:
                output_path.unlink()
            except OSError:
                pass
            return None
        return duration
    except (OSError, subprocess.SubprocessError):
        return None
    finally:
        try:
            text_path.unlink()
        except OSError:
            pass
        try:
            script_path.unlink()
        except OSError:
            pass


def _generate_speech_wav(
    text: str,
    output_path: Path,
    voice_name: str | None,
    voice_culture: str | None,
    style: str,
    *,
    allow_system_fallback: bool = True,
) -> tuple[str, float, Path]:
    tried_gpt_sovits = GPT_SOVITS_ENABLED and GPT_SOVITS_ENGINE.is_ready()
    if tried_gpt_sovits:
        try:
            duration = _synthesize_gpt_sovits_validated(
                text,
                output_path,
                style,
            )
            return "gpt_sovits", duration, output_path
        except (OSError, RuntimeError) as error:
            _safe_log(f"[voice-service] GPT-SoVITS failed: {error}")
            try:
                output_path.unlink()
            except OSError:
                pass
            if not allow_system_fallback:
                raise RuntimeError("GPT-SoVITS generation failed") from error

    if not allow_system_fallback:
        raise RuntimeError("GPT-SoVITS is not ready")

    fallback_path = _transient_audio_path()
    duration = _generate_windows_tts_wav(
        text,
        fallback_path,
        voice_name,
        voice_culture,
    )
    if duration is not None:
        return "windows_tts", duration, fallback_path

    try:
        fallback_path.unlink()
    except OSError:
        pass
    mock_path = _transient_audio_path(prefix="voice_mock")
    return "mock_wav", _generate_mock_wav(text, mock_path), mock_path


def _list_windows_tts_voices() -> list[dict]:
    if sys.platform != "win32":
        return []

    script = """
Add-Type -AssemblyName System.Speech
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$voices = $synth.GetInstalledVoices() | ForEach-Object {
    [PSCustomObject]@{
        name = $_.VoiceInfo.Name
        culture = $_.VoiceInfo.Culture.Name
        gender = $_.VoiceInfo.Gender.ToString()
        age = $_.VoiceInfo.Age.ToString()
        enabled = $_.Enabled
    }
}
$synth.Dispose()
$voices | ConvertTo-Json -Depth 4
""".strip()
    try:
        result = subprocess.run(
            [
                "powershell",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-Command",
                script,
            ],
            capture_output=True,
            text=True,
            timeout=8,
            check=False,
        )
        if result.returncode != 0 or not result.stdout.strip():
            return []
        voices = json.loads(result.stdout)
        if isinstance(voices, dict):
            return [voices]
        if isinstance(voices, list):
            return [voice for voice in voices if isinstance(voice, dict)]
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError):
        return []
    return []


def _cleanup_stale_audio_files(
    max_age_seconds: float = TRANSIENT_AUDIO_MAX_AGE_SECONDS,
) -> int:
    cutoff = time.time() - max_age_seconds
    candidates = set(OUTPUT_DIR.glob("voice_*.wav"))
    candidates.update(OUTPUT_DIR.glob("cached_voice_*.wav"))
    removed = 0
    for audio_file in candidates:
        try:
            if max_age_seconds > 0 and audio_file.stat().st_mtime > cutoff:
                continue
            audio_file.unlink()
            removed += 1
        except OSError:
            pass
    return removed


def _delete_audio_file(file_path: Path) -> None:
    try:
        file_path.unlink()
    except OSError:
        pass


def _schedule_audio_delete(file_path: Path) -> None:
    if AUDIO_DELETE_GRACE_SECONDS <= 0:
        _delete_audio_file(file_path)
        return
    timer = threading.Timer(
        AUDIO_DELETE_GRACE_SECONDS,
        _delete_audio_file,
        args=(file_path,),
    )
    timer.daemon = True
    timer.start()


def _is_generated_audio_file(file_path: Path) -> bool:
    return (
        file_path.suffix.lower() == ".wav"
        and (
            file_path.name.startswith("voice_")
            or file_path.name.startswith("cached_voice_")
        )
        and file_path.parent == OUTPUT_DIR
        and file_path.exists()
    )


def _audio_response_finished(file_path: Path, content_length: int) -> None:
    _safe_log(
        f"[voice-service] audio served pid={os.getpid()} "
        f"file={file_path.name} bytes={content_length}/{content_length}"
    )
    _schedule_audio_delete(file_path)


def _generate_tts_payload(body: dict) -> tuple[int, dict]:
    requested_text = str(body.get("text", "")).strip()
    if not requested_text:
        return 400, {"ok": False, "error": "text_required"}

    request_id = str(body.get("requestId", "")).strip()[:128]
    if not request_id:
        request_id = f"voice-{time.time_ns()}-{threading.get_ident()}"

    status = str(body.get("status") or "") or None
    event_type = body.get("eventType")
    source = str(body.get("source", "unknown"))
    text = _select_reminder_text(requested_text, status, source)
    style = REMINDER_STYLE.get(status or "", "normal")
    voice_name = _normalize_voice_name(body.get("voiceName")) or DEFAULT_VOICE_NAME
    voice_culture = (
        _normalize_voice_name(body.get("voiceCulture")) or DEFAULT_VOICE_CULTURE
    )
    _cleanup_stale_audio_files()
    safe_request_id = "".join(
        character if character.isascii() and character.isalnum() else "_"
        for character in request_id
    )[-48:]
    audio_path = _transient_audio_path(prefix=f"voice_{safe_request_id}")

    global _generation_in_progress, _generation_waiting_requests
    with _generation_state_lock:
        _generation_waiting_requests += 1
    try:
        generation_slot_acquired = _generation_slot.acquire(
            timeout=GENERATION_QUEUE_WAIT_SECONDS
        )
    finally:
        with _generation_state_lock:
            _generation_waiting_requests -= 1

    if not generation_slot_acquired:
        return 503, {
            "ok": False,
            "requestId": request_id,
            "error": "generation_queue_timeout",
            "message": "Voice generation stayed busy for too long",
        }

    with _generation_state_lock:
        _generation_in_progress = True

    generation_error: Exception | None = None
    try:
        timestamp = datetime.now().strftime("%H:%M:%S")
        _safe_log(
            f"[voice-service {timestamp}] request={request_id} source={source} "
            f"status={status} event={event_type} "
            f"voice={'staff_a' if GPT_SOVITS_ENGINE.is_ready() else voice_name or voice_culture or 'auto'} "
            f"style={style} text={text}"
        )
        mode, duration, served_audio_path = _generate_speech_wav(
            text,
            audio_path,
            voice_name,
            voice_culture,
            style,
            allow_system_fallback=source != "assistant",
        )
    except Exception as error:
        generation_error = error
    finally:
        with _generation_state_lock:
            _generation_in_progress = False
        _generation_slot.release()

    if generation_error is not None:
        _delete_audio_file(audio_path)
        return 503, {
            "ok": False,
            "requestId": request_id,
            "error": "gpt_sovits_generation_failed",
            "message": str(generation_error),
        }

    return 200, {
        "ok": True,
        "requestId": request_id,
        "mode": mode,
        "cached": False,
        "deleteAfterDownload": True,
        "requestedText": requested_text,
        "style": style,
        "voiceName": voice_name,
        "voiceCulture": voice_culture,
        "text": text,
        "audioPath": str(served_audio_path),
        "audioUrl": f"/audio/{served_audio_path.name}",
        "durationMs": int(duration * 1000),
    }


@app.get("/health")
def health() -> dict:
    return {
        "ok": True,
        "service": "desk_companion_voice_service",
        "processId": os.getpid(),
        "mode": "gpt_sovits_with_windows_fallback",
        "audioRetention": "delete_after_download",
        "httpServer": "uvicorn",
        "gptSovits": GPT_SOVITS_ENGINE.status(),
        "generation": _generation_status(),
        "defaultVoiceName": DEFAULT_VOICE_NAME,
        "defaultVoiceCulture": DEFAULT_VOICE_CULTURE,
    }


@app.get("/voices")
def voices() -> dict:
    return {
        "ok": True,
        "voices": _list_windows_tts_voices(),
        "gptSovitsVoices": [
            {
                "name": "Staff A",
                "id": "staff_a_v2_pro_plus",
                "styles": sorted(set(REMINDER_STYLE.values())),
                "ready": GPT_SOVITS_ENGINE.is_ready(),
            }
        ],
        "defaultVoiceName": DEFAULT_VOICE_NAME,
        "defaultVoiceCulture": DEFAULT_VOICE_CULTURE,
    }


@app.get("/audio/{filename}")
def audio(filename: str) -> FileResponse:
    file_path = OUTPUT_DIR / Path(filename).name
    if not _is_generated_audio_file(file_path):
        raise HTTPException(status_code=404, detail="audio_not_found")
    content_length = file_path.stat().st_size
    return FileResponse(
        file_path,
        media_type="audio/wav",
        headers={
            "Cache-Control": "no-store",
            "X-Audio-Length": str(content_length),
        },
        background=BackgroundTask(
            _audio_response_finished,
            file_path,
            content_length,
        ),
    )


@app.post("/tts")
def tts(body: dict) -> JSONResponse:
    status_code, payload = _generate_tts_payload(body)
    return JSONResponse(status_code=status_code, content=payload)


def main() -> None:
    global DEFAULT_VOICE_NAME, DEFAULT_VOICE_CULTURE, GPT_SOVITS_ENABLED

    _configure_utf8_stdio()
    parser = argparse.ArgumentParser(description="Desk Companion local voice service")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8001)
    parser.add_argument("--voice-name", default=None)
    parser.add_argument("--voice-culture", default=None)
    parser.add_argument("--disable-gpt-sovits", action="store_true")
    args = parser.parse_args()

    DEFAULT_VOICE_NAME = _normalize_voice_name(args.voice_name)
    DEFAULT_VOICE_CULTURE = _normalize_voice_name(args.voice_culture)
    GPT_SOVITS_ENABLED = not args.disable_gpt_sovits
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    removed = _cleanup_stale_audio_files(max_age_seconds=0)
    try:
        (OUTPUT_DIR / ".voice_cache_version").unlink()
    except OSError:
        pass
    if removed:
        print(
            f"[voice-service] removed {removed} stale generated audio files",
            flush=True,
        )
    if GPT_SOVITS_ENABLED:
        if GPT_SOVITS_ENGINE.start():
            print("[voice-service] GPT-SoVITS Staff A is ready", flush=True)
        else:
            print(
                f"[voice-service] GPT-SoVITS unavailable: {GPT_SOVITS_ENGINE.last_error}",
                flush=True,
            )

    print(
        f"[voice-service] listening on http://{args.host}:{args.port} "
        f"(output: {OUTPUT_DIR})",
        flush=True,
    )
    try:
        uvicorn.run(
            app,
            host=args.host,
            port=args.port,
            log_level="warning",
            access_log=False,
        )
    finally:
        print("\n[voice-service] shutting down", flush=True)
        GPT_SOVITS_ENGINE.stop()
        _cleanup_stale_audio_files(max_age_seconds=0)


if __name__ == "__main__":
    main()
