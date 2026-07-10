from __future__ import annotations

import json
import os
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path


SERVICE_ROOT = Path(__file__).resolve().parents[1]
RUNTIME_ROOT = SERVICE_ROOT / "runtime" / "GPT-SoVITS"
RUNTIME_PYTHON = SERVICE_ROOT / "runtime" / "miniconda" / "python.exe"
OPEN_JTALK_DICT_ROOT = SERVICE_ROOT / "runtime" / "open_jtalk_dic_utf_8-1.11"
CONFIG_PATH = SERVICE_ROOT / "gpt_sovits_config.yaml"
MODEL_ROOT = SERVICE_ROOT / "models" / "staff_a" / "Staff_A_GPT-SoVITS_v2ProPlus"
API_BASE_URL = "http://127.0.0.1:9880"

REFERENCE_STYLES = {
    "normal": {
        "audio": "rec257_normal.opus",
        "text": "こんなことを言いながら、気の短いおじいさんは下駄を突っかけて、そそくさと出て行ってしまった。",
    },
    "low": {
        "audio": "emo039_low01.opus",
        "text": "アフィ狙いの釣り記事ですね。英語関係のコミュのあちこちにマルチポストしています。",
    },
    "whisper": {
        "audio": "emo052_whisper.opus",
        "text": "事業を継続しながら、事業が依拠している不動産を、切り売りしていくことなど非現実的なのだ。",
    },
    "high": {
        "audio": "emo069_high.opus",
        "text": "ギリシャのフットボールの試合では、一方のチームの選手は、相手チームの陣地のラインの向こう側にボールを持ち込もうとしたのです。",
    },
}


