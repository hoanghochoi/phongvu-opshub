#!/usr/bin/env python3
"""Create the reviewed Windows runtime pack from a generated VieNeu corpus."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path


PACK_VERSION = "ngoc-linh-chunk-v4"
EXPECTED_ASSET_COUNT = 1_103


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    source_manifest_path = args.corpus / "manifest-all.json"
    source_manifest = json.loads(source_manifest_path.read_text(encoding="utf-8"))
    assets = [asset for asset in source_manifest["assets"] if asset["scheme"] == "chunk"]
    if len(assets) != EXPECTED_ASSET_COUNT:
        raise ValueError(f"expected {EXPECTED_ASSET_COUNT} chunk assets, found {len(assets)}")
    if args.output.exists() and any(args.output.iterdir()):
        raise FileExistsError(f"output must be empty: {args.output}")
    args.output.mkdir(parents=True, exist_ok=True)

    runtime_assets: list[dict[str, object]] = []
    for asset in assets:
        metadata = asset["formats"]["wav24"]
        source = args.corpus / metadata["path"]
        if not source.is_file():
            raise FileNotFoundError(source)
        digest = sha256(source)
        if digest != metadata["sha256"]:
            raise ValueError(f"source hash mismatch: {source}")
        destination = args.output / source.name
        shutil.copy2(source, destination)
        runtime_assets.append(
            {
                "id": asset["asset_id"],
                "text": asset["text"],
                "role": asset["role"],
                "file": source.name,
                "bytes": metadata["bytes"],
                "sha256": digest,
                "frames": metadata["frames"],
                "contentDurationMs": asset["qc"]["contentDurationMs"],
            }
        )

    manifest = {
        "schemaVersion": 1,
        "assetPackVersion": PACK_VERSION,
        "voice": source_manifest["generator"]["voice"],
        "generator": source_manifest["generator"],
        "audioPolicy": source_manifest["audioPolicy"],
        "license": source_manifest["license"],
        "inventory": {"scheme": "chunk-0-999", "assetCount": len(runtime_assets)},
        "supportedAmount": {"currency": "VND", "min": 1, "max": 999_999_999_999_999_999},
        "assets": runtime_assets,
    }
    (args.output / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    (args.output / "THIRD_PARTY_NOTICES.md").write_text(
        "# Third-party notices\n\n"
        "The speech assets in this directory were generated once for OpsHub using:\n\n"
        "- pnnbao97/VieNeu-TTS, Apache-2.0\n"
        "- pnnbao-ump/VieNeu-TTS-v3-Turbo, Apache-2.0\n"
        "- OpenMOSS-Team/MOSS-Audio-Tokenizer-Nano-ONNX\n\n"
        "Exact source, model and codec revisions are recorded in `manifest.json`.\n",
        encoding="utf-8",
    )
    print(f"pack={PACK_VERSION} assets={len(runtime_assets)} output={args.output}")


if __name__ == "__main__":
    main()
