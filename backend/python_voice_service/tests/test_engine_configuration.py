import importlib
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


APP_DIR = Path(__file__).resolve().parents[1] / "app"
sys.path.insert(0, str(APP_DIR))

import gpt_sovits_engine


class EngineConfigurationTest(unittest.TestCase):
    def test_environment_paths_override_bundled_runtime(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runtime_root = root / "gpt-sovits"
            runtime_python = root / "voice" / "bin" / "python"
            model_root = root / "models" / "staff-a"
            environment = {
                "GPT_SOVITS_ROOT": str(runtime_root),
                "GPT_SOVITS_PYTHON": str(runtime_python),
                "GPT_SOVITS_MODEL_ROOT": str(model_root),
                "GPT_SOVITS_API_URL": "http://127.0.0.1:19980/",
            }
            with patch.dict(os.environ, environment, clear=False):
                module = importlib.reload(gpt_sovits_engine)
                self.assertEqual(module.RUNTIME_ROOT, runtime_root)
                self.assertEqual(module.RUNTIME_PYTHON, runtime_python)
                self.assertEqual(module.MODEL_ROOT, model_root)
                self.assertEqual(module.API_BASE_URL, "http://127.0.0.1:19980")

        importlib.reload(gpt_sovits_engine)

    def test_audio_loader_patch_is_cross_platform_and_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            runtime_root = Path(directory)
            tts_path = (
                runtime_root
                / "GPT_SoVITS"
                / "TTS_infer_pack"
                / "TTS.py"
            )
            tts_path.parent.mkdir(parents=True)
            tts_path.write_text(
                "        raw_audio, raw_sr = torchaudio.load(ref_audio_path)\n",
                encoding="utf-8",
            )

            engine = gpt_sovits_engine.GptSoVitsEngine()
            with patch.object(gpt_sovits_engine, "RUNTIME_ROOT", runtime_root):
                engine._patch_torchaudio_loader_compatibility()
                engine._patch_torchaudio_loader_compatibility()

            patched_source = tts_path.read_text(encoding="utf-8")
            self.assertNotIn("torchaudio.load", patched_source)
            self.assertEqual(patched_source.count("librosa.load"), 1)
            self.assertIn("torch.from_numpy(raw_audio_np)", patched_source)


if __name__ == "__main__":
    unittest.main()
