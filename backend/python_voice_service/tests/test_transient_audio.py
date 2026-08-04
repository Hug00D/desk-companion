import io
import json
import os
import socket
import sys
import tempfile
import threading
import time
import unittest
import urllib.request
import uvicorn
import wave
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch


APP_DIR = Path(__file__).resolve().parents[1] / "app"
sys.path.insert(0, str(APP_DIR))

import main as voice_main
import gpt_sovits_engine as voice_engine


def _start_test_server() -> tuple[uvicorn.Server, threading.Thread, socket.socket, int]:
    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server_socket.bind(("127.0.0.1", 0))
    port = server_socket.getsockname()[1]
    server = uvicorn.Server(
        uvicorn.Config(
            voice_main.app,
            log_level="critical",
            access_log=False,
        )
    )
    server_thread = threading.Thread(
        target=server.run,
        kwargs={"sockets": [server_socket]},
        daemon=True,
    )
    server_thread.start()
    deadline = time.time() + 5
    while not server.started and server_thread.is_alive() and time.time() < deadline:
        time.sleep(0.01)
    if not server.started:
        server.should_exit = True
        server_thread.join(timeout=2)
        server_socket.close()
        raise RuntimeError("Uvicorn test server did not start")
    return server, server_thread, server_socket, port


def _stop_test_server(
    server: uvicorn.Server,
    server_thread: threading.Thread,
    server_socket: socket.socket,
) -> None:
    server.should_exit = True
    server_thread.join(timeout=5)
    server_socket.close()


