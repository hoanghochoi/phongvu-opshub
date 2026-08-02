#!/usr/bin/env python3
"""Package the approved OPS-43 voice presets for the Windows installer.

The tool only copies immutable local WAVs. It never invokes a TTS service and
refuses incomplete, renamed, malformed, clipped, or unexpected source packs.
"""

from __future__ import annotations

import argparse
import array
import hashlib
import json
import re
import shutil
import unicodedata
import wave
from dataclasses import asdict, dataclass
from pathlib import Path


ASSET_PACK_VERSION = "local-preset-speaker-v1"
SAMPLE_RATE_HZ = 22_050
CHANNELS = 1
BITS_PER_SAMPLE = 16
CHUNK_ASSET_COUNT = 1_103
PREFIX_SOURCE_FILE = "phong-vu-da-nhan.wav"
PREFIX_FILE = "prefix.wav"
VOICE_PRESETS = (
    ("mien-bac-thanh-ha", "Miền Bắc — Thanh Hà"),
    ("mien-trung-mai-ngoc", "Miền Trung — Mai Ngọc"),
    ("mien-nam-phuong-ly", "Miền Nam — Phương Ly"),
)
DIGITS = ("không", "một", "hai", "ba", "bốn", "năm", "sáu", "bảy", "tám", "chín")


@dataclass(frozen=True)
class AssetSpec:
    asset_id: str
    text: str


def read_three_digits(value: int, force_hundreds: bool) -> str:
    if value < 0 or value > 999:
        raise ValueError("three-digit value must be in range 0..999")
    hundred, ten, unit = value // 100, (value % 100) // 10, value % 10
    parts: list[str] = []
    if hundred > 0:
        parts.extend((DIGITS[hundred], "trăm"))
    elif force_hundreds and (ten > 0 or unit > 0):
        parts.extend(("không", "trăm"))
    if ten > 1:
        parts.extend((DIGITS[ten], "mươi"))
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


def chunk_inventory() -> list[AssetSpec]:
    assets = [
        AssetSpec(
            f"chunk/leading/{value:03d}",
            "không" if value == 0 else read_three_digits(value, False),
        )
        for value in range(1_000)
    ]
    assets.extend(
        AssetSpec(f"chunk/forced/{value:03d}", read_three_digits(value, True))
        for value in range(1, 100)
    )
    assets.extend(
        AssetSpec(f"chunk/unit/{unit}", unit)
        for unit in ("nghìn", "triệu", "tỷ", "đồng")
    )
    if len(assets) != CHUNK_ASSET_COUNT:
        raise RuntimeError("Payment chunk grammar unexpectedly changed")
    return assets


def source_file_name(text: str) -> str:
    normalized = unicodedata.normalize("NFD", text.lower().replace("đ", "d"))
    normalized = "".join(
        character for character in normalized if not unicodedata.combining(character)
    )
    return re.sub(r"[^a-z0-9]+", "-", normalized).strip("-") + ".wav"


