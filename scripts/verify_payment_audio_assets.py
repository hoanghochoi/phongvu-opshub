#!/usr/bin/env python3
"""Fail-closed validation for the packaged OPS-11 payment audio assets."""

from __future__ import annotations

import argparse
import array
import hashlib
import json
import sys
import wave
from pathlib import Path


PACK_VERSION = "piper-vi-vais1000-chunk-v1"
VOICE = "Piper vi-vais1000"
PIPER_TTS_VERSION = "1.4.2"
MODEL_SHA256 = "ec7c89e2c85f4d1edc24b6120c18aaf1bda614f06b511567eb9c7c0de15e2dab"
CONFIG_SHA256 = "fafb9da1354ed4b77c31af228ed41fb41cd825c14cffa105454b25e6ae751ee0"
EXPECTED_ASSET_COUNT = 1_103
SAMPLE_RATE = 24_000
LEADING_MS = 300
TRAILING_MS = 200


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def expected_ids() -> set[str]:
    values = {f"chunk/leading/{value:03d}" for value in range(1_000)}
    values.update(f"chunk/forced/{value:03d}" for value in range(1, 100))
    values.update(
        {
            "chunk/unit/nghìn",
            "chunk/unit/triệu",
            "chunk/unit/tỷ",
            "chunk/unit/đồng",
        }
    )
    return values


def validate_pack(root: Path) -> dict[str, int | str]:
    manifest_path = root / "manifest.json"
    notice_path = root / "THIRD_PARTY_NOTICES.md"
    if not manifest_path.is_file() or not notice_path.is_file():
        raise FileNotFoundError("manifest.json or THIRD_PARTY_NOTICES.md is missing")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("schemaVersion") != 1:
        raise ValueError("unsupported manifest schema")
    if manifest.get("assetPackVersion") != PACK_VERSION:
        raise ValueError(f"unexpected asset pack version: {manifest.get('assetPackVersion')}")
    if manifest.get("voice") != VOICE:
        raise ValueError(f"unexpected voice: {manifest.get('voice')}")
    generator = manifest.get("generator", {})
    expected_generator = {
        "provider": "Piper",
        "piperTtsVersion": PIPER_TTS_VERSION,
        "voiceId": "piper:vi-vais1000",
        "model": "vi-vais1000",
        "modelSha256": MODEL_SHA256,
        "configSha256": CONFIG_SHA256,
        "speed": 0.9,
        "outputGainDb": -1.5,
    }
    for key, expected in expected_generator.items():
        if generator.get(key) != expected:
            raise ValueError(f"unexpected generator {key}: {generator.get(key)}")
    policy = manifest.get("audioPolicy", {})
    expected_policy = {
        "packageSampleRate": SAMPLE_RATE,
        "channels": 1,
        "bitsPerSample": 16,
        "assetLeadingSilenceMs": LEADING_MS,
        "assetTrailingSilenceMs": TRAILING_MS,
        "composeBoundarySilenceMs": 0,
        "joinGapMs": 45,
        "outputGainDb": -1.5,
    }
    for key, expected in expected_policy.items():
        if policy.get(key) != expected:
            raise ValueError(f"unexpected audio policy {key}: {policy.get(key)}")

    assets = manifest.get("assets")
    if not isinstance(assets, list) or len(assets) != EXPECTED_ASSET_COUNT:
        raise ValueError(f"expected {EXPECTED_ASSET_COUNT} manifest assets")
    ids = [asset.get("id") for asset in assets]
    if len(set(ids)) != len(ids) or set(ids) != expected_ids():
        raise ValueError("asset IDs are duplicated or do not match the chunk grammar")
    files = [asset.get("file") for asset in assets]
    if len(set(files)) != len(files):
        raise ValueError("manifest contains duplicate file names")

    leading_frames = SAMPLE_RATE * LEADING_MS // 1_000
    trailing_frames = SAMPLE_RATE * TRAILING_MS // 1_000
    total_bytes = 0
    for asset in assets:
        path = root / str(asset["file"])
        if not path.is_file() or path.parent != root:
            raise FileNotFoundError(path)
        if path.stat().st_size != asset.get("bytes"):
            raise ValueError(f"size mismatch: {path.name}")
        if sha256(path) != asset.get("sha256"):
            raise ValueError(f"SHA-256 mismatch: {path.name}")
        with wave.open(str(path), "rb") as audio:
            actual_format = (
                audio.getnchannels(),
                audio.getsampwidth(),
                audio.getframerate(),
                audio.getcomptype(),
            )
            if actual_format != (1, 2, SAMPLE_RATE, "NONE"):
                raise ValueError(f"WAV format mismatch: {path.name}: {actual_format}")
            frames = audio.getnframes()
            pcm = audio.readframes(frames)
        if frames != asset.get("frames") or frames <= leading_frames + trailing_frames:
            raise ValueError(f"frame count mismatch: {path.name}")
        leading_bytes = leading_frames * 2
        trailing_bytes = trailing_frames * 2
        if any(pcm[:leading_bytes]) or any(pcm[-trailing_bytes:]):
            raise ValueError(f"boundary guard is not silent: {path.name}")
        if not any(pcm[leading_bytes:-trailing_bytes]):
            raise ValueError(f"speech payload is silent: {path.name}")
        content = array.array("h")
        content.frombytes(pcm[leading_bytes:-trailing_bytes])
        if sys.byteorder != "little":
            content.byteswap()
        if any(sample in {-32768, 32767} for sample in content):
            raise ValueError(f"speech payload reaches full scale: {path.name}")
        expected_content_frames = round(float(asset["contentDurationMs"]) * SAMPLE_RATE / 1_000)
        if frames != leading_frames + expected_content_frames + trailing_frames:
            raise ValueError(f"content duration mismatch: {path.name}")
        total_bytes += path.stat().st_size

    actual_wavs = {path.name for path in root.glob("*.wav")}
    if actual_wavs != set(files):
        missing = sorted(set(files) - actual_wavs)[:5]
        extra = sorted(actual_wavs - set(files))[:5]
        raise ValueError(f"pack inventory mismatch: missing={missing} extra={extra}")
    return {
        "pack": PACK_VERSION,
        "assets": len(assets),
        "bytes": total_bytes,
        "sampleRate": SAMPLE_RATE,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pack", type=Path, required=True)
    args = parser.parse_args()
    summary = validate_pack(args.pack.resolve())
    print(json.dumps(summary, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