class GptSoVitsEngine:
    def __init__(self) -> None:
        self._process: subprocess.Popen[bytes] | None = None
        self._request_lock = threading.Lock()
        self.last_error: str | None = None

    @property
    def configured(self) -> bool:
        required_paths = (
            RUNTIME_PYTHON,
            RUNTIME_ROOT / "api_v2.py",
            OPEN_JTALK_DICT_ROOT / "sys.dic",
            CONFIG_PATH,
            MODEL_ROOT / "Staff_A+hlw-e15.ckpt",
            MODEL_ROOT / "Staff_A+hlw_e8_s392.pth",
            MODEL_ROOT / "rec257_normal.opus",
        )
        return all(path.exists() for path in required_paths)

    def is_ready(self) -> bool:
        try:
            with urllib.request.urlopen(f"{API_BASE_URL}/docs", timeout=2) as response:
                return response.status == 200
        except (OSError, urllib.error.URLError):
            return False

    def start(self, timeout_seconds: float = 120.0) -> bool:
        if self.is_ready():
            self.last_error = None
            return True
        if not self.configured:
            self.last_error = "GPT-SoVITS runtime or Staff A model is incomplete"
            return False

        self._patch_windows_torchaudio_compatibility()
        env = os.environ.copy()
        conda_root = RUNTIME_PYTHON.parent
        env["PATH"] = os.pathsep.join(
            (
                str(conda_root),
                str(conda_root / "Scripts"),
                str(conda_root / "Library" / "bin"),
                env.get("PATH", ""),
            )
        )
        env["PYTHONUTF8"] = "1"
        env["PYTHONIOENCODING"] = "utf-8"
        env["OPEN_JTALK_DICT_DIR"] = str(OPEN_JTALK_DICT_ROOT)

        stdout_path = RUNTIME_ROOT / "gpt_sovits_stdout.log"
        stderr_path = RUNTIME_ROOT / "gpt_sovits_stderr.log"
        creationflags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
        with stdout_path.open("ab") as stdout_file, stderr_path.open("ab") as stderr_file:
            self._process = subprocess.Popen(
                (
                    str(RUNTIME_PYTHON),
                    "api_v2.py",
                    "-c",
                    str(CONFIG_PATH),
                    "-a",
                    "127.0.0.1",
                    "-p",
                    "9880",
                ),
                cwd=RUNTIME_ROOT,
                env=env,
                stdout=stdout_file,
                stderr=stderr_file,
                creationflags=creationflags,
            )

        deadline = time.monotonic() + timeout_seconds
        while time.monotonic() < deadline:
            if self.is_ready():
                self.last_error = None
                return True
            if self._process.poll() is not None:
                break
            time.sleep(1)

        self.last_error = self._startup_error(stderr_path)
        self.stop()
        return False

    def stop(self) -> None:
        process = self._process
        self._process = None
        if process is None or process.poll() is not None:
            return
        process.terminate()
        try:
            process.wait(timeout=8)
        except subprocess.TimeoutExpired:
            process.kill()

    def synthesize(self, text: str, output_path: Path, style: str = "normal") -> float:
        if not self.is_ready() and not self.start():
            raise RuntimeError(self.last_error or "GPT-SoVITS is unavailable")

        reference = REFERENCE_STYLES.get(style, REFERENCE_STYLES["normal"])
        payload = {
            "text": text,
            "text_lang": "zh",
            "ref_audio_path": str(MODEL_ROOT / reference["audio"]),
            "prompt_lang": "ja",
            "prompt_text": reference["text"],
            "text_split_method": "cut5",
            "batch_size": 1,
            "split_bucket": False,
            "media_type": "wav",
            "streaming_mode": False,
            "parallel_infer": True,
            "repetition_penalty": 1.35,
            "speed_factor": 0.88,
        }
        request = urllib.request.Request(
            f"{API_BASE_URL}/tts",
            data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            headers={"Content-Type": "application/json; charset=utf-8"},
            method="POST",
        )

        with self._request_lock:
            try:
                with urllib.request.urlopen(request, timeout=180) as response:
                    audio_bytes = response.read()
            except urllib.error.HTTPError as error:
                detail = error.read().decode("utf-8", errors="replace")
                raise RuntimeError(f"GPT-SoVITS HTTP {error.code}: {detail}") from error
            except (OSError, urllib.error.URLError) as error:
                raise RuntimeError(f"GPT-SoVITS request failed: {error}") from error

        if len(audio_bytes) < 1024:
            raise RuntimeError("GPT-SoVITS returned an empty audio response")
        output_path.parent.mkdir(parents=True, exist_ok=True)
        temporary_path = output_path.with_suffix(".tmp.wav")
        temporary_path.write_bytes(audio_bytes)
        temporary_path.replace(output_path)
        return _duration_of_wav(output_path)

    def status(self) -> dict:
        return {
            "configured": self.configured,
            "ready": self.is_ready(),
            "voice": "staff_a_v2_pro_plus",
            "apiUrl": API_BASE_URL,
            "openJTalkDictionary": str(OPEN_JTALK_DICT_ROOT),
            "lastError": self.last_error,
        }

    def _patch_windows_torchaudio_compatibility(self) -> None:
        if sys.platform != "win32":
            return
        tts_path = RUNTIME_ROOT / "GPT_SoVITS" / "TTS_infer_pack" / "TTS.py"
        source = tts_path.read_text(encoding="utf-8")
        old = "        raw_audio, raw_sr = torchaudio.load(ref_audio_path)"
        marker = "        raw_audio_np, raw_sr = librosa.load(ref_audio_path, sr=None, mono=False)"
        if marker in source:
            return
        if old not in source:
            raise RuntimeError("Unsupported GPT-SoVITS TTS.py audio loader")
        replacement = "\n".join(
            (
                marker,
                "        if raw_audio_np.ndim == 1:",
                "            raw_audio_np = raw_audio_np[None, :]",
                "        raw_audio = torch.from_numpy(raw_audio_np)",
            )
        )
        tts_path.write_text(source.replace(old, replacement, 1), encoding="utf-8")

    @staticmethod
    def _startup_error(stderr_path: Path) -> str:
        try:
            lines = stderr_path.read_text(encoding="utf-8", errors="replace").splitlines()
            return "GPT-SoVITS failed to start: " + " | ".join(lines[-4:])
        except OSError:
            return "GPT-SoVITS failed to start"


def _duration_of_wav(path: Path) -> float:
    import wave

    with wave.open(str(path), "rb") as wav_file:
        return wav_file.getnframes() / wav_file.getframerate()
