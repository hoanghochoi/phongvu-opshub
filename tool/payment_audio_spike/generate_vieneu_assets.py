#!/usr/bin/env python3
"""Generate and benchmark the OPS-11 VieNeu offline payment asset spike.

Large generated audio is written below an ignored artifacts directory. This file
contains the reproducible inventory/grammar and records exact upstream pins in
the generated manifest.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import multiprocessing as mp
import os
import random
import shutil
import statistics
import struct
import time
import wave
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable, Sequence

import numpy as np
import soundfile as sf
import soxr

VIENEU_VERSION = "3.2.3"
VIENEU_GIT_COMMIT = "f56ce97ffb3731aeafed623391587a1589ecb501"
MODEL_REPO = "pnnbao-ump/VieNeu-TTS-v3-Turbo"
MODEL_REVISION = "75ff82a72f54d55ed389e1eeb12041d3c4bac7d4"
CODEC_REPO = "OpenMOSS-Team/MOSS-Audio-Tokenizer-Nano-ONNX"
CODEC_REVISION = "ceff0d0749bfb3fa2d61149794ec6feef0d1e1ae"
SAMPLE_RATE = 48_000
PACKAGE_SAMPLE_RATE = 24_000
VOICE = "Ngọc Linh"
TEMPERATURE = 0.65
RETRY_TEMPERATURES = [0.65, 0.8, 0.95, 0.5, 0.75, 1.0, 0.4, 0.85, 0.6, 0.3, 0.9, 0.2]
TOP_K = 25
TOP_P = 0.95
REPETITION_PENALTY = 1.2
MAX_NEW_FRAMES = 48
TRIM_THRESHOLD_DB = -65.0
TRIM_PADDING_MS = 20
ASSET_LEADING_SILENCE_MS = 300
ASSET_TRAILING_SILENCE_MS = 200
VOICE_BOUNDARY_SILENCE_MS = 120
COMPOSE_BOUNDARY_SILENCE_MS = 30
JOIN_GAP_MS = 45
OUTLIER_DURATION_MS = 3_000
MIN_CONTENT_DURATION_MS = 180
LISTENING_AMOUNTS = [
    1,
    4,
    5,
    15,
    21,
    24,
    25,
    101,
    105,
    1_005,
    21_005,
    105_000,
    1_250_000,
    21_000_005,
    999_999_999,
]

DIGITS = ["không", "một", "hai", "ba", "bốn", "năm", "sáu", "bảy", "tám", "chín"]
GROUP_UNITS = ["", "nghìn", "triệu", "tỷ", "nghìn tỷ", "triệu tỷ"]


@dataclass(frozen=True)
class AssetSpec:
    asset_id: str
    text: str
    scheme: str
    role: str


def read_three_digits(value: int, force_hundreds: bool) -> str:
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
    if amount <= 0:
        return str(amount)
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


def word_inventory() -> list[AssetSpec]:
    tokens = sorted(
        {
            *DIGITS,
            "trăm",
            "mười",
            "mươi",
            "mốt",
            "tư",
            "lăm",
            "lẻ",
            "nghìn",
            "triệu",
            "tỷ",
            "đồng",
        }
    )
    return [AssetSpec(f"word/token/{token}", token, "word", "token") for token in tokens]


def chunk_inventory() -> list[AssetSpec]:
    assets = [
        AssetSpec(
            f"chunk/leading/{value:03d}",
            "không" if value == 0 else read_three_digits(value, False),
            "chunk",
            "leading-group",
        )
        for value in range(1000)
    ]
    assets.extend(
        AssetSpec(
            f"chunk/forced/{value:03d}",
            read_three_digits(value, True),
            "chunk",
            "forced-group",
        )
        for value in range(1, 100)
    )
    assets.extend(
        AssetSpec(f"chunk/unit/{unit.replace(' ', '-')}", unit, "chunk", "scale-unit")
        for unit in ["nghìn", "triệu", "tỷ", "đồng"]
    )
    return assets


def amount_word_asset_ids(amount: int) -> list[str]:
    return [f"word/token/{token}" for token in vietnamese_amount_words(amount).split()] + ["word/token/đồng"]


def amount_chunk_asset_ids(amount: int) -> list[str]:
    if amount <= 0:
        raise ValueError("amount must be positive")
    groups: list[int] = []
    remaining = amount
    while remaining > 0:
        groups.append(remaining % 1000)
        remaining //= 1000
    if len(groups) > len(GROUP_UNITS):
        raise ValueError("amount exceeds supported group units")
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


def trim_audio(audio: np.ndarray, sample_rate: int) -> np.ndarray:
    mono = np.asarray(audio, dtype=np.float32).reshape(-1)
    threshold = 10 ** (TRIM_THRESHOLD_DB / 20.0)
    active = np.flatnonzero(np.abs(mono) >= threshold)
    if not active.size:
        return mono
    pad = int(sample_rate * TRIM_PADDING_MS / 1000)
    start = max(0, int(active[0]) - pad)
    end = min(len(mono), int(active[-1]) + pad + 1)
    return mono[start:end]


def add_boundary_silence(
    audio: np.ndarray,
    sample_rate: int,
    leading_ms: int = ASSET_LEADING_SILENCE_MS,
    trailing_ms: int = ASSET_TRAILING_SILENCE_MS,
) -> np.ndarray:
    leading = np.zeros(round(sample_rate * leading_ms / 1000), dtype=np.float32)
    trailing = np.zeros(round(sample_rate * trailing_ms / 1000), dtype=np.float32)
    return np.concatenate([leading, np.asarray(audio, dtype=np.float32), trailing])


def strip_boundary_silence(samples: np.ndarray, sample_rate: int) -> np.ndarray:
    stored_leading_frames = round(sample_rate * ASSET_LEADING_SILENCE_MS / 1000)
    stored_trailing_frames = round(sample_rate * ASSET_TRAILING_SILENCE_MS / 1000)
    keep_frames = round(sample_rate * COMPOSE_BOUNDARY_SILENCE_MS / 1000)
    removable_leading = stored_leading_frames - keep_frames
    removable_trailing = stored_trailing_frames - keep_frames
    if removable_leading < 0 or removable_trailing < 0:
        raise ValueError("compose boundary cannot exceed stored asset boundary")
    if len(samples) <= removable_leading + removable_trailing:
        raise ValueError("asset is shorter than its removable boundary guards")
    if np.any(samples[:removable_leading]) or np.any(samples[-removable_trailing:]):
        raise ValueError("asset boundary guard is missing or corrupt")
    end = len(samples) - removable_trailing if removable_trailing else len(samples)
    return samples[removable_leading:end]


def remove_stored_boundary_silence(
    samples: np.ndarray,
    sample_rate: int,
    leading_ms: int = ASSET_LEADING_SILENCE_MS,
    trailing_ms: int = ASSET_TRAILING_SILENCE_MS,
) -> np.ndarray:
    leading_frames = round(sample_rate * leading_ms / 1000)
    trailing_frames = round(sample_rate * trailing_ms / 1000)
    if len(samples) <= leading_frames + trailing_frames:
        raise ValueError("asset is shorter than its boundary guards")
    if np.any(samples[:leading_frames]) or np.any(samples[-trailing_frames:]):
        raise ValueError("asset boundary guard is missing or corrupt")
    end = len(samples) - trailing_frames if trailing_frames else len(samples)
    return samples[leading_frames:end]


def expected_max_content_duration_ms(text: str) -> int:
    word_count = max(1, len(text.split()))
    return 1_800 + 250 * (word_count - 1)


def content_duration_ms(
    samples: np.ndarray,
    sample_rate: int,
    leading_ms: int = ASSET_LEADING_SILENCE_MS,
    trailing_ms: int = ASSET_TRAILING_SILENCE_MS,
) -> float:
    guard_frames = round(sample_rate * (leading_ms + trailing_ms) / 1000)
    content_frames = max(0, len(samples) - guard_frames)
    return round(content_frames * 1000 / sample_rate, 2)


def generation_seed(asset_id: str, attempt: int) -> int:
    digest = hashlib.sha256(f"{asset_id}:{attempt}".encode("utf-8")).digest()
    return int.from_bytes(digest[:4], "big")


def validate_candidate(spec: AssetSpec, audio: np.ndarray, sample_rate: int) -> list[str]:
    duration_ms = round(len(audio) * 1000 / sample_rate, 2)
    reasons = []
    if duration_ms < MIN_CONTENT_DURATION_MS:
        reasons.append("too_short")
    if duration_ms > expected_max_content_duration_ms(spec.text):
        reasons.append("too_long")
    if not np.isfinite(audio).all():
        reasons.append("non_finite")
    if audio.size == 0 or float(np.max(np.abs(audio), initial=0.0)) < 0.001:
        reasons.append("silent")
    return reasons


_WORKER_TTS = None
_WORKER_MODEL_DIR: Path | None = None
_WORKER_CODEC_DIR: Path | None = None
_WORKER_OUTPUT: Path | None = None
_WORKER_REGENERATE = False


def _init_worker(
    model_dir: str, codec_dir: str, output: str, threads: int, regenerate: bool = False
) -> None:
    global _WORKER_TTS, _WORKER_MODEL_DIR, _WORKER_CODEC_DIR, _WORKER_OUTPUT, _WORKER_REGENERATE
    from vieneu import Vieneu
    from vieneu._v3_turbo_engine.onnx_runtime_lite import OnnxV3LiteEngine

    _WORKER_MODEL_DIR = Path(model_dir)
    _WORKER_CODEC_DIR = Path(codec_dir)
    _WORKER_OUTPUT = Path(output)
    _WORKER_REGENERATE = regenerate
    original_fetch = OnnxV3LiteEngine._fetch

    def local_fetch(repo: str, files: list[str], subfolder: str | None) -> Path:
        if repo == CODEC_REPO:
            return _WORKER_CODEC_DIR
        return original_fetch(repo, files, subfolder)

    OnnxV3LiteEngine._fetch = staticmethod(local_fetch)
    _WORKER_TTS = Vieneu(
        backend="onnx",
        precision="int8",
        threads=threads,
        onnx_dir=str(_WORKER_MODEL_DIR),
        backbone_repo=str(_WORKER_MODEL_DIR.parent),
    )


def _generate_one(spec_dict: dict) -> dict:
    spec = AssetSpec(**spec_dict)
    assert _WORKER_TTS is not None and _WORKER_OUTPUT is not None
    path48 = _WORKER_OUTPUT / spec.scheme / "wav48" / f"{safe_name(spec.asset_id)}.wav"
    path24 = _WORKER_OUTPUT / spec.scheme / "wav24" / f"{safe_name(spec.asset_id)}.wav"
    if path48.exists() and path24.exists() and not _WORKER_REGENERATE:
        sample_rate, samples = read_pcm16(path24)
        reasons = validate_stored_asset(spec, samples, sample_rate)
        return {
            "asset_id": spec.asset_id,
            "status": "cached" if not reasons else "rejected",
            "duration_ms": wav_duration_ms(path24),
            "content_duration_ms": content_duration_ms(samples, sample_rate),
            "qc_passed": not reasons,
            "qc_reasons": reasons,
            "attempts": [],
        }
    path48.parent.mkdir(parents=True, exist_ok=True)
    path24.parent.mkdir(parents=True, exist_ok=True)
    started = time.perf_counter()
    attempts = []
    accepted48 = None
    for attempt, temperature in enumerate(RETRY_TEMPERATURES, 1):
        seed = generation_seed(spec.asset_id, attempt)
        np.random.seed(seed)
        audio = _WORKER_TTS.infer(
            spec.text + ".",
            voice=VOICE,
            temperature=temperature,
            top_k=TOP_K,
            top_p=TOP_P,
            repetition_penalty=REPETITION_PENALTY,
            max_new_frames=MAX_NEW_FRAMES,
            apply_watermark=False,
        )
        trimmed48 = trim_audio(audio, SAMPLE_RATE)
        reasons = validate_candidate(spec, trimmed48, SAMPLE_RATE)
        attempts.append(
            {
                "attempt": attempt,
                "seed": seed,
                "temperature": temperature,
                "content_duration_ms": round(len(trimmed48) * 1000 / SAMPLE_RATE, 2),
                "qc_passed": not reasons,
                "qc_reasons": reasons,
            }
        )
        if not reasons:
            accepted48 = trimmed48
            break
    if accepted48 is None:
        return {
            "asset_id": spec.asset_id,
            "status": "rejected",
            "qc_passed": False,
            "qc_reasons": sorted({reason for item in attempts for reason in item["qc_reasons"]}),
            "attempts": attempts,
            "wall_ms": round((time.perf_counter() - started) * 1000, 2),
        }
    sf.write(
        path48,
        add_boundary_silence(accepted48, SAMPLE_RATE),
        SAMPLE_RATE,
        subtype="PCM_16",
    )
    audio24 = soxr.resample(accepted48, SAMPLE_RATE, PACKAGE_SAMPLE_RATE, quality="HQ")
    audio24 = add_boundary_silence(audio24, PACKAGE_SAMPLE_RATE)
    sf.write(path24, audio24, PACKAGE_SAMPLE_RATE, subtype="PCM_16")
    return {
        "asset_id": spec.asset_id,
        "status": "generated",
        "duration_ms": round(len(audio24) * 1000 / PACKAGE_SAMPLE_RATE, 2),
        "content_duration_ms": content_duration_ms(audio24, PACKAGE_SAMPLE_RATE),
        "qc_passed": True,
        "qc_reasons": [],
        "attempts": attempts,
        "wall_ms": round((time.perf_counter() - started) * 1000, 2),
    }


def wav_duration_ms(path: Path) -> float:
    with wave.open(str(path), "rb") as wav:
        return round(wav.getnframes() * 1000 / wav.getframerate(), 2)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def generate_assets(
    specs: Sequence[AssetSpec],
    model_dir: Path,
    codec_dir: Path,
    output: Path,
    workers: int,
    threads: int,
    regenerate: bool = False,
) -> list[dict]:
    context = mp.get_context("spawn")
    results: list[dict] = []
    with context.Pool(
        processes=workers,
        initializer=_init_worker,
        initargs=(str(model_dir), str(codec_dir), str(output), threads, regenerate),
    ) as pool:
        for index, result in enumerate(pool.imap_unordered(_generate_one, map(asdict, specs)), 1):
            results.append(result)
            if index % 25 == 0 or index == len(specs):
                print(f"generated {index}/{len(specs)}", flush=True)
    return results


def repackage_assets(specs: Sequence[AssetSpec], corpus: Path) -> None:
    for spec in specs:
        source = corpus / spec.scheme / "wav48" / f"{safe_name(spec.asset_id)}.wav"
        destination = corpus / spec.scheme / "wav24" / f"{safe_name(spec.asset_id)}.wav"
        rate, stored = read_pcm16(source)
        if rate != SAMPLE_RATE:
            raise ValueError(f"source sample rate mismatch: {source}")
        content = remove_stored_boundary_silence(stored, rate).astype(np.float32) / 32768.0
        packaged = soxr.resample(content, SAMPLE_RATE, PACKAGE_SAMPLE_RATE, quality="HQ")
        packaged = add_boundary_silence(packaged, PACKAGE_SAMPLE_RATE)
        sf.write(destination, packaged, PACKAGE_SAMPLE_RATE, subtype="PCM_16")


def migrate_corpus_assets(
    specs: Sequence[AssetSpec],
    source_corpus: Path,
    destination_corpus: Path,
    source_leading_ms: int,
    source_trailing_ms: int,
) -> None:
    if source_corpus.resolve() == destination_corpus.resolve():
        raise ValueError("source and destination corpus must be different")
    for spec in specs:
        for format_name, expected_rate in [
            ("wav48", SAMPLE_RATE),
            ("wav24", PACKAGE_SAMPLE_RATE),
        ]:
            relative = Path(spec.scheme) / format_name / f"{safe_name(spec.asset_id)}.wav"
            source = source_corpus / relative
            rate, stored = read_pcm16(source)
            if rate != expected_rate:
                raise ValueError(f"source sample rate mismatch: {source}")
            content = remove_stored_boundary_silence(
                stored,
                rate,
                leading_ms=source_leading_ms,
                trailing_ms=source_trailing_ms,
            )
            guarded = add_boundary_silence(
                content.astype(np.float32) / 32768.0,
                rate,
            )
            write_pcm16(
                destination_corpus / relative,
                rate,
                np.round(guarded * 32768).astype(np.int16),
            )
    for scheme in ["word", "chunk", "all"]:
        source_results = source_corpus / f"generation-results-{scheme}.json"
        if source_results.is_file():
            destination_corpus.mkdir(parents=True, exist_ok=True)
            shutil.copy2(
                source_results,
                destination_corpus / source_results.name,
            )


def read_pcm16(path: Path) -> tuple[int, np.ndarray]:
    with wave.open(str(path), "rb") as wav:
        if wav.getnchannels() != 1 or wav.getsampwidth() != 2:
            raise ValueError(f"unsupported WAV format: {path}")
        rate = wav.getframerate()
        data = np.frombuffer(wav.readframes(wav.getnframes()), dtype="<i2").copy()
    return rate, data


def write_pcm16(path: Path, rate: int, samples: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(rate)
        wav.writeframes(np.asarray(samples, dtype="<i2").tobytes())


def validate_stored_asset(spec: AssetSpec, samples: np.ndarray, sample_rate: int) -> list[str]:
    reasons = []
    leading_frames = round(sample_rate * ASSET_LEADING_SILENCE_MS / 1000)
    trailing_frames = round(sample_rate * ASSET_TRAILING_SILENCE_MS / 1000)
    if len(samples) <= leading_frames + trailing_frames:
        return ["too_short", "missing_boundary_guard"]
    if np.any(samples[:leading_frames]) or np.any(samples[-trailing_frames:]):
        reasons.append("missing_boundary_guard")
    content = samples[leading_frames:-trailing_frames]
    reasons.extend(validate_candidate(spec, content.astype(np.float32) / 32768.0, sample_rate))
    return sorted(set(reasons))


def compose(asset_ids: Sequence[str], scheme: str, output: Path, corpus: Path) -> dict:
    arrays: list[np.ndarray] = []
    rate = PACKAGE_SAMPLE_RATE
    gap = np.zeros(round(rate * JOIN_GAP_MS / 1000), dtype=np.int16)
    boundary_deltas: list[int] = []
    for index, asset_id in enumerate(asset_ids):
        path = corpus / scheme / "wav24" / f"{safe_name(asset_id)}.wav"
        sample_rate, samples = read_pcm16(path)
        if sample_rate != rate:
            raise ValueError(f"sample rate mismatch: {path}")
        samples = strip_boundary_silence(samples, sample_rate)
        if arrays and arrays[-1].size and samples.size:
            boundary_deltas.append(abs(int(arrays[-1][-1]) - int(samples[0])))
            arrays.append(gap)
        arrays.append(samples)
    combined = np.concatenate(arrays) if arrays else np.zeros(0, dtype=np.int16)
    write_pcm16(output, rate, combined)
    return {
        "duration_ms": round(len(combined) * 1000 / rate, 2),
        "mean_boundary_delta": round(statistics.fmean(boundary_deltas), 2) if boundary_deltas else 0,
        "token_count": len(asset_ids),
    }


def create_listening_pack(corpus: Path, output: Path) -> list[dict]:
    spec_by_id = {spec.asset_id: spec for spec in word_inventory() + chunk_inventory()}
    required_ids = set()
    for amount in LISTENING_AMOUNTS:
        required_ids.update(amount_word_asset_ids(amount))
        required_ids.update(amount_chunk_asset_ids(amount))
    failures = []
    for asset_id in sorted(required_ids):
        spec = spec_by_id[asset_id]
        path = corpus / spec.scheme / "wav24" / f"{safe_name(asset_id)}.wav"
        if not path.exists():
            failures.append(f"{asset_id}:missing")
            continue
        rate, samples = read_pcm16(path)
        reasons = validate_stored_asset(spec, samples, rate)
        if reasons:
            failures.append(f"{asset_id}:{','.join(reasons)}")
    if failures:
        raise ValueError("listening pack blocked by QC: " + "; ".join(failures))
    output.mkdir(parents=True, exist_ok=True)
    mapping: list[dict] = []
    for amount in LISTENING_AMOUNTS:
        candidates = [
            ("word", amount_word_asset_ids(amount)),
            ("chunk", amount_chunk_asset_ids(amount)),
        ]
        random.Random(amount).shuffle(candidates)
        for label_index, (scheme, asset_ids) in enumerate(candidates):
            blind_label = "A" if label_index == 0 else "B"
            path = output / f"{amount:015d}-{blind_label}.wav"
            metrics = compose(asset_ids, scheme, path, corpus)
            mapping.append(
                {
                    "amount": amount,
                    "blind_label": blind_label,
                    "scheme": scheme,
                    "text": vietnamese_amount_words(amount) + " đồng",
                    "file": path.name,
                    **metrics,
                }
            )
    (output / "blind-map.json").write_text(json.dumps(mapping, ensure_ascii=False, indent=2), encoding="utf-8")
    (output / "README.md").write_text(
        "# OPS-11 blind A/B listening pack\n\n"
        "Nghe từng cặp có cùng số tiền, không mở `blind-map.json` trước khi chấm. "
        "Chấm 1–5 cho: tự nhiên, rõ số tiền, độ liền mạch và mức khó chịu tại điểm nối.\n\n"
        "Sau khi chấm xong, dùng `blind-map.json` để giải mù. Corpus có chủ đích giữ "
        "nguyên các output lỗi/lặp nhằm đo tỷ lệ QC thật của từng phương án.\n",
        encoding="utf-8",
    )
    return mapping


def quality_summary(specs: Sequence[AssetSpec], corpus: Path) -> dict:
    summary: dict[str, dict] = {}
    for scheme in sorted({spec.scheme for spec in specs}):
        durations = []
        outliers = []
        for spec in (item for item in specs if item.scheme == scheme):
            path = corpus / scheme / "wav24" / f"{safe_name(spec.asset_id)}.wav"
            rate, samples = read_pcm16(path)
            duration_ms = content_duration_ms(samples, rate)
            durations.append(duration_ms)
            if duration_ms > OUTLIER_DURATION_MS:
                outliers.append(
                    {"assetId": spec.asset_id, "text": spec.text, "durationMs": duration_ms}
                )
        summary[scheme] = {
            "assetCount": len(durations),
            "meanDurationMs": round(statistics.fmean(durations), 2),
            "p95DurationMs": round(float(np.percentile(durations, 95)), 2),
            "maxDurationMs": round(max(durations), 2),
            "outlierThresholdMs": OUTLIER_DURATION_MS,
            "outlierCount": len(outliers),
            "outlierRatePercent": round(len(outliers) * 100 / len(durations), 3),
            "outliers": sorted(outliers, key=lambda item: item["durationMs"], reverse=True),
        }
    return summary


def build_manifest(specs: Sequence[AssetSpec], corpus: Path, results: Sequence[dict]) -> dict:
    results_by_id = {item["asset_id"]: item for item in results}
    entries: list[dict] = []
    for spec in specs:
        formats = {}
        for format_name in ["wav48", "wav24"]:
            path = corpus / spec.scheme / format_name / f"{safe_name(spec.asset_id)}.wav"
            with wave.open(str(path), "rb") as wav:
                formats[format_name] = {
                    "path": path.relative_to(corpus).as_posix(),
                    "bytes": path.stat().st_size,
                    "sha256": sha256(path),
                    "sampleRate": wav.getframerate(),
                    "channels": wav.getnchannels(),
                    "bitsPerSample": wav.getsampwidth() * 8,
                    "frames": wav.getnframes(),
                }
        result = results_by_id[spec.asset_id]
        entries.append(
            {
                **asdict(spec),
                "qc": {
                    "passed": result.get("qc_passed", False),
                    "contentDurationMs": result.get("content_duration_ms"),
                    "attempts": result.get("attempts", []),
                },
                "formats": formats,
            }
        )
    generated_wall = [item["wall_ms"] for item in results if "wall_ms" in item]
    return {
        "assetPackVersion": "ops-11-spike-v4",
        "generator": {
            "vieneuVersion": VIENEU_VERSION,
            "vieneuGitCommit": VIENEU_GIT_COMMIT,
            "modelRepo": MODEL_REPO,
            "modelRevision": MODEL_REVISION,
            "codecRepo": CODEC_REPO,
            "codecRevision": CODEC_REVISION,
            "backend": "onnx-int8-cpu",
            "voice": VOICE,
            "temperature": TEMPERATURE,
            "retryTemperatures": RETRY_TEMPERATURES,
            "topK": TOP_K,
            "topP": TOP_P,
            "repetitionPenalty": REPETITION_PENALTY,
            "maxNewFrames": MAX_NEW_FRAMES,
            "watermark": False,
        },
        "audioPolicy": {
            "sourceSampleRate": SAMPLE_RATE,
            "packageSampleRate": PACKAGE_SAMPLE_RATE,
            "channels": 1,
            "bitsPerSample": 16,
            "trimThresholdDb": TRIM_THRESHOLD_DB,
            "trimPaddingMs": TRIM_PADDING_MS,
            "assetLeadingSilenceMs": ASSET_LEADING_SILENCE_MS,
            "assetTrailingSilenceMs": ASSET_TRAILING_SILENCE_MS,
            "composeBoundarySilenceMs": COMPOSE_BOUNDARY_SILENCE_MS,
            "joinGapMs": JOIN_GAP_MS,
        },
        "inventory": {
            "word": len([item for item in specs if item.scheme == "word"]),
            "chunk": len([item for item in specs if item.scheme == "chunk"]),
            "total": len(specs),
        },
        "generation": {
            "generatedCount": len(generated_wall),
            "cachedCount": len(results) - len(generated_wall),
            "attemptCount": sum(len(item.get("attempts", [])) for item in results),
            "retriedAssetCount": len([item for item in results if len(item.get("attempts", [])) > 1]),
            "meanWallMs": round(statistics.fmean(generated_wall), 2) if generated_wall else None,
            "p95WallMs": round(float(np.percentile(generated_wall, 95)), 2) if generated_wall else None,
        },
        "license": {
            "spdx": "Apache-2.0",
            "attribution": ["pnnbao97/VieNeu-TTS", MODEL_REPO, CODEC_REPO],
        },
        "assets": entries,
    }


def zip_size(source: Path, destination_without_suffix: Path) -> int:
    archive = shutil.make_archive(str(destination_without_suffix), "zip", root_dir=source)
    return Path(archive).stat().st_size


def benchmark_composition(corpus: Path, iterations: int = 50) -> dict:
    measurements: dict[str, list[float]] = {"word": [], "chunk": []}
    amounts = LISTENING_AMOUNTS * ((iterations + len(LISTENING_AMOUNTS) - 1) // len(LISTENING_AMOUNTS))
    bench_dir = corpus.parent / "benchmark-temp"
    for scheme in ["word", "chunk"]:
        for index, amount in enumerate(amounts[:iterations]):
            ids = amount_word_asset_ids(amount) if scheme == "word" else amount_chunk_asset_ids(amount)
            started = time.perf_counter()
            compose(ids, scheme, bench_dir / f"{scheme}-{index}.wav", corpus)
            measurements[scheme].append((time.perf_counter() - started) * 1000)
    return {
        scheme: {
            "iterations": len(values),
            "meanMs": round(statistics.fmean(values), 3),
            "p95Ms": round(float(np.percentile(values, 95)), 3),
            "maxMs": round(max(values), 3),
        }
        for scheme, values in measurements.items()
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-dir", type=Path)
    parser.add_argument("--codec-dir", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--scheme", choices=["word", "chunk", "all"], default="all")
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--threads", type=int, default=2)
    parser.add_argument("--limit", type=int)
    parser.add_argument("--regenerate", action="store_true")
    parser.add_argument("--repackage-only", action="store_true")
    parser.add_argument(
        "--migrate-from",
        type=Path,
        help="Copy accepted speech from an older corpus and replace only its boundary guards.",
    )
    parser.add_argument("--source-leading-silence-ms", type=int, default=120)
    parser.add_argument("--source-trailing-silence-ms", type=int, default=120)
    parser.add_argument(
        "--postprocess-only",
        action="store_true",
        help="Build manifests, listening pack and benchmarks from an existing corpus.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    specs: list[AssetSpec] = []
    if args.scheme in ["word", "all"]:
        specs.extend(word_inventory())
    if args.scheme in ["chunk", "all"]:
        specs.extend(chunk_inventory())
    if args.limit:
        specs = specs[: args.limit]
    args.output.mkdir(parents=True, exist_ok=True)
    if args.migrate_from is not None:
        migrate_corpus_assets(
            specs,
            args.migrate_from,
            args.output,
            args.source_leading_silence_ms,
            args.source_trailing_silence_ms,
        )
        args.postprocess_only = True
        print(f"migrated {len(specs)} asset(s) from {args.migrate_from}", flush=True)
    if args.repackage_only:
        repackage_assets(specs, args.output)
        print(f"repackaged {len(specs)} asset(s)", flush=True)
        return
    started = time.perf_counter()
    if args.postprocess_only:
        prior_results = {}
        for scheme in ["word", "chunk"]:
            path = args.output / f"generation-results-{scheme}.json"
            if path.exists():
                for item in json.loads(path.read_text(encoding="utf-8")):
                    prior_results[item["asset_id"]] = item
        results = []
        for spec in specs:
            path = args.output / spec.scheme / "wav24" / f"{safe_name(spec.asset_id)}.wav"
            rate, samples = read_pcm16(path)
            reasons = validate_stored_asset(spec, samples, rate)
            results.append(
                {
                    "asset_id": spec.asset_id,
                    "status": "cached" if not reasons else "rejected",
                    "duration_ms": wav_duration_ms(path),
                    "content_duration_ms": content_duration_ms(samples, rate),
                    "qc_passed": not reasons,
                    "qc_reasons": reasons,
                    "attempts": prior_results.get(spec.asset_id, {}).get("attempts", []),
                }
            )
    else:
        if args.model_dir is None or args.codec_dir is None:
            raise SystemExit("--model-dir and --codec-dir are required unless --postprocess-only is used")
        results = generate_assets(
            specs,
            args.model_dir,
            args.codec_dir,
            args.output,
            args.workers,
            args.threads,
            args.regenerate,
        )
    attempts_path = args.output / f"generation-results-{args.scheme}.json"
    attempts_path.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    rejected = [item for item in results if not item.get("qc_passed", False)]
    if rejected:
        rejected_ids = ", ".join(item["asset_id"] for item in rejected)
        raise SystemExit(f"QC rejected {len(rejected)} asset(s): {rejected_ids}")
    manifest = build_manifest(specs, args.output, results)
    manifest["generation"]["totalWallSeconds"] = round(time.perf_counter() - started, 2)
    manifest_path = args.output / f"manifest-{args.scheme}.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    if args.scheme == "all" and not args.limit:
        listening = create_listening_pack(
            args.output, args.output.parent / f"{args.output.name}-listening-pack"
        )
        benchmark = benchmark_composition(args.output)
        sizes = {
            scheme: {
                fmt: sum(path.stat().st_size for path in (args.output / scheme / fmt).glob("*.wav"))
                for fmt in ["wav48", "wav24"]
            }
            for scheme in ["word", "chunk"]
        }
        sizes["word"]["zip24"] = zip_size(
            args.output / "word" / "wav24", args.output.parent / f"{args.output.name}-word-wav24"
        )
        sizes["chunk"]["zip24"] = zip_size(
            args.output / "chunk" / "wav24", args.output.parent / f"{args.output.name}-chunk-wav24"
        )
        report = {
            "sizes": sizes,
            "quality": quality_summary(specs, args.output),
            "composition": benchmark,
            "listening": listening,
        }
        (args.output.parent / f"benchmark-{args.output.name}.json").write_text(
            json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
        )
    print(manifest_path, flush=True)


if __name__ == "__main__":
    mp.freeze_support()
    main()
