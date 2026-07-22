#!/usr/bin/env python3
"""Generate the three preset-voice samples used to select the OPS-11 voice."""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import numpy as np
import soundfile as sf
import soxr

import generate_vieneu_assets as spike


VOICES = ["Ngọc Linh", "Trúc Ly", "Phạm Tuyên"]
SAMPLE_TEXT = "Phong Vũ đã nhận một triệu hai trăm năm mươi nghìn đồng."


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--codec-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--threads", type=int, default=4)
    args = parser.parse_args()

    args.output.mkdir(parents=True, exist_ok=True)
    spike._init_worker(str(args.model_dir), str(args.codec_dir), str(args.output), args.threads)
    assert spike._WORKER_TTS is not None
    results = []
    for index, voice in enumerate(VOICES):
        started = time.perf_counter()
        spec = spike.AssetSpec(f"voice/{voice}", SAMPLE_TEXT, "voice", "candidate")
        attempts = []
        accepted = None
        for attempt, temperature in enumerate(spike.RETRY_TEMPERATURES, 1):
            seed = spike.generation_seed(spec.asset_id, attempt)
            np.random.seed(seed)
            audio = spike._WORKER_TTS.infer(
                SAMPLE_TEXT,
                voice=voice,
                temperature=temperature,
                top_k=spike.TOP_K,
                top_p=spike.TOP_P,
                repetition_penalty=spike.REPETITION_PENALTY,
                max_new_frames=spike.MAX_NEW_FRAMES,
                apply_watermark=False,
            )
            trimmed = spike.trim_audio(audio, spike.SAMPLE_RATE)
            reasons = spike.validate_candidate(spec, trimmed, spike.SAMPLE_RATE)
            attempts.append(
                {
                    "attempt": attempt,
                    "seed": seed,
                    "temperature": temperature,
                    "contentDurationMs": round(len(trimmed) * 1000 / spike.SAMPLE_RATE, 2),
                    "qcPassed": not reasons,
                    "qcReasons": reasons,
                }
            )
            if not reasons:
                accepted = trimmed
                break
        if accepted is None:
            raise SystemExit(f"QC rejected voice sample: {voice}")
        packaged = soxr.resample(
            accepted, spike.SAMPLE_RATE, spike.PACKAGE_SAMPLE_RATE, quality="HQ"
        )
        packaged = spike.add_boundary_silence(
            packaged,
            spike.PACKAGE_SAMPLE_RATE,
            leading_ms=spike.VOICE_BOUNDARY_SILENCE_MS,
            trailing_ms=spike.VOICE_BOUNDARY_SILENCE_MS,
        )
        path = args.output / f"{index + 1}-{voice.replace(' ', '-')}.wav"
        sf.write(path, packaged, spike.PACKAGE_SAMPLE_RATE, subtype="PCM_16")
        results.append(
            {
                "voice": voice,
                "text": SAMPLE_TEXT,
                "file": path.name,
                "durationMs": round(len(packaged) * 1000 / spike.PACKAGE_SAMPLE_RATE, 2),
                "contentDurationMs": spike.content_duration_ms(
                    packaged,
                    spike.PACKAGE_SAMPLE_RATE,
                    leading_ms=spike.VOICE_BOUNDARY_SILENCE_MS,
                    trailing_ms=spike.VOICE_BOUNDARY_SILENCE_MS,
                ),
                "attempts": attempts,
                "wallMs": round((time.perf_counter() - started) * 1000, 2),
            }
        )
        print(path, flush=True)
    (args.output / "manifest.json").write_text(
        json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8"
    )


if __name__ == "__main__":
    main()
