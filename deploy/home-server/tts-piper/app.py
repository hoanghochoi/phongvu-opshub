import logging
import os
import tempfile
import threading
import time
import wave
from pathlib import Path
from typing import Any

from fastapi import BackgroundTasks, FastAPI, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

from piper.config import SynthesisConfig
from piper.voice import PiperVoice


logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger("opshub-piper-tts")

MODEL_DIR = Path(
    os.getenv("PIPER_MODEL_DIR", "/opt/opshub-piper-tts/models/vi-vais1000")
)
MODEL_PATH = Path(os.getenv("PIPER_MODEL_PATH", str(MODEL_DIR / "model.onnx")))
CONFIG_PATH = Path(os.getenv("PIPER_CONFIG_PATH", str(MODEL_DIR / "config.json")))
TMP_DIR = Path(os.getenv("PIPER_TMP_DIR", "/tmp/opshub-piper-tts"))
DEFAULT_VOICE_ID = os.getenv("PIPER_VOICE_ID", "piper:vi-vais1000")
MAX_TEXT_CHARS = int(os.getenv("PIPER_MAX_TEXT_CHARS", "500"))
LEADING_SILENCE_MS = int(os.getenv("PIPER_LEADING_SILENCE_MS", "0"))
TAIL_SILENCE_MS = int(os.getenv("PIPER_TAIL_SILENCE_MS", "500"))

TMP_DIR.mkdir(parents=True, exist_ok=True)

app = FastAPI(title="OpsHub Piper TTS Sidecar")
_lock = threading.Lock()
_voice: PiperVoice | None = None
_loaded_at: float | None = None


class SynthesizeRequest(BaseModel):
    text: str = Field(min_length=1, max_length=MAX_TEXT_CHARS)
    format: str = "wav"
    speed: float | None = Field(default=None, ge=0.5, le=1.5)
    pitch: float | None = Field(default=None, ge=0.5, le=1.5)
    voice_index: int | None = Field(default=None, ge=0)
    voice_id: str | None = Field(default=None, max_length=96)


def _load_voice() -> PiperVoice:
    global _voice, _loaded_at
    if _voice is not None:
        return _voice

    start = time.perf_counter()
    if not MODEL_PATH.exists():
        raise RuntimeError(f"Piper model not found: {MODEL_PATH}")
    if not CONFIG_PATH.exists():
        raise RuntimeError(f"Piper config not found: {CONFIG_PATH}")

    logger.info(
        "Loading Piper voice",
        extra={"model_path": str(MODEL_PATH), "config_path": str(CONFIG_PATH)},
    )
    _voice = PiperVoice.load(str(MODEL_PATH), str(CONFIG_PATH))
    _loaded_at = time.time()
    logger.info("Piper voice loaded in %.3fs", time.perf_counter() - start)
    return _voice


@app.on_event("startup")
def startup() -> None:
    _load_voice()


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "status": "ok" if _voice is not None else "loading",
        "provider": "piper",
        "voiceId": DEFAULT_VOICE_ID,
        "loaded": _voice is not None,
    }


@app.get("/config")
def config() -> dict[str, Any]:
    return {
        "provider": "piper",
        "model": "vi-vais1000",
        "voiceId": DEFAULT_VOICE_ID,
        "aliases": ["piper:vi-vais1000", "custom:suong-vo", "builtin:0"],
        "format": "wav",
        "modelPath": str(MODEL_PATH),
        "configPath": str(CONFIG_PATH),
        "maxTextChars": MAX_TEXT_CHARS,
        "leadingSilenceMs": LEADING_SILENCE_MS,
        "tailSilenceMs": TAIL_SILENCE_MS,
        "loadedAt": _loaded_at,
    }


@app.post("/synthesize")
def synthesize(request: SynthesizeRequest, background_tasks: BackgroundTasks):
    text = request.text.strip()
    if not text:
        raise HTTPException(status_code=400, detail="text is required")

    voice_id = (request.voice_id or DEFAULT_VOICE_ID).strip()
    if voice_id not in {DEFAULT_VOICE_ID, "piper:vi-vais1000", "custom:suong-vo", "builtin:0"}:
        logger.warning("Unknown voice_id %s, falling back to %s", voice_id, DEFAULT_VOICE_ID)

    speed = request.speed or 1.0
    length_scale = 1.0 / speed
    syn_config = SynthesisConfig(
        speaker_id=request.voice_index,
        length_scale=length_scale,
    )

    fd, output_path = tempfile.mkstemp(
        prefix="opshub-piper-", suffix=".wav", dir=str(TMP_DIR)
    )
    os.close(fd)
    start = time.perf_counter()

    logger.info(
        "Piper synthesize start chars=%s speed=%.2f pitch_ignored=%s requested_format=%s",
        len(text),
        speed,
        request.pitch is not None,
        request.format,
    )
    try:
        with _lock:
            voice = _load_voice()
            with wave.open(output_path, "wb") as wav_file:
                voice.synthesize_wav(text, wav_file, syn_config=syn_config)
        _pad_wav_silence(output_path, LEADING_SILENCE_MS, TAIL_SILENCE_MS)

        duration = _wav_duration(output_path)
        size = Path(output_path).stat().st_size
        logger.info(
            "Piper synthesize success elapsed=%.3fs audio=%.2fs bytes=%s leading_silence_ms=%s tail_silence_ms=%s",
            time.perf_counter() - start,
            duration,
            size,
            LEADING_SILENCE_MS,
            TAIL_SILENCE_MS,
        )
        background_tasks.add_task(_cleanup_file, output_path)
        return FileResponse(
            output_path,
            media_type="audio/wav",
            filename="payment.wav",
            background=background_tasks,
        )
    except HTTPException:
        _cleanup_file(output_path)
        raise
    except Exception as error:
        _cleanup_file(output_path)
        logger.exception("Piper synthesize failed: %s", _safe_error(error))
        raise HTTPException(status_code=500, detail="TTS synthesize failed") from error


def _wav_duration(path: str) -> float:
    with wave.open(path, "rb") as wav_file:
        return wav_file.getnframes() / wav_file.getframerate()


def _pad_wav_silence(path: str, leading_ms: int, trailing_ms: int) -> None:
    if leading_ms <= 0 and trailing_ms <= 0:
        return
    with wave.open(path, "rb") as wav_file:
        params = wav_file.getparams()
        frames = wav_file.readframes(wav_file.getnframes())
    leading_frames = int(params.framerate * max(leading_ms, 0) / 1000)
    trailing_frames = int(params.framerate * max(trailing_ms, 0) / 1000)
    frame_width = params.nchannels * params.sampwidth
    leading_silence = b"\x00" * leading_frames * frame_width
    trailing_silence = b"\x00" * trailing_frames * frame_width
    with wave.open(path, "wb") as wav_file:
        wav_file.setparams(params)
        wav_file.writeframes(leading_silence)
        wav_file.writeframes(frames)
        wav_file.writeframes(trailing_silence)


def _cleanup_file(path: str) -> None:
    try:
        Path(path).unlink(missing_ok=True)
    except Exception as error:
        logger.warning("Failed to clean temporary audio file: %s", _safe_error(error))


def _safe_error(error: Exception) -> str:
    return str(error).replace("\n", " ")[:500]
