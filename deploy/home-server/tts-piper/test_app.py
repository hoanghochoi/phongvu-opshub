import importlib.util
import os
import struct
import sys
import tempfile
import types
import unittest
import wave
from pathlib import Path


def _install_dependency_stubs() -> None:
    fastapi = types.ModuleType("fastapi")

    class FastAPI:
        def __init__(self, *args, **kwargs):
            pass

        def get(self, *args, **kwargs):
            return lambda function: function

        def post(self, *args, **kwargs):
            return lambda function: function

        def on_event(self, *args, **kwargs):
            return lambda function: function

    class BackgroundTasks:
        def add_task(self, *args, **kwargs):
            pass

    class HTTPException(Exception):
        def __init__(self, status_code, detail):
            super().__init__(detail)
            self.status_code = status_code
            self.detail = detail

    fastapi.FastAPI = FastAPI
    fastapi.BackgroundTasks = BackgroundTasks
    fastapi.HTTPException = HTTPException
    sys.modules["fastapi"] = fastapi

    responses = types.ModuleType("fastapi.responses")
    responses.FileResponse = object
    sys.modules["fastapi.responses"] = responses

    pydantic = types.ModuleType("pydantic")
    pydantic.BaseModel = type("BaseModel", (), {})
    pydantic.Field = lambda default=None, **kwargs: default
    sys.modules["pydantic"] = pydantic

    piper = types.ModuleType("piper")
    piper_config = types.ModuleType("piper.config")
    piper_config.SynthesisConfig = type("SynthesisConfig", (), {})
    piper_voice = types.ModuleType("piper.voice")
    piper_voice.PiperVoice = type("PiperVoice", (), {})
    sys.modules["piper"] = piper
    sys.modules["piper.config"] = piper_config
    sys.modules["piper.voice"] = piper_voice


class PiperAudioPaddingTest(unittest.TestCase):
    def test_defaults_to_no_leading_and_keeps_500ms_tail(self):
        _install_dependency_stubs()
        previous_leading = os.environ.pop("PIPER_LEADING_SILENCE_MS", None)
        previous_tail = os.environ.pop("PIPER_TAIL_SILENCE_MS", None)
        try:
            with tempfile.TemporaryDirectory() as temp:
                os.environ["PIPER_TMP_DIR"] = temp
                module_path = Path(__file__).with_name("app.py")
                spec = importlib.util.spec_from_file_location(
                    "opshub_piper_app_test", module_path
                )
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)

                self.assertEqual(module.LEADING_SILENCE_MS, 0)
                self.assertEqual(module.TAIL_SILENCE_MS, 500)

                wav_path = Path(temp) / "padding.wav"
                original_samples = [100, -100, 200, -200]
                with wave.open(str(wav_path), "wb") as wav_file:
                    wav_file.setnchannels(1)
                    wav_file.setsampwidth(2)
                    wav_file.setframerate(1000)
                    wav_file.writeframes(
                        struct.pack("<" + "h" * len(original_samples), *original_samples)
                    )

                module._pad_wav_silence(
                    str(wav_path),
                    module.LEADING_SILENCE_MS,
                    module.TAIL_SILENCE_MS,
                )

                with wave.open(str(wav_path), "rb") as wav_file:
                    frames = wav_file.readframes(wav_file.getnframes())
                    self.assertEqual(wav_file.getnframes(), 504)
                samples = struct.unpack("<" + "h" * (len(frames) // 2), frames)
                self.assertEqual(list(samples[:4]), original_samples)
                self.assertTrue(all(sample == 0 for sample in samples[4:]))
        finally:
            os.environ.pop("PIPER_TMP_DIR", None)
            if previous_leading is not None:
                os.environ["PIPER_LEADING_SILENCE_MS"] = previous_leading
            if previous_tail is not None:
                os.environ["PIPER_TAIL_SILENCE_MS"] = previous_tail


if __name__ == "__main__":
    unittest.main()
