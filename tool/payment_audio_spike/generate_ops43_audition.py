#!/usr/bin/env python3
"""Build OPS-43 prefix and audition WAVs from immutable local voice assets.

The deployed cue already exists in ``data/payment-cue-prefix.wav`` as PCM16
mono 22,050 Hz. This tool extracts its first cue section instead of decoding
the source MP3 again, preserving the deployed gain and waveform for listening
QA. It never regenerates speech with TTS and refuses incompatible WAV input.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import wave
from dataclasses import dataclass
from pathlib import Path

import numpy as np


@dataclass(frozen=True)
class AuditionSpec:
    file_stem: str
    amount_label: str
    asset_files: tuple[str, ...]


SAMPLE_RATE_HZ = 22_050
BITS_PER_SAMPLE = 16
CHANNELS = 1
SILENCE_THRESHOLD = 33  # -60 dBFS rounded to signed PCM16.
DETECTION_WINDOW_MS = 10
MIN_CUE_FOLLOWING_SILENCE_MS = 300
VOICE_PACKS = (
    "mien-bac-thanh-ha",
    "mien-trung-mai-ngoc",
    "mien-nam-phuong-ly",
)
PREFIX_PHRASE_FILE = "phong-vu-da-nhan.wav"
AUDITION_SPECS = (
    AuditionSpec(
        file_stem="payment-123000",
        amount_label="123.000 đồng",
        asset_files=(
            "mot-tram-hai-muoi-ba.wav",
            "nghin.wav",
            "dong.wav",
        ),
    ),
    AuditionSpec(
        file_stem="payment-12345678",
        amount_label="12.345.678 đồng",
        asset_files=(
            "muoi-hai.wav",
            "trieu.wav",
            "ba-tram-bon-muoi-lam.wav",
            "nghin.wav",
            "sau-tram-bay-muoi-tam.wav",
            "dong.wav",
        ),
    ),
)


@dataclass(frozen=True)
class PcmWav:
    sample_rate_hz: int
    samples: np.ndarray


def frames_for(milliseconds: int) -> int:
    return round(SAMPLE_RATE_HZ * milliseconds / 1000)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_pcm16_mono(path: Path) -> PcmWav:
    with wave.open(str(path), "rb") as source:
        format_info = (
            source.getnchannels(),
            source.getsampwidth(),
            source.getframerate(),
            source.getcomptype(),
        )
        expected = (CHANNELS, BITS_PER_SAMPLE // 8, SAMPLE_RATE_HZ, "NONE")
        if format_info != expected:
            raise ValueError(
                f"Unsupported WAV format for {path.name}: {format_info}; "
                f"expected {expected}"
            )
        samples = np.frombuffer(source.readframes(source.getnframes()), dtype="<i2")
    if not len(samples):
        raise ValueError(f"WAV is empty: {path.name}")
    return PcmWav(sample_rate_hz=SAMPLE_RATE_HZ, samples=samples.copy())


def write_pcm16_mono(path: Path, samples: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = np.asarray(samples, dtype="<i2")
    with wave.open(str(path), "wb") as output:
        output.setnchannels(CHANNELS)
        output.setsampwidth(BITS_PER_SAMPLE // 8)
        output.setframerate(SAMPLE_RATE_HZ)
        output.writeframes(pcm.tobytes())


def first_nonzero_frame(samples: np.ndarray) -> int:
    indices = np.flatnonzero(samples)
    if not indices.size:
        raise ValueError("WAV does not contain non-zero PCM samples")
    return int(indices[0])


def last_nonzero_frame(samples: np.ndarray) -> int:
    indices = np.flatnonzero(samples)
    if not indices.size:
        raise ValueError("WAV does not contain non-zero PCM samples")
    return int(indices[-1])


def first_audible_frame(samples: np.ndarray) -> int:
    indices = np.flatnonzero(
        np.abs(samples.astype(np.int32)) >= SILENCE_THRESHOLD
    )
    if not indices.size:
        raise ValueError("WAV does not contain audible PCM samples")
    return int(indices[0])


def last_audible_frame(samples: np.ndarray) -> int:
    indices = np.flatnonzero(
        np.abs(samples.astype(np.int32)) >= SILENCE_THRESHOLD
    )
    if not indices.size:
        raise ValueError("WAV does not contain audible PCM samples")
    return int(indices[-1])


def apply_voice_gain(samples: np.ndarray, gain_db: float) -> np.ndarray:
    multiplier = 10 ** (gain_db / 20)
    scaled = np.rint(samples.astype(np.float64) * multiplier)
    if np.max(scaled, initial=0) > 32767 or np.min(scaled, initial=0) < -32768:
        raise ValueError(
            f"Voice gain {gain_db:.2f} dB would clip a source speech asset"
        )
    return scaled.astype("<i2")


def extract_deployed_cue(samples: np.ndarray) -> np.ndarray:
    """Extract the first cue before the long intentional cue-to-speech gap."""

    window_frames = frames_for(DETECTION_WINDOW_MS)
    minimum_quiet_windows = max(
        1, MIN_CUE_FOLLOWING_SILENCE_MS // DETECTION_WINDOW_MS
    )
    saw_active = False
    last_active_window = -1
    quiet_windows = 0
    for start in range(0, len(samples), window_frames):
        end = min(start + window_frames, len(samples))
        active = bool(np.any(np.abs(samples[start:end].astype(np.int32)) >= SILENCE_THRESHOLD))
        if active:
            saw_active = True
            last_active_window = start // window_frames
            quiet_windows = 0
        elif saw_active:
            quiet_windows += 1
            if quiet_windows >= minimum_quiet_windows:
                end_frame = min(
                    len(samples), (last_active_window + 1) * window_frames
                )
                cue = samples[:end_frame]
                duration_ms = len(cue) * 1000 / SAMPLE_RATE_HZ
                if not 500 <= duration_ms <= 2_000:
                    raise ValueError(
                        f"Detected cue duration is outside expected bounds: {duration_ms:.1f} ms"
                    )
                return cue
    raise ValueError("Could not find a long cue-to-speech silence in cue source")


def _crossfade(left: np.ndarray, right: np.ndarray, frames: int) -> np.ndarray:
    if frames <= 0:
        return np.concatenate([left, right])
    if frames > len(left) or frames > len(right):
        raise ValueError("Crossfade exceeds prepared amount chunk length")
    fade_in = np.arange(1, frames + 1, dtype=np.float64) / (frames + 1)
    fade_out = 1.0 - fade_in
    mixed = np.rint(
        left[-frames:].astype(np.float64) * fade_out
        + right[:frames].astype(np.float64) * fade_in
    )
    return np.concatenate(
        [
            left[:-frames],
            np.clip(mixed, -32768, 32767).astype("<i2"),
            right[frames:],
        ]
    )


def compose_amount(
    segments: list[tuple[str, np.ndarray]],
    gap_ms: int,
    *,
    crossfade_ms: int,
) -> np.ndarray:
    """Crossfade every internal amount-preset boundary without a silent gap."""

    if not segments:
        raise ValueError("At least one amount segment is required")
    if gap_ms and crossfade_ms:
        raise ValueError("Amount preset joins cannot combine a gap and a crossfade")
    gap = np.zeros(frames_for(gap_ms), dtype="<i2")
    crossfade_frames = frames_for(crossfade_ms)
    prepared: list[np.ndarray] = []
    for index, (_, segment) in enumerate(segments):
        first_audible = first_audible_frame(segment)
        last_audible = last_audible_frame(segment)
        # The first chunk starts at its audible onset because prefix -> amount
        # has a separate intentional gap. Every later chunk supplies a small
        # onset pre-roll to crossfade with the preceding chunk.
        start = first_audible if index == 0 else max(0, first_audible - crossfade_frames)
        if index == len(segments) - 1:
            kept = segment[start:]
        else:
            end = last_audible + 1
            kept = segment[start:end]
        prepared.append(kept)

    result = prepared[0]
    for index, next_chunk in enumerate(prepared[1:]):
        if crossfade_frames:
            result = _crossfade(result, next_chunk, crossfade_frames)
        else:
            result = np.concatenate([result, gap, next_chunk])
    return result


def compose_prefix(cue: np.ndarray, phrase: np.ndarray, gap_ms: int) -> np.ndarray:
    # Drop only the phrase's exact-zero guard; keep quiet speech onset intact.
    phrase_from_first_sample = phrase[first_nonzero_frame(phrase) :]
    return np.concatenate(
        [cue, np.zeros(frames_for(gap_ms), dtype="<i2"), phrase_from_first_sample]
    )


def compose_announcement(prefix: np.ndarray, amount: np.ndarray, gap_ms: int) -> np.ndarray:
    # Mirrors PaymentWavTools.combinePcm16WithGap: remove unused zero tail and
    # leading zero guard, then insert the explicit target gap.
    prefix_end = last_nonzero_frame(prefix) + 1
    amount_start = first_nonzero_frame(amount)
    return np.concatenate(
        [
            prefix[:prefix_end],
            np.zeros(frames_for(gap_ms), dtype="<i2"),
            amount[amount_start:],
        ]
    )


def report(path: Path) -> dict[str, object]:
    parsed = read_pcm16_mono(path)
    samples = parsed.samples
    first = first_nonzero_frame(samples)
    last = last_nonzero_frame(samples)
    peak = int(np.max(np.abs(samples.astype(np.int32))))
    return {
        "file": path.name,
        "bytes": path.stat().st_size,
        "sha256": sha256(path),
        "sampleRateHz": parsed.sample_rate_hz,
        "channels": CHANNELS,
        "bitsPerSample": BITS_PER_SAMPLE,
        "durationMs": round(len(samples) * 1000 / SAMPLE_RATE_HZ, 3),
        "leadingZeroMs": round(first * 1000 / SAMPLE_RATE_HZ, 3),
        "trailingZeroMs": round((len(samples) - last - 1) * 1000 / SAMPLE_RATE_HZ, 3),
        "peakPcm16": peak,
        "fullScaleSampleCount": int(np.count_nonzero(np.abs(samples.astype(np.int32)) >= 32767)),
    }


def assert_exact_gap(samples: np.ndarray, start: int, length: int, label: str) -> None:
    if length < 0 or not np.all(samples[start : start + length] == 0):
        raise ValueError(f"Expected exact zero gap is missing: {label}")


def build(args: argparse.Namespace) -> dict[str, object]:
    cue_source = read_pcm16_mono(args.cue_source).samples
    cue = extract_deployed_cue(cue_source)
    prefix_gap_frames = frames_for(args.prefix_gap_ms)
    amount_gap_frames = frames_for(args.amount_gap_ms)
    cue_end = len(cue)

    output: dict[str, object] = {
        "schemaVersion": 1,
        "purpose": "OPS-43 listening QA only; not a Flutter runtime manifest",
        "cueSource": args.cue_source.name,
        "cueExtractedDurationMs": round(len(cue) * 1000 / SAMPLE_RATE_HZ, 3),
        "policy": {
            "format": "PCM16 mono 22050 Hz",
            "cueToPhraseInsertedGapMs": args.prefix_gap_ms,
            "prefixToAmountGapMs": args.amount_gap_ms,
            "amountChunkGapMs": args.chunk_gap_ms,
            "intermediateChunkTailTrimThresholdDbfs": -60,
            "allInternalAmountPresetCrossfadeMs": args.preset_crossfade_ms,
            "voiceGainDb": args.voice_gain_db,
            "auditions": [
                {
                    "amount": spec.amount_label,
                    "amountFiles": list(spec.asset_files),
                }
                for spec in AUDITION_SPECS
            ],
        },
        "packs": [],
    }

    for pack_name in VOICE_PACKS:
        pack = args.packs_root / pack_name
        phrase = apply_voice_gain(
            read_pcm16_mono(pack / PREFIX_PHRASE_FILE).samples,
            args.voice_gain_db,
        )
        prefix = compose_prefix(cue, phrase, args.prefix_gap_ms)
        assert_exact_gap(prefix, cue_end, prefix_gap_frames, f"{pack_name}: cue -> phrase")

        prefix_path = pack / "prefix.wav"
        audition_paths = [
            args.audition_root / pack_name / f"{spec.file_stem}.wav"
            for spec in AUDITION_SPECS
        ]
        for target in (prefix_path, *audition_paths):
            if target.exists() and not args.overwrite:
                raise FileExistsError(
                    f"Refusing to replace existing file without --overwrite: {target}"
                )
        write_pcm16_mono(prefix_path, prefix)
        auditions: list[dict[str, object]] = []
        for spec, audition_path in zip(AUDITION_SPECS, audition_paths, strict=True):
            amount_segments = [
                (
                    filename,
                    apply_voice_gain(
                        read_pcm16_mono(pack / filename).samples,
                        args.voice_gain_db,
                    ),
                )
                for filename in spec.asset_files
            ]
            amount = compose_amount(
                amount_segments,
                args.chunk_gap_ms,
                crossfade_ms=args.preset_crossfade_ms,
            )
            announcement = compose_announcement(prefix, amount, args.amount_gap_ms)
            prefix_end = last_nonzero_frame(prefix) + 1
            assert_exact_gap(
                announcement,
                prefix_end,
                amount_gap_frames,
                f"{pack_name}: prefix -> amount ({spec.file_stem})",
            )
            write_pcm16_mono(audition_path, announcement)
            auditions.append({"amount": spec.amount_label, **report(audition_path)})
        output["packs"].append(
            {
                "pack": pack_name,
                "prefix": report(prefix_path),
                "auditions": auditions,
            }
        )

    manifest_path = args.audition_root / "manifest.json"
    if manifest_path.exists() and not args.overwrite:
        raise FileExistsError(
            f"Refusing to replace existing file without --overwrite: {manifest_path}"
        )
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(
        json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return output


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--packs-root", type=Path, required=True)
    parser.add_argument("--cue-source", type=Path, default=Path("data/payment-cue-prefix.wav"))
    parser.add_argument("--audition-root", type=Path, required=True)
    parser.add_argument("--prefix-gap-ms", type=int, default=120)
    parser.add_argument("--amount-gap-ms", type=int, default=150)
    parser.add_argument("--chunk-gap-ms", type=int, default=0)
    parser.add_argument("--preset-crossfade-ms", type=int, default=50)
    parser.add_argument("--voice-gain-db", type=float, default=1.25)
    parser.add_argument("--overwrite", action="store_true")
    args = parser.parse_args()
    for field in (
        "prefix_gap_ms",
        "amount_gap_ms",
        "chunk_gap_ms",
        "preset_crossfade_ms",
    ):
        if getattr(args, field) < 0:
            parser.error(f"--{field.replace('_', '-')} must be non-negative")
    if not 0 <= args.voice_gain_db <= 6:
        parser.error("--voice-gain-db must be between 0 and 6")
    manifest = build(args)
    print(
        json.dumps(
            {
                "cueExtractedDurationMs": manifest["cueExtractedDurationMs"],
                "packs": [entry["pack"] for entry in manifest["packs"]],
                "auditionAmounts": [spec.amount_label for spec in AUDITION_SPECS],
            },
        )
    )


if __name__ == "__main__":
    main()
