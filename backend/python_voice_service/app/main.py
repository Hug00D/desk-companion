from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import subprocess
import struct
import sys
import tempfile
import threading
import time
import wave
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

from gpt_sovits_engine import GptSoVitsEngine


SERVICE_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = SERVICE_ROOT / "output"
VOICE_CACHE_VERSION = "gpt_sovits_staff_a_v2_slow"
CACHE_VERSION_FILE = OUTPUT_DIR / ".voice_cache_version"
CACHE_AUDIO_KEEP_LIMIT = 120
MIN_GENERATION_INTERVAL_SECONDS = 3.0
DEFAULT_VOICE_NAME: str | None = None
DEFAULT_VOICE_CULTURE: str | None = None
GPT_SOVITS_ENABLED = True
GPT_SOVITS_ENGINE = GptSoVitsEngine()
_generation_lock = threading.Lock()
_generation_in_progress = False
_last_generation_started_at = 0.0
_catalog_lock = threading.Lock()
_last_catalog_text: dict[str, str] = {}

REMINDER_CATALOG: dict[str, tuple[str, ...]] = {
    "attention": (
        "眼睛有點累了，眨眨眼，讓視線休息一下。",
        "看螢幕有一會兒了，稍微放鬆一下眼睛吧。",
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


def _json_bytes(payload: dict) -> bytes:
    return json.dumps(payload, ensure_ascii=False).encode("utf-8")


def _normalize_voice_name(value: object) -> str | None:
    if value is None:
        return None
    normalized = str(value).strip()
    return normalized or None


def _cache_audio_path(
    text: str,
    engine_key: str,
) -> Path:
    normalized_text = " ".join(text.strip().split())
    cache_input = f"{VOICE_CACHE_VERSION}\n{engine_key}\n{normalized_text}".encode(
        "utf-8"
    )
    cache_key = hashlib.sha256(cache_input).hexdigest()[:24]
    return OUTPUT_DIR / f"cached_voice_{cache_key}.wav"


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


def _is_valid_cached_audio(text: str, output_path: Path) -> bool:
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
        if _is_valid_cached_audio(text, output_path):
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
            print(f"[voice-service] GPT-SoVITS fallback: {error}", flush=True)
            try:
                output_path.unlink()
            except OSError:
                pass

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


def _cleanup_old_audio_files(keep: int = 30) -> None:
    wav_files = sorted(
        OUTPUT_DIR.glob("voice_*.wav"),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    for old_file in wav_files[keep:]:
        try:
            old_file.unlink()
        except OSError:
            pass


def _cleanup_cached_audio_files(keep: int = CACHE_AUDIO_KEEP_LIMIT) -> None:
    cache_files = sorted(
        OUTPUT_DIR.glob("cached_voice_*.wav"),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    for old_file in cache_files[keep:]:
        try:
            old_file.unlink()
        except OSError:
            pass


def _prepare_cache_storage() -> None:
    try:
        previous_version = CACHE_VERSION_FILE.read_text(encoding="utf-8").strip()
    except OSError:
        previous_version = ""
    if previous_version == VOICE_CACHE_VERSION:
        return

    removed = 0
    for cache_file in OUTPUT_DIR.glob("cached_voice_*.wav"):
        try:
            cache_file.unlink()
            removed += 1
        except OSError:
            pass
    CACHE_VERSION_FILE.write_text(VOICE_CACHE_VERSION, encoding="utf-8")
    print(
        f"[voice-service] cache version updated; removed={removed}",
        flush=True,
    )


def _prewarm_reminder_cache() -> None:
    if not GPT_SOVITS_ENABLED or not GPT_SOVITS_ENGINE.is_ready():
        return

    total = sum(len(messages) for messages in REMINDER_CATALOG.values())
    generated = 0
    reused = 0
    print(f"[voice-service] checking {total} Staff A reminders", flush=True)
    for status, messages in REMINDER_CATALOG.items():
        style = REMINDER_STYLE.get(status, "normal")
        engine_key = f"gpt_sovits_staff_a:{style}"
        for text in messages:
            audio_path = _cache_audio_path(text, engine_key)
            if _is_valid_cached_audio(text, audio_path):
                reused += 1
                continue
            if audio_path.exists():
                audio_path.unlink(missing_ok=True)
            try:
                _synthesize_gpt_sovits_validated(text, audio_path, style)
            except (OSError, RuntimeError) as error:
                print(
                    f"[voice-service] prewarm failed status={status}: {error}",
                    flush=True,
                )
                continue
            generated += 1
            print(
                f"[voice-service] generated {generated}/{total} status={status}",
                flush=True,
            )
    _cleanup_cached_audio_files()
    print(
        f"[voice-service] reminder cache ready generated={generated} reused={reused}",
        flush=True,
    )


def _cached_audio_payload(
    text: str,
    audio_path: Path,
    host: str,
) -> dict | None:
    if not audio_path.exists():
        return None

    if not _is_valid_cached_audio(text, audio_path):
        try:
            audio_path.unlink()
        except OSError:
            pass
        return None

    duration = _duration_of_wav(audio_path)
    if duration is None:
        return None

    try:
        audio_path.touch()
    except OSError:
        pass

    return {
        "ok": True,
        "mode": "cached_wav",
        "cached": True,
        "text": text,
        "audioPath": str(audio_path),
        "audioUrl": f"http://{host}/audio/{audio_path.name}",
        "durationMs": int(duration * 1000),
    }


class VoiceRequestHandler(BaseHTTPRequestHandler):
    server_version = "DeskCompanionVoiceService/0.1"

    def _send_json(self, status: int, payload: dict) -> None:
        data = _json_bytes(payload)
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(data)

    def _send_audio_file(self, file_path: Path) -> None:
        if not file_path.exists() or file_path.parent != OUTPUT_DIR:
            self._send_json(404, {"ok": False, "error": "audio_not_found"})
            return

        data = file_path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "audio/wav")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(data)

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/health":
            self._send_json(
                200,
                {
                    "ok": True,
                    "service": "desk_companion_voice_service",
                    "mode": "gpt_sovits_with_windows_fallback",
                    "gptSovits": GPT_SOVITS_ENGINE.status(),
                    "defaultVoiceName": DEFAULT_VOICE_NAME,
                    "defaultVoiceCulture": DEFAULT_VOICE_CULTURE,
                },
            )
            return

        if path == "/voices":
            self._send_json(
                200,
                {
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
                },
            )
            return

        if path.startswith("/audio/"):
            filename = Path(unquote(path.removeprefix("/audio/"))).name
            self._send_audio_file(OUTPUT_DIR / filename)
            return

        self._send_json(404, {"ok": False, "error": "not_found"})

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        if path != "/tts":
            self._send_json(404, {"ok": False, "error": "not_found"})
            return

        content_length = int(self.headers.get("Content-Length", "0"))
        raw_body = self.rfile.read(content_length)
        try:
            body = json.loads(raw_body.decode("utf-8")) if raw_body else {}
        except json.JSONDecodeError:
            self._send_json(400, {"ok": False, "error": "invalid_json"})
            return

        requested_text = str(body.get("text", "")).strip()
        if not requested_text:
            self._send_json(400, {"ok": False, "error": "text_required"})
            return

        status = str(body.get("status") or "") or None
        event_type = body.get("eventType")
        source = str(body.get("source", "unknown"))
        text = _select_reminder_text(requested_text, status, source)
        style = REMINDER_STYLE.get(status or "", "normal")
        voice_name = _normalize_voice_name(body.get("voiceName")) or DEFAULT_VOICE_NAME
        voice_culture = (
            _normalize_voice_name(body.get("voiceCulture")) or DEFAULT_VOICE_CULTURE
        )
        host = self.headers.get("Host", "127.0.0.1:8001")
        if GPT_SOVITS_ENABLED and GPT_SOVITS_ENGINE.is_ready():
            engine_key = f"gpt_sovits_staff_a:{style}"
        else:
            engine_key = f"windows_tts:{voice_name or voice_culture or 'auto'}"
        audio_path = _cache_audio_path(text, engine_key)
        cached_payload = _cached_audio_payload(text, audio_path, host)
        if cached_payload is not None:
            cached_payload["requestedText"] = requested_text
            cached_payload["style"] = style
            cached_payload["voiceName"] = voice_name
            cached_payload["voiceCulture"] = voice_culture
            self._send_json(200, cached_payload)
            return

        global _generation_in_progress, _last_generation_started_at
        now_monotonic = time.monotonic()
        with _generation_lock:
            seconds_since_last_generation = (
                now_monotonic - _last_generation_started_at
            )
            if (
                _generation_in_progress
                or seconds_since_last_generation < MIN_GENERATION_INTERVAL_SECONDS
            ):
                reason = (
                    "generation_already_in_progress"
                    if _generation_in_progress
                    else "generation_debounced"
                )
                self._send_json(
                    202,
                    {
                        "ok": True,
                        "mode": "skipped_debounce",
                        "reason": reason,
                    },
                )
                return
            _generation_in_progress = True
            _last_generation_started_at = now_monotonic

        timestamp = datetime.now().strftime("%H:%M:%S")
        print(
            f"[voice-service {timestamp}] source={source} "
            f"status={status} event={event_type} "
            f"voice={'staff_a' if GPT_SOVITS_ENGINE.is_ready() else voice_name or voice_culture or 'auto'} "
            f"style={style} text={text}",
            flush=True,
        )

        try:
            mode, duration, served_audio_path = _generate_speech_wav(
                text,
                audio_path,
                voice_name,
                voice_culture,
                style,
            )
            _cleanup_old_audio_files()
            _cleanup_cached_audio_files()
        finally:
            with _generation_lock:
                _generation_in_progress = False

        self._send_json(
            200,
            {
                "ok": True,
                "mode": mode,
                "cached": False,
                "requestedText": requested_text,
                "style": style,
                "voiceName": voice_name,
                "voiceCulture": voice_culture,
                "text": text,
                "audioPath": str(served_audio_path),
                "audioUrl": f"http://{host}/audio/{served_audio_path.name}",
                "durationMs": int(duration * 1000),
            },
        )

    def log_message(self, format: str, *args) -> None:
        return


def main() -> None:
    global DEFAULT_VOICE_NAME, DEFAULT_VOICE_CULTURE, GPT_SOVITS_ENABLED

    parser = argparse.ArgumentParser(description="Desk Companion local voice service")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8001)
    parser.add_argument("--voice-name", default=None)
    parser.add_argument("--voice-culture", default=None)
    parser.add_argument("--disable-gpt-sovits", action="store_true")
    parser.add_argument("--skip-prewarm", action="store_true")
    args = parser.parse_args()

    DEFAULT_VOICE_NAME = _normalize_voice_name(args.voice_name)
    DEFAULT_VOICE_CULTURE = _normalize_voice_name(args.voice_culture)
    GPT_SOVITS_ENABLED = not args.disable_gpt_sovits
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    _prepare_cache_storage()
    if GPT_SOVITS_ENABLED:
        if GPT_SOVITS_ENGINE.start():
            print("[voice-service] GPT-SoVITS Staff A is ready", flush=True)
            if not args.skip_prewarm:
                threading.Thread(
                    target=_prewarm_reminder_cache,
                    name="voice-prewarm",
                    daemon=True,
                ).start()
        else:
            print(
                f"[voice-service] GPT-SoVITS unavailable: {GPT_SOVITS_ENGINE.last_error}",
                flush=True,
            )

    server = ThreadingHTTPServer((args.host, args.port), VoiceRequestHandler)
    print(
        f"[voice-service] listening on http://{args.host}:{args.port} "
        f"(output: {OUTPUT_DIR})",
        flush=True,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[voice-service] shutting down", flush=True)
    finally:
        server.server_close()
        GPT_SOVITS_ENGINE.stop()


if __name__ == "__main__":
    main()