class TransientAudioTest(unittest.TestCase):
    def setUp(self) -> None:
        self._temporary_directory = tempfile.TemporaryDirectory()
        self._original_output_dir = voice_main.OUTPUT_DIR
        self._original_delete_grace = voice_main.AUDIO_DELETE_GRACE_SECONDS
        voice_main.OUTPUT_DIR = Path(self._temporary_directory.name)
        voice_main.AUDIO_DELETE_GRACE_SECONDS = 0

    def tearDown(self) -> None:
        voice_main.OUTPUT_DIR = self._original_output_dir
        voice_main.AUDIO_DELETE_GRACE_SECONDS = self._original_delete_grace
        self._temporary_directory.cleanup()

    def test_audio_file_is_deleted_after_it_is_sent(self) -> None:
        audio_bytes = b"RIFF-one-shot-audio"
        audio_path = voice_main.OUTPUT_DIR / "voice_test.wav"
        audio_path.write_bytes(audio_bytes)
        server, server_thread, server_socket, port = _start_test_server()
        try:
            with urllib.request.urlopen(
                f"http://127.0.0.1:{port}/audio/{audio_path.name}",
                timeout=5,
            ) as response:
                received = response.read()
                self.assertEqual(response.status, 200)
                self.assertEqual(received, audio_bytes)
                self.assertEqual(response.headers["Cache-Control"], "no-store")
                self.assertEqual(
                    int(response.headers["X-Audio-Length"]),
                    len(received),
                )
            deadline = time.time() + 2
            while audio_path.exists() and time.time() < deadline:
                time.sleep(0.01)
            self.assertFalse(audio_path.exists())
        finally:
            _stop_test_server(server, server_thread, server_socket)

    def test_audio_file_is_complete_over_a_real_http_connection(self) -> None:
        audio_bytes = b"RIFF" + (b"desk-companion-audio" * 20000)
        audio_path = voice_main.OUTPUT_DIR / "voice_network_test.wav"
        audio_path.write_bytes(audio_bytes)
        server, server_thread, server_socket, port = _start_test_server()

        try:
            request = urllib.request.Request(
                f"http://127.0.0.1:{port}/audio/{audio_path.name}",
            )
            with urllib.request.urlopen(request, timeout=5) as response:
                received = response.read()
                self.assertEqual(response.status, 200)
                self.assertEqual(response.version, 11)
                self.assertIsNone(response.headers["Transfer-Encoding"])
                self.assertEqual(
                    int(response.headers["Content-Length"]),
                    len(received),
                )
                self.assertEqual(int(response.headers["X-Audio-Length"]), len(received))
            self.assertEqual(received, audio_bytes)
        finally:
            _stop_test_server(server, server_thread, server_socket)

    def test_concurrent_generation_requests_wait_instead_of_being_skipped(self) -> None:
        server, server_thread, server_socket, port = _start_test_server()
        active_generations = 0
        maximum_active_generations = 0
        generation_state_lock = threading.Lock()

        def generate(text, output_path, *args, **kwargs):
            nonlocal active_generations, maximum_active_generations
            with generation_state_lock:
                active_generations += 1
                maximum_active_generations = max(
                    maximum_active_generations,
                    active_generations,
                )
            try:
                time.sleep(0.15)
                with wave.open(str(output_path), "wb") as wav_file:
                    wav_file.setnchannels(1)
                    wav_file.setsampwidth(2)
                    wav_file.setframerate(16000)
                    wav_file.writeframes(b"\x00\x00" * 160)
                return "gpt_sovits", 0.01, output_path
            finally:
                with generation_state_lock:
                    active_generations -= 1

        def send_tts(request_id: str) -> dict:
            payload = json.dumps(
                {
                    "requestId": request_id,
                    "text": f"test {request_id}",
                    "source": "assistant",
                    "status": "assistant_chat",
                }
            ).encode("utf-8")
            request = urllib.request.Request(
                f"http://127.0.0.1:{port}/tts",
                data=payload,
                headers={
                    "Content-Type": "application/json",
                },
                method="POST",
            )
            with urllib.request.urlopen(request, timeout=5) as response:
                self.assertEqual(response.status, 200)
                return json.loads(response.read().decode("utf-8"))

        try:
            with patch.object(voice_main, "_generate_speech_wav", side_effect=generate):
                with ThreadPoolExecutor(max_workers=2) as executor:
                    results = list(
                        executor.map(send_tts, ("queue-one", "queue-two"))
                    )
            self.assertEqual(maximum_active_generations, 1)
            self.assertEqual(
                {result["requestId"] for result in results},
                {"queue-one", "queue-two"},
            )
            self.assertTrue(all(result["mode"] == "gpt_sovits" for result in results))
        finally:
            _stop_test_server(server, server_thread, server_socket)

    def test_invalid_gpt_sovits_response_never_replaces_output_file(self) -> None:
        output_path = voice_main.OUTPUT_DIR / "voice_invalid_engine.wav"

        class InvalidAudioResponse:
            status = 200

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def read(self):
                return b"not-a-wav" * 200

        engine = voice_engine.GptSoVitsEngine()
        with (
            patch.object(engine, "is_ready", return_value=True),
            patch.object(
                voice_engine.urllib.request,
                "urlopen",
                return_value=InvalidAudioResponse(),
            ),
        ):
            with self.assertRaisesRegex(RuntimeError, "invalid WAV"):
                engine.synthesize("test", output_path)

        self.assertFalse(output_path.exists())
        self.assertFalse(output_path.with_suffix(".tmp.wav").exists())

    def test_cleanup_removes_only_stale_generated_audio(self) -> None:
        stale_voice = voice_main.OUTPUT_DIR / "voice_old.wav"
        stale_cache = voice_main.OUTPUT_DIR / "cached_voice_old.wav"
        recent_voice = voice_main.OUTPUT_DIR / "voice_recent.wav"
        unrelated_file = voice_main.OUTPUT_DIR / "notes.txt"
        for path in (stale_voice, stale_cache, recent_voice, unrelated_file):
            path.write_bytes(b"test")

        old_timestamp = time.time() - 700
        os.utime(stale_voice, (old_timestamp, old_timestamp))
        os.utime(stale_cache, (old_timestamp, old_timestamp))

        removed = voice_main._cleanup_stale_audio_files(max_age_seconds=600)

        self.assertEqual(removed, 2)
        self.assertFalse(stale_voice.exists())
        self.assertFalse(stale_cache.exists())
        self.assertTrue(recent_voice.exists())
        self.assertTrue(unrelated_file.exists())

    def test_log_does_not_crash_on_text_outside_cp950(self) -> None:
        output_bytes = io.BytesIO()
        cp950_stream = io.TextIOWrapper(output_bytes, encoding="cp950")
        original_stdout = voice_main.sys.stdout
        try:
            voice_main.sys.stdout = cp950_stream
            voice_main._safe_log("assistant text: 来")
            cp950_stream.flush()
        finally:
            voice_main.sys.stdout = original_stdout

        logged_text = output_bytes.getvalue().decode("cp950")
        self.assertIn(r"\u6765", logged_text)

    def test_assistant_voice_does_not_fall_back_to_system_tts(self) -> None:
        output_path = voice_main.OUTPUT_DIR / "voice_assistant.wav"
        with (
            patch.object(voice_main.GPT_SOVITS_ENGINE, "is_ready", return_value=True),
            patch.object(
                voice_main,
                "_synthesize_gpt_sovits_validated",
                side_effect=RuntimeError("model failed"),
            ),
            patch.object(voice_main, "_generate_windows_tts_wav") as windows_tts,
        ):
            with self.assertRaisesRegex(RuntimeError, "generation failed"):
                voice_main._generate_speech_wav(
                    "Mixed English and Chinese",
                    output_path,
                    None,
                    None,
                    "normal",
                    allow_system_fallback=False,
                )

        windows_tts.assert_not_called()


if __name__ == "__main__":
    unittest.main()
