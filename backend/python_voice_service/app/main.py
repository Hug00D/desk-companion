from __future__ import annotations

import argparse
import hashlib
import json
import math
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


SERVICE_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = SERVICE_ROOT / "output"
VOICE_CACHE_VERSION = "windows_tts_v1"
CACHE_AUDIO_KEEP_LIMIT = 120
MIN_GENERATION_INTERVAL_SECONDS = 3.0
DEFAULT_VOICE_NAME: str | None = None
DEFAULT_VOICE_CULTURE: str | None = None
_generation_lock = threading.Lock()
_generation_in_progress = False
_last_generation_started_at = 0.0


def _json_bytes(payload: dict) -> bytes:
    return json.dumps(payload, ensure_ascii=False).encode("utf-8")


def _normalize_voice_name(value: object) -> str | None:
    if value is None:
        return None
    normalized = str(value).strip()
    return normalized or None


def _cache_audio_path(
    text: str,
    voice_name: str | None,
    voice_culture: str | None,
) -> Path:
    normalized_text = " ".join(text.strip().split())
    voice_key = voice_name or voice_culture or "auto"
    cache_input = f"{VOICE_CACHE_VERSION}\n{voice_key}\n{normalized_text}".encode(
        "utf-8"
    )
    cache_key = hashlib.sha256(cache_input).hexdigest()[:24]
    return OUTPUT_DIR / f"cached_voice_{cache_key}.wav"


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
) -> tuple[str, float]:
    duration = _generate_windows_tts_wav(
        text,
        output_path,
        voice_name,
        voice_culture,
    )
    if duration is not None:
        return "windows_tts", duration

    return "mock_wav", _generate_mock_wav(text, output_path)


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


def _cached_audio_payload(
    text: str,
    audio_path: Path,
    host: str,
) -> dict | None:
    if not audio_path.exists():
        return None

    duration = _duration_of_wav(audio_path)
    if duration is None or duration <= 0.1 or audio_path.stat().st_size < 1024:
        try:
            audio_path.unlink()
        except OSError:
            pass
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
                    "mode": "windows_tts_or_mock_wav",
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

        text = str(body.get("text", "")).strip()
        if not text:
            self._send_json(400, {"ok": False, "error": "text_required"})
            return

        voice_name = _normalize_voice_name(body.get("voiceName")) or DEFAULT_VOICE_NAME
        voice_culture = (
            _normalize_voice_name(body.get("voiceCulture")) or DEFAULT_VOICE_CULTURE
        )
        host = self.headers.get("Host", "127.0.0.1:8001")
        audio_path = _cache_audio_path(text, voice_name, voice_culture)
        cached_payload = _cached_audio_payload(text, audio_path, host)
        if cached_payload is not None:
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

        status = body.get("status")
        event_type = body.get("eventType")
        source = body.get("source", "unknown")
        timestamp = datetime.now().strftime("%H:%M:%S")
        print(
            f"[voice-service {timestamp}] source={source} "
            f"status={status} event={event_type} "
            f"voice={voice_name or voice_culture or 'auto'} text={text}",
            flush=True,
        )

        try:
            mode, duration = _generate_speech_wav(
                text,
                audio_path,
                voice_name,
                voice_culture,
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
                "voiceName": voice_name,
                "voiceCulture": voice_culture,
                "text": text,
                "audioPath": str(audio_path),
                "audioUrl": f"http://{host}/audio/{audio_path.name}",
                "durationMs": int(duration * 1000),
            },
        )

    def log_message(self, format: str, *args) -> None:
        return


def main() -> None:
    parser = argparse.ArgumentParser(description="Desk Companion local voice service")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8001)
    args = parser.parse_args()

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
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


if __name__ == "__main__":
    main()
