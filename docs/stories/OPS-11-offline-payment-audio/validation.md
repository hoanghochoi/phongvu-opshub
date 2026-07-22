# OPS-11 Validation

## Required Proof

| Layer | Proof |
| --- | --- |
| Source pack | 1.103 manifest entries and WAV files pass SHA-256, size, PCM16 mono 24 kHz, speech-present and 300/200 ms silent-guard checks. |
| Client grammar | Edge amounts map to canonical leading/forced chunks and scale units. |
| Composition | Known guards are trimmed without scanning speech; malformed guards fail closed. |
| Local-first | Matching event composes and claims with zero audio downloads; missing pack falls back to server stream. |
| Backend | Event advertises VND/version/mode; claim creates delivery ownership without opening or generating audio. |
| Distribution | Source pack and built Windows Release pack produce the same manifest hash and pass the full validator. |
| Existing consumers | Payment Monitor FIFO/dedupe/recovery, Bank Statement, VietQR, realtime gateway and Windows packaging regression remain green. |

## Fresh Local Evidence

- Asset validator: 1.103 WAV, 88.838.258 bytes, all checks passed.
- Focused Flutter: 48 tests passed; first real 1.250.000 VND compose including
  manifest load and five SHA-256 checks completed in 229 ms.
- `flutter analyze --no-pub`: no issues.
- NestJS build passed; focused Payment Notifications: 44 tests passed.
- Windows Release build passed in 414.2 seconds; the copied release pack passed
  the same 1.103-file validator and its manifest SHA-256 matched source.

## Remaining Runtime Risk

- Physical showroom speaker quality and p95 WebSocket-to-first-audio require a
  signed staging build and real transactions.
- Server fallback remains enabled until adoption and failure telemetry support
  reducing legacy TTS capacity.
