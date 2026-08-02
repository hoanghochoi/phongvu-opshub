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
LOCAL_PRESET_PACK_VERSION = "local-preset-speaker-v1"
LOCAL_PRESET_SAMPLE_RATE = 22_050
LOCAL_PRESET_ASSET_COUNT = 1_104
LOCAL_PRESET_CHUNK_COUNT = 1_103
LOCAL_PRESET_IDS = {
    "mien-bac-thanh-ha": "Miền Bắc — Thanh Hà",
    "mien-trung-mai-ngoc": "Miền Trung — Mai Ngọc",
    "mien-nam-phuong-ly": "Miền Nam — Phương Ly",
}


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


def validate_local_preset_pack(root: Path) -> dict[str, int | str]:
    manifest_path = root / "manifest.json"
    notice_path = root / "THIRD_PARTY_NOTICES.md"
    if not manifest_path.is_file() or not notice_path.is_file():
        raise FileNotFoundError("manifest.json or THIRD_PARTY_NOTICES.md is missing")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("schemaVersion") != 2:
        raise ValueError("unsupported local preset manifest schema")
    if manifest.get("assetPackVersion") != LOCAL_PRESET_PACK_VERSION:
        raise ValueError("unexpected local preset asset pack version")
    voice_preset = manifest.get("voicePreset")
    if not isinstance(voice_preset, dict):
        raise ValueError("local preset voice metadata is missing")
    preset_id = voice_preset.get("id")
    if preset_id not in LOCAL_PRESET_IDS or root.name != preset_id:
        raise ValueError("local preset identity does not match its directory")
    if voice_preset.get("label") != LOCAL_PRESET_IDS[preset_id]:
        raise ValueError("local preset label is invalid")
    expected_policy = {
        "packageSampleRate": LOCAL_PRESET_SAMPLE_RATE,
        "channels": 1,
        "bitsPerSample": 16,
        "sourceBoundaryTrimThresholdDbfs": -60,
        "internalAmountJoinGapMs": 0,
        "internalAmountCrossfadeMs": 50,
        "preserveFinalCurrencyTail": True,
        "cueToPhraseGapMs": 120,
        "prefixToAmountGapMs": 150,
    }
    policy = manifest.get("audioPolicy")
    if not isinstance(policy, dict):
        raise ValueError("local preset audio policy is missing")
    for key, expected in expected_policy.items():
        if policy.get(key) != expected:
            raise ValueError(f"unexpected local preset audio policy {key}")
    inventory = manifest.get("inventory")
    if inventory != {
        "scheme": "chunk-0-999",
        "chunkAssetCount": LOCAL_PRESET_CHUNK_COUNT,
        "assetCount": LOCAL_PRESET_ASSET_COUNT,
    }:
        raise ValueError("local preset inventory metadata is invalid")

    assets = manifest.get("assets")
    if not isinstance(assets, list) or len(assets) != LOCAL_PRESET_ASSET_COUNT:
        raise ValueError(f"expected {LOCAL_PRESET_ASSET_COUNT} local preset assets")
    expected_asset_ids = expected_ids() | {"prefix"}
    ids = [asset.get("id") for asset in assets if isinstance(asset, dict)]
    if len(ids) != len(assets) or len(set(ids)) != len(ids) or set(ids) != expected_asset_ids:
        raise ValueError("local preset asset IDs do not match the chunk grammar")
    files = [asset.get("file") for asset in assets if isinstance(asset, dict)]
    if len(files) != len(assets) or len(set(files)) != len(files):
        raise ValueError("local preset asset filenames are invalid or duplicated")

    total_bytes = 0
    for asset in assets:
        assert isinstance(asset, dict)
        name = asset["file"]
        if not isinstance(name, str) or not name or "/" in name or "\\" in name or ".." in name:
            raise ValueError("local preset asset filename is unsafe")
        path = root / name
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
            if actual_format != (1, 2, LOCAL_PRESET_SAMPLE_RATE, "NONE"):
                raise ValueError(f"WAV format mismatch: {path.name}: {actual_format}")
            frames = audio.getnframes()
            pcm = audio.readframes(frames)
        if frames != asset.get("frames") or frames <= 0:
            raise ValueError(f"frame count mismatch: {path.name}")
        expected_duration = round(frames * 1000 / LOCAL_PRESET_SAMPLE_RATE, 3)
        if asset.get("durationMs") != expected_duration:
            raise ValueError(f"duration mismatch: {path.name}")
        if not any(pcm):
            raise ValueError(f"silent WAV asset: {path.name}")
        samples = array.array("h")
        samples.frombytes(pcm)
        if sys.byteorder != "little":
            samples.byteswap()
        if any(sample in {-32768, 32767} for sample in samples):
            raise ValueError(f"full-scale WAV sample: {path.name}")
        total_bytes += path.stat().st_size

    actual_wavs = {path.name for path in root.glob("*.wav")}
    if actual_wavs != set(files):
        missing = sorted(set(files) - actual_wavs)[:5]
        extra = sorted(actual_wavs - set(files))[:5]
        raise ValueError(f"local preset inventory mismatch: missing={missing} extra={extra}")
    return {
        "pack": LOCAL_PRESET_PACK_VERSION,
        "preset": preset_id,
        "assets": len(assets),
        "bytes": total_bytes,
        "sampleRate": LOCAL_PRESET_SAMPLE_RATE,
    }


def validate_local_preset_root(root: Path) -> list[dict[str, int | str]]:
    if not root.is_dir():
        raise FileNotFoundError(root)
    directories = {path.name for path in root.iterdir() if path.is_dir()}
    if directories != set(LOCAL_PRESET_IDS):
        missing = sorted(set(LOCAL_PRESET_IDS) - directories)
        unexpected = sorted(directories - set(LOCAL_PRESET_IDS))
        raise ValueError(f"local preset directories mismatch: missing={missing} extra={unexpected}")
    return [validate_local_preset_pack(root / preset_id) for preset_id in sorted(LOCAL_PRESET_IDS)]


def main() -> None:
    parser = argparse.ArgumentParser()
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--pack", type=Path)
    source.add_argument("--presets-root", type=Path)
    args = parser.parse_args()
    if args.presets_root is not None:
        summaries = validate_local_preset_root(args.presets_root.resolve())
        print(json.dumps(summaries, ensure_ascii=False, sort_keys=True))
        return
    assert args.pack is not None
    manifest = json.loads((args.pack.resolve() / "manifest.json").read_text(encoding="utf-8"))
    summary = (
        validate_local_preset_pack(args.pack.resolve())
        if manifest.get("assetPackVersion") == LOCAL_PRESET_PACK_VERSION
        else validate_pack(args.pack.resolve())
    )
    print(json.dumps(summary, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
