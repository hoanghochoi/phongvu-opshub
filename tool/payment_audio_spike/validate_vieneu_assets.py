#!/usr/bin/env python3
"""Validate hashes, WAV policy and expected deliverable counts for an asset pack."""

from __future__ import annotations

import argparse
import hashlib
import json
import wave
from pathlib import Path

import numpy as np

import generate_vieneu_assets as spike


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--corpus-name", default="corpus-v4")
    parser.add_argument("--baseline-corpus-name", default="corpus-v3")
    parser.add_argument("--voice-corpus-name", default="corpus-v3")
    args = parser.parse_args()

    corpus = args.root / args.corpus_name
    manifest = json.loads((corpus / "manifest-all.json").read_text(encoding="utf-8"))
    expected_inventory = {"word": 21, "chunk": 1103, "total": 1124}
    if manifest["inventory"] != expected_inventory:
        raise ValueError(f"unexpected inventory: {manifest['inventory']}")
    expected_policy = {
        "assetLeadingSilenceMs": spike.ASSET_LEADING_SILENCE_MS,
        "assetTrailingSilenceMs": spike.ASSET_TRAILING_SILENCE_MS,
    }
    for key, value in expected_policy.items():
        if manifest["audioPolicy"].get(key) != value:
            raise ValueError(f"unexpected audio policy {key}: {manifest['audioPolicy'].get(key)}")

    checked_formats = 0
    for asset in manifest["assets"]:
        if not asset.get("qc", {}).get("passed"):
            raise ValueError(f"manifest contains failed QC asset: {asset['asset_id']}")
        spec = spike.AssetSpec(
            asset["asset_id"], asset["text"], asset["scheme"], asset["role"]
        )
        for metadata in asset["formats"].values():
            path = corpus / metadata["path"]
            if not path.is_file():
                raise FileNotFoundError(path)
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            if digest != metadata["sha256"]:
                raise ValueError(f"hash mismatch: {path}")
            with wave.open(str(path), "rb") as wav:
                actual = (wav.getnchannels(), wav.getsampwidth() * 8, wav.getframerate())
            expected = (1, 16, metadata["sampleRate"])
            if actual != expected:
                raise ValueError(f"WAV policy mismatch: {path}: {actual}")
            rate, samples = spike.read_pcm16(path)
            reasons = spike.validate_stored_asset(spec, samples, rate)
            if reasons:
                raise ValueError(f"stored asset QC failed: {path}: {reasons}")
            leading_frames = round(rate * spike.ASSET_LEADING_SILENCE_MS / 1000)
            trailing_frames = round(rate * spike.ASSET_TRAILING_SILENCE_MS / 1000)
            if np.any(samples[:leading_frames]) or np.any(samples[-trailing_frames:]):
                raise ValueError(f"non-silent asset boundary: {path}")
            checked_formats += 1

    listening_files = list(
        (args.root / f"{args.corpus_name}-listening-pack").glob("*.wav")
    )
    voice_files = list((args.root / f"{args.voice_corpus_name}-voice-samples").glob("*.wav"))
    listening_count = len(listening_files)
    voice_count = len(voice_files)
    if listening_count != 30 or voice_count != 3:
        raise ValueError(
            f"deliverable count mismatch: listening={listening_count}, voices={voice_count}"
        )
    for path in listening_files:
        rate, samples = spike.read_pcm16(path)
        edge_frames = round(rate * spike.COMPOSE_BOUNDARY_SILENCE_MS / 1000)
        if np.any(samples[:edge_frames]) or np.any(samples[-edge_frames:]):
            raise ValueError(f"composed A/B file has clipped boundary: {path}")
        baseline = args.root / f"{args.baseline_corpus_name}-listening-pack" / path.name
        if not baseline.is_file() or hashlib.sha256(path.read_bytes()).digest() != hashlib.sha256(
            baseline.read_bytes()
        ).digest():
            raise ValueError(f"composed A/B file changed from baseline: {path}")
    for path in voice_files:
        rate, samples = spike.read_pcm16(path)
        edge_frames = round(rate * spike.VOICE_BOUNDARY_SILENCE_MS / 1000)
        if np.any(samples[:edge_frames]) or np.any(samples[-edge_frames:]):
            raise ValueError(f"voice sample has clipped boundary: {path}")
    benchmark = json.loads(
        (args.root / f"benchmark-{args.corpus_name}.json").read_text(encoding="utf-8")
    )
    outliers = sum(item["outlierCount"] for item in benchmark["quality"].values())
    if outliers:
        raise ValueError(f"benchmark contains {outliers} duration outlier(s)")
    print(
        f"validated_assets={len(manifest['assets'])} "
        f"validated_formats={checked_formats} listening_unchanged={listening_count} "
        f"voices_unchanged={voice_count}"
    )


if __name__ == "__main__":
    main()
