# 0013 VieNeu Offline Payment Audio Assets

Date: 2026-07-22

## Status

Accepted for OPS-11 implementation. Ngọc Linh and the corpus-v4 listening files
were approved on 2026-07-22; physical-speaker staging QA remains required before
production rollout.

## Context

The current payment announcement path creates speech on the server. That adds
provider/server work and network latency to every transaction. OPS-11 instead
sends only the normalized amount over the existing realtime channel and lets an
enabled client compose pre-generated Vietnamese number assets locally.

The spike compares two asset granularities generated with VieNeu 3.2.3, v3
Turbo ONNX int8, model revision
`75ff82a72f54d55ed389e1eeb12041d3c4bac7d4`, codec revision
`ceff0d0749bfb3fa2d61149794ec6feef0d1e1ae`, and the `Ngọc Linh` preset voice.
Audio is generated once during asset preparation, converted to mono PCM16 at
24 kHz, and is intended to ship inside the application installer. Runtime does
not download the model or call VieNeu.

## Evidence

| Measure | Word-level | Chunk 0–999 |
| --- | ---: | ---: |
| Asset count | 21 | 1,103 |
| Raw 24 kHz PCM16 | 751,264 bytes | 75,072,818 bytes |
| ZIP 24 kHz candidate | 416,414 bytes | 55,114,507 bytes |
| Mean content duration | 504.39 ms | 1,177.05 ms |
| p95 content duration | 560.00 ms | 1,394.72 ms |
| Outputs longer than 3 seconds | 0/21 | 0/1,103 |
| Client composition mean, 50 runs | 6.285 ms | 4.172 ms |
| Client composition p95, 50 runs | 12.560 ms | 6.456 ms |

The first generated corpus (`corpus-v2`) was rejected after listening feedback:
its `-45 dB` trim with only 25 ms padding clipped audible starts/ends, and its
listening pack deliberately included runaway outputs. That pack must not be
used for product or voice decisions.

The corrective `corpus-v3` uses deterministic per-attempt seeds, twelve retry
temperatures, a 3.84-second generation cap, duration bounds based on phrase
length, and fail-closed output. Each stored asset receives an exact 120 ms zero
guard after resampling. Composition removes only 90 ms of that known guard,
leaving 30 ms on both sides; it never trims the speech waveform. All 1,124
assets, 2,248 source/package formats, 30 A/B files, and three voice samples pass
hash, format, duration, and boundary validation. Word generation required 39
attempts for 21 assets; chunk generation required 1,111 attempts for 1,103
assets.

The packaging-only `corpus-v4` preserves those accepted speech samples and
changes only the standalone corpus guards to 300 ms leading and 200 ms
trailing. It leaves 30 ms at each edge during composition and keeps the 45 ms
join gap, so the A/B playback timing and the existing 120 ms voice-sample
guards do not change. The v3 corpus remains intact for rollback and byte-level
comparison. All 2,248 v4 WAV formats have byte-identical speech content after
their guards are removed, and all 30 recomposed A/B files are byte-identical to
v3. The v4 chunk candidate measures 88,838,258 bytes raw and 55,201,137 bytes
as ZIP at 24 kHz; the longer zero guards add only 86,630 compressed bytes over
v3.

The chunk inventory contains 1,000 leading groups, 99 forced-hundreds variants
for non-leading groups 001–099, and the four scale/currency units `nghìn`,
`triệu`, `tỷ`, and `đồng`. This preserves readings such as
`một triệu không trăm lẻ năm nghìn` without falling back to word-level joins.

## Decision

- Reject pure word-level assets for OPS-11. Their small installer footprint does
  not compensate for unstable short-token generation and highly fragmented
  prosody.
- Continue OPS-11 with the chunk 0–999 inventory and 24 kHz mono PCM16 package.
  Its measured local composition time leaves almost the full two-second budget
  for websocket delivery, scheduling, and audio-device startup.
- Treat approximately 55.20 MB as the measured compressed installer increment
  before Inno Setup packaging. The assets are installed with the client and are
  regenerated only when the voice, grammar, model pin, or audio policy changes.
- Keep the manifest with asset-pack version, exact upstream revisions, hashes,
  format metadata, and licensing attribution. The Flutter build must consume a
  reviewed output pack, not run TTS as part of application startup.
- Keep the build-time QC gate fail-closed for missing files, hash/format
  mismatch, non-zero boundary guards, duration bounds, failed retries, and the
  representative amount set. Do not publish an A/B pack from rejected assets.
- Use `Ngọc Linh` as the accepted OPS-11 production voice. A voice or grammar
  change requires a new immutable asset-pack version and a new client build.

## Consequences

The normal local path does not synthesize or download per-transaction audio.
Server audio remains available for old clients, recovery, kill-switch rollback,
and missing/corrupt/mismatched packs. The client receives deterministic offline
behavior while the Windows installer grows by roughly 55 MB compressed. A
client whose pack is missing or invalid logs the sanitized failure through
`AppLogger` and falls back without blocking payment monitoring.
