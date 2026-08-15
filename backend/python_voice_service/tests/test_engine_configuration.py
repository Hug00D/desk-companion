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


if __name__ == "__main__":
    unittest.main()