def safe_name(asset_id: str) -> str:
    return asset_id.replace("/", "__").replace(" ", "-") + ".wav"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def wav_metadata(path: Path) -> dict[str, int | str]:
    with wave.open(str(path), "rb") as audio:
        actual = (
            audio.getnchannels(),
            audio.getsampwidth(),
            audio.getframerate(),
            audio.getcomptype(),
        )
        expected = (CHANNELS, BITS_PER_SAMPLE // 8, SAMPLE_RATE_HZ, "NONE")
        if actual != expected:
            raise ValueError(f"Invalid PCM WAV format for {path}: {actual}")
        frames = audio.getnframes()
        pcm = audio.readframes(frames)
    if frames <= 0 or not any(pcm):
        raise ValueError(f"WAV has no audible PCM samples: {path}")
    samples = array.array("h")
    samples.frombytes(pcm)
    if samples.itemsize != 2:
        raise RuntimeError("Python host does not expose 16-bit array samples")
    if __import__("sys").byteorder != "little":
        samples.byteswap()
    if any(sample in {-32768, 32767} for sample in samples):
        raise ValueError(f"WAV reaches full scale and may clip when mixed: {path}")
    return {
        "bytes": path.stat().st_size,
        "sha256": sha256(path),
        "frames": frames,
        "durationMs": round(frames * 1000 / SAMPLE_RATE_HZ, 3),
    }


def build_manifest(
    preset_id: str,
    label: str,
    source: Path,
    destination: Path,
    specs: list[AssetSpec],
) -> dict[str, object]:
    expected_source = {PREFIX_FILE, PREFIX_SOURCE_FILE}
    expected_source.update(source_file_name(spec.text) for spec in specs)
    actual_source = {path.name for path in source.glob("*.wav") if path.is_file()}
    if actual_source != expected_source:
        missing = sorted(expected_source - actual_source)[:5]
        unexpected = sorted(actual_source - expected_source)[:5]
        raise ValueError(
            f"Source pack {preset_id} is not immutable/inventory-complete: "
            f"missing={missing} unexpected={unexpected}"
        )

    assets: list[dict[str, object]] = []
    source_by_id = [("prefix", PREFIX_FILE)] + [
        (spec.asset_id, source_file_name(spec.text)) for spec in specs
    ]
    for asset_id, source_name in source_by_id:
        source_path = source / source_name
        target_name = PREFIX_FILE if asset_id == "prefix" else safe_name(asset_id)
        target_path = destination / target_name
        metadata = wav_metadata(source_path)
        shutil.copy2(source_path, target_path)
        copied_metadata = wav_metadata(target_path)
        if copied_metadata != metadata:
            raise ValueError(f"Copied WAV metadata differs from source: {source_path}")
        assets.append({"id": asset_id, "file": target_name, **metadata})

    return {
        "schemaVersion": 2,
        "assetPackVersion": ASSET_PACK_VERSION,
        "voicePreset": {"id": preset_id, "label": label},
        "audioPolicy": {
            "packageSampleRate": SAMPLE_RATE_HZ,
            "channels": CHANNELS,
            "bitsPerSample": BITS_PER_SAMPLE,
            "sourceBoundaryTrimThresholdDbfs": -60,
            "internalAmountJoinGapMs": 0,
            "internalAmountCrossfadeMs": 50,
            "preserveFinalCurrencyTail": True,
            "cueToPhraseGapMs": 120,
            "prefixToAmountGapMs": 150,
        },
        "inventory": {
            "scheme": "chunk-0-999",
            "chunkAssetCount": CHUNK_ASSET_COUNT,
            "assetCount": len(assets),
        },
        "assets": assets,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    args = parser.parse_args()
    source_root = args.source_root.resolve()
    output_root = args.output_root.resolve()
    if not source_root.is_dir():
        raise ValueError(f"Source root does not exist: {source_root}")
    if output_root.exists():
        raise ValueError(f"Refusing to overwrite existing output root: {output_root}")

    specs = chunk_inventory()
    output_root.mkdir(parents=True)
    for preset_id, label in VOICE_PRESETS:
        source = source_root / preset_id
        destination = output_root / preset_id
        if not source.is_dir():
            raise ValueError(f"Source voice pack is missing: {source}")
        destination.mkdir()
        manifest = build_manifest(preset_id, label, source, destination, specs)
        (destination / "manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        (destination / "THIRD_PARTY_NOTICES.md").write_text(
            "# Payment speaker voice preset\n\n"
            "This immutable PCM WAV pack was supplied from the approved local "
            "OPS-43 TTS sample set. It contains no model, TTS runtime, or "
            "network dependency. Exact asset hashes and audio policy are in "
            "`manifest.json`.\n",
            encoding="utf-8",
        )
        print(json.dumps({"preset": preset_id, "assets": len(manifest["assets"])}))


if __name__ == "__main__":
    main()
