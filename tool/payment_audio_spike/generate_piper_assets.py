#!/usr/bin/env python3
"""Generate the immutable OPS-11 Windows payment-number pack with Piper."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import statistics
import time
import wave
from dataclasses import dataclass
from importlib.metadata import version as package_version
from pathlib import Path
from typing import Sequence

import numpy as np
import soxr
from piper.config import SynthesisConfig
from piper.voice import PiperVoice


PIPER_TTS_VERSION = "1.4.2"
PACK_VERSION = "piper-vi-vais1000-chunk-v1"
VOICE = "Piper vi-vais1000"
VOICE_ID = "piper:vi-vais1000"
MODEL_SOURCE = "nrl-ai/edgevox-models/piper/vi-vais1000"
MODEL_SHA256 = "ec7c89e2c85f4d1edc24b6120c18aaf1bda614f06b511567eb9c7c0de15e2dab"
CONFIG_SHA256 = "fafb9da1354ed4b77c31af228ed41fb41cd825c14cffa105454b25e6ae751ee0"
SPEED = 0.90
OUTPUT_GAIN_DB = -1.5
PACKAGE_SAMPLE_RATE = 24_000
TRIM_THRESHOLD_DB = -65.0
TRIM_PADDING_MS = 20
ASSET_LEADING_SILENCE_MS = 300
ASSET_TRAILING_SILENCE_MS = 200
COMPOSE_BOUNDARY_SILENCE_MS = 0
JOIN_GAP_MS = 45
MIN_CONTENT_DURATION_MS = 140
MAX_CLIPPED_SAMPLES = 0
SUPPORTED_AMOUNT_MAX = 999_999_999_999_999_999

DIGITS = ["không", "một", "hai", "ba", "bốn", "năm", "sáu", "bảy", "tám", "chín"]
GROUP_UNITS = ["", "nghìn", "triệu", "tỷ", "nghìn tỷ", "triệu tỷ"]


@dataclass(frozen=True)
class AssetSpec:
    asset_id: str
    text: str
    role: str


def read_three_digits(value: int, force_hundreds: bool) -> str:
    if value < 0 or value > 999:
        raise ValueError("three-digit value must be in range 0..999")
    hundred = value // 100
    ten = (value % 100) // 10
    unit = value % 10
    parts: list[str] = []
    if hundred > 0:
        parts.extend([DIGITS[hundred], "trăm"])
    elif force_hundreds and (ten > 0 or unit > 0):
        parts.extend(["không", "trăm"])
    if ten > 1:
        parts.extend([DIGITS[ten], "mươi"])
        if unit == 1:
            parts.append("mốt")
        elif unit == 4:
            parts.append("tư")
        elif unit == 5:
            parts.append("lăm")
        elif unit > 0:
            parts.append(DIGITS[unit])
    elif ten == 1:
        parts.append("mười")
        if unit == 5:
            parts.append("lăm")
        elif unit > 0:
            parts.append(DIGITS[unit])
    elif unit > 0:
        if hundred > 0 or force_hundreds:
            parts.append("lẻ")
        parts.append(DIGITS[unit])
    return " ".join(parts)


def vietnamese_amount_words(amount: int) -> str:
    if amount <= 0 or amount > SUPPORTED_AMOUNT_MAX:
        raise ValueError("amount is outside the supported VND range")
    groups: list[int] = []
    remaining = amount
    while remaining > 0:
        groups.append(remaining % 1000)
        remaining //= 1000
    if len(groups) > len(GROUP_UNITS):
        raise ValueError("amount exceeds supported group units")
    highest = len(groups) - 1
    parts: list[str] = []
    for index in range(highest, -1, -1):
        group = groups[index]
        if group == 0:
            continue
        phrase = read_three_digits(group, force_hundreds=index < highest)
        if GROUP_UNITS[index]:
            phrase += " " + GROUP_UNITS[index]
        parts.append(phrase)
    return " ".join(parts)


def chunk_inventory() -> list[AssetSpec]:
    assets = [
        AssetSpec(
            f"chunk/leading/{value:03d}",
            "không" if value == 0 else read_three_digits(value, False),
            "leading-group",
        )
        for value in range(1000)
    ]
    assets.extend(
        AssetSpec(
            f"chunk/forced/{value:03d}",
            read_three_digits(value, True),
            "forced-group",
        )
        for value in range(1, 100)
    )
    assets.extend(
        AssetSpec(f"chunk/unit/{unit}", unit, "scale-unit")
        for unit in ["nghìn", "triệu", "tỷ", "đồng"]
    )
    return assets


def amount_chunk_asset_ids(amount: int) -> list[str]:
    if amount <= 0 or amount > SUPPORTED_AMOUNT_MAX:
        raise ValueError("amount is outside the supported VND range")
    groups: list[int] = []
    remaining = amount
    while remaining > 0:
        groups.append(remaining % 1000)
        remaining //= 1000
    highest = len(groups) - 1
    ids: list[str] = []
    for index in range(highest, -1, -1):
        value = groups[index]
        if value == 0:
            continue
        role = "forced" if index < highest and value < 100 else "leading"
        ids.append(f"chunk/{role}/{value:03d}")
        unit = GROUP_UNITS[index]
        if unit:
            ids.extend(f"chunk/unit/{part}" for part in unit.split())
    ids.append("chunk/unit/đồng")
    return ids


def safe_name(asset_id: str) -> str:
    return asset_id.replace("/", "__").replace(" ", "-")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_pcm16(path: Path) -> tuple[int, np.ndarray]:
    with wave.open(str(path), "rb") as audio:
        if audio.getnchannels() != 1 or audio.getsampwidth() != 2:
            raise ValueError(f"unsupported WAV format: {path}")
        rate = audio.getframerate()
        samples = np.frombuffer(
            audio.readframes(audio.getnframes()), dtype="<i2"
        ).copy()
    return rate, samples


def write_pcm16(path: Path, sample_rate: int, samples: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = np.asarray(samples, dtype="<i2")
    with wave.open(str(path), "wb") as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(sample_rate)
        audio.writeframes(pcm.tobytes())


def trim_audio(audio: np.ndarray, sample_rate: int) -> np.ndarray:
    mono = np.asarray(audio, dtype=np.float32).reshape(-1)
    threshold = 10 ** (TRIM_THRESHOLD_DB / 20.0)
    active = np.flatnonzero(np.abs(mono) >= threshold)
    if not active.size:
        return np.zeros(0, dtype=np.float32)
    padding = round(sample_rate * TRIM_PADDING_MS / 1000)
    start = max(0, int(active[0]) - padding)
    end = min(len(mono), int(active[-1]) + padding + 1)
    return mono[start:end]


def add_boundary_silence(audio: np.ndarray, sample_rate: int) -> np.ndarray:
    leading = np.zeros(
        round(sample_rate * ASSET_LEADING_SILENCE_MS / 1000), dtype=np.float32
    )
    trailing = np.zeros(
        round(sample_rate * ASSET_TRAILING_SILENCE_MS / 1000), dtype=np.float32
    )
    return np.concatenate([leading, np.asarray(audio, dtype=np.float32), trailing])


def expected_max_content_duration_ms(text: str) -> int:
    return 2_000 + 450 * (max(1, len(text.split())) - 1)


def validate_candidate(spec: AssetSpec, audio: np.ndarray, sample_rate: int) -> list[str]:
    reasons: list[str] = []
    duration_ms = len(audio) * 1000 / sample_rate
    if duration_ms < MIN_CONTENT_DURATION_MS:
        reasons.append("too_short")
    if duration_ms > expected_max_content_duration_ms(spec.text):
        reasons.append("too_long")
    if not np.isfinite(audio).all():
        reasons.append("non_finite")
    peak = float(np.max(np.abs(audio), initial=0.0))
    if peak < 0.001:
        reasons.append("silent")
    clipped = int(np.count_nonzero(np.abs(audio) >= 1.0))
    if clipped > MAX_CLIPPED_SAMPLES:
        reasons.append("clipped")
    return reasons


def validate_stored_asset(
    spec: AssetSpec, samples: np.ndarray, sample_rate: int
) -> list[str]:
    leading_frames = round(sample_rate * ASSET_LEADING_SILENCE_MS / 1000)
    trailing_frames = round(sample_rate * ASSET_TRAILING_SILENCE_MS / 1000)
    if len(samples) <= leading_frames + trailing_frames:
        return ["missing_boundary_guard", "too_short"]
    reasons: list[str] = []
    if np.any(samples[:leading_frames]) or np.any(samples[-trailing_frames:]):
        reasons.append("missing_boundary_guard")
    content = samples[leading_frames:-trailing_frames].astype(np.float32) / 32768.0
    reasons.extend(validate_candidate(spec, content, sample_rate))
    return sorted(set(reasons))


def _synthesize(voice: PiperVoice, spec: AssetSpec, speed: float) -> tuple[int, np.ndarray]:
    buffer = io.BytesIO()
    synthesis = SynthesisConfig(length_scale=1.0 / speed)
    with wave.open(buffer, "wb") as output:
        voice.synthesize_wav(spec.text + ".", output, syn_config=synthesis)
    buffer.seek(0)
    with wave.open(buffer, "rb") as audio:
        actual_format = (audio.getnchannels(), audio.getsampwidth(), audio.getcomptype())
        if actual_format != (1, 2, "NONE"):
            raise ValueError(f"unexpected Piper WAV format: {actual_format}")
        sample_rate = audio.getframerate()
        samples = np.frombuffer(
            audio.readframes(audio.getnframes()), dtype="<i2"
        ).copy()
    return sample_rate, samples.astype(np.float32) / 32768.0


def generate_asset(
    voice: PiperVoice,
    spec: AssetSpec,
    output: Path,
    speed: float,
) -> dict[str, object]:
    started = time.perf_counter()
    source_rate, source = _synthesize(voice, spec, speed)
    if source_rate != 22_050:
        raise ValueError(f"Unexpected Piper sample rate: {source_rate}")
    trimmed = trim_audio(source, source_rate)
    reasons = validate_candidate(spec, trimmed, source_rate)
    if reasons:
        raise ValueError(f"Piper QC rejected {spec.asset_id}: {','.join(reasons)}")
    package_audio = soxr.resample(
        trimmed, source_rate, PACKAGE_SAMPLE_RATE, quality="HQ"
    ).astype(np.float32)
    package_audio *= 10 ** (OUTPUT_GAIN_DB / 20.0)
    guarded = add_boundary_silence(package_audio, PACKAGE_SAMPLE_RATE)
    pcm = np.round(np.clip(guarded, -1.0, 32767 / 32768) * 32768).astype(np.int16)
    path = output / f"{safe_name(spec.asset_id)}.wav"
    write_pcm16(path, PACKAGE_SAMPLE_RATE, pcm)
    stored_rate, stored = read_pcm16(path)
    stored_reasons = validate_stored_asset(spec, stored, stored_rate)
    if stored_reasons:
        raise ValueError(
            f"Packaged QC rejected {spec.asset_id}: {','.join(stored_reasons)}"
        )
    leading_frames = round(PACKAGE_SAMPLE_RATE * ASSET_LEADING_SILENCE_MS / 1000)
    trailing_frames = round(PACKAGE_SAMPLE_RATE * ASSET_TRAILING_SILENCE_MS / 1000)
    content = stored[leading_frames:-trailing_frames]
    content_duration_ms = round(len(content) * 1000 / PACKAGE_SAMPLE_RATE, 2)
    rms = float(np.sqrt(np.mean(np.square(content.astype(np.float64))))) / 32768.0
    peak = float(np.max(np.abs(content.astype(np.int32)), initial=0)) / 32768.0
    return {
        "id": spec.asset_id,
        "text": spec.text,
        "role": spec.role,
        "file": path.name,
        "bytes": path.stat().st_size,
        "sha256": sha256(path),
        "frames": len(stored),
        "contentDurationMs": content_duration_ms,
        "rmsDbfs": round(20 * np.log10(max(rms, 1e-12)), 2),
        "peakDbfs": round(20 * np.log10(max(peak, 1e-12)), 2),
        "generationMs": round((time.perf_counter() - started) * 1000, 2),
    }


def build_pack(
    model_path: Path,
    config_path: Path,
    output: Path,
    speed: float,
) -> dict[str, object]:
    if package_version("piper-tts") != PIPER_TTS_VERSION:
        raise ValueError("Installed piper-tts version does not match production")
    if sha256(model_path) != MODEL_SHA256:
        raise ValueError("Piper model checksum does not match production")
    if sha256(config_path) != CONFIG_SHA256:
        raise ValueError("Piper config checksum does not match production")
    output.mkdir(parents=True, exist_ok=False)
    specs = chunk_inventory()
    voice = PiperVoice.load(str(model_path), str(config_path))
    assets: list[dict[str, object]] = []
    started = time.perf_counter()
    for index, spec in enumerate(specs, 1):
        assets.append(generate_asset(voice, spec, output, speed))
        if index % 25 == 0 or index == len(specs):
            print(f"generated {index}/{len(specs)}", flush=True)

    durations = [float(asset["contentDurationMs"]) for asset in assets]
    manifest: dict[str, object] = {
        "schemaVersion": 1,
        "assetPackVersion": PACK_VERSION,
        "voice": VOICE,
        "generator": {
            "provider": "Piper",
            "piperTtsVersion": PIPER_TTS_VERSION,
            "voiceId": VOICE_ID,
            "model": "vi-vais1000",
            "modelSource": MODEL_SOURCE,
            "modelSha256": MODEL_SHA256,
            "configSha256": CONFIG_SHA256,
            "backend": "onnxruntime-cpu",
            "speed": speed,
            "lengthScale": round(1.0 / speed, 12),
            "outputGainDb": OUTPUT_GAIN_DB,
        },
        "audioPolicy": {
            "sourceSampleRate": 22_050,
            "packageSampleRate": PACKAGE_SAMPLE_RATE,
            "channels": 1,
            "bitsPerSample": 16,
            "trimThresholdDb": TRIM_THRESHOLD_DB,
            "trimPaddingMs": TRIM_PADDING_MS,
            "assetLeadingSilenceMs": ASSET_LEADING_SILENCE_MS,
            "assetTrailingSilenceMs": ASSET_TRAILING_SILENCE_MS,
            "composeBoundarySilenceMs": COMPOSE_BOUNDARY_SILENCE_MS,
            "joinGapMs": JOIN_GAP_MS,
            "outputGainDb": OUTPUT_GAIN_DB,
        },
        "license": {
            "spdx": "LicenseRef-Mixed",
            "attribution": [
                "OHF-Voice/piper1-gpl (GPL-3.0-or-later, build-time generator)",
                MODEL_SOURCE + " (repository declares mixed licensing)",
                "VAIS1000 Vietnamese speech dataset",
            ],
        },
        "inventory": {"scheme": "chunk-0-999", "assetCount": len(assets)},
        "supportedAmount": {
            "currency": "VND",
            "min": 1,
            "max": SUPPORTED_AMOUNT_MAX,
        },
        "quality": {
            "meanContentDurationMs": round(statistics.fmean(durations), 2),
            "p95ContentDurationMs": round(float(np.percentile(durations, 95)), 2),
            "maxContentDurationMs": round(max(durations), 2),
            "wallSeconds": round(time.perf_counter() - started, 2),
        },
        "assets": assets,
    }
    (output / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (output / "THIRD_PARTY_NOTICES.md").write_text(
        "# Third-party notices\n\n"
        "These immutable speech assets were generated at build time with Piper "
        "1.4.2 and the `vi-vais1000` model copied from the OpsHub production "
        "TTS host. Piper and the model are not distributed in the client.\n\n"
        "- Generator: OHF-Voice/piper1-gpl, GPL-3.0-or-later.\n"
        "- Model source: nrl-ai/edgevox-models/piper/vi-vais1000; the source "
        "repository declares mixed licensing.\n"
        "- Dataset recorded by the model: VAIS1000.\n\n"
        "Exact generator version, synthesis parameters and model/config SHA-256 "
        "checksums are recorded in `manifest.json`.\n",
        encoding="utf-8",
    )
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--speed", type=float, default=SPEED)
    args = parser.parse_args()
    if not 0.5 <= args.speed <= 1.5:
        parser.error("--speed must be between 0.5 and 1.5")
    manifest = build_pack(
        args.model.resolve(), args.config.resolve(), args.output.resolve(), args.speed
    )
    print(
        json.dumps(
            {
                "pack": manifest["assetPackVersion"],
                "assets": manifest["inventory"]["assetCount"],
                "quality": manifest["quality"],
            },
            ensure_ascii=False,
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
