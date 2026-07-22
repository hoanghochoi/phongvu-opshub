# 0014 Piper Offline Payment Audio Assets

Date: 2026-07-22

## Status

Accepted for OPS-11 implementation. This decision supersedes the voice and
generator choice in decision 0013; the approved chunk grammar and composition
policy remain unchanged.

## Context

Listening QA found that VieNeu voices were not suitable for short payment
announcements and did not match the existing production cue. Production already
uses Piper `piper:vi-vais1000` through `piper-tts==1.4.2` at speed `0.90`.
Generating the immutable number pack with the same model keeps the announcement
voice consistent without calling production for each of the 1,103 assets.

The production model and config are copied read-only to an ignored local build
directory. Their required SHA-256 values are:

- model: `ec7c89e2c85f4d1edc24b6120c18aaf1bda614f06b511567eb9c7c0de15e2dab`;
- config: `fafb9da1354ed4b77c31af228ed41fb41cd825c14cffa105454b25e6ae751ee0`.

Piper emits mono PCM16 at 22.05 kHz. Build tooling trims only the model's outer
silence, resamples to 24 kHz, applies a fixed `-1.5 dB` headroom gain, then adds
exactly 300 ms leading and 200 ms trailing silence. Runtime composition trims
the stored guards fully at chunk boundaries and inserts a 45 ms join gap. The
fixed production cue is joined to the amount with a 150 ms gap.

## Decision

- Ship immutable pack `piper-vi-vais1000-chunk-v1` in the Windows installer.
- Keep the existing inventory: 1,000 leading groups, 99 forced-hundreds groups
  and four scale/currency units. Do not return to word-level joins.
- Generate with local Piper 1.4.2, production model/config pins and speed 0.90.
  Do not send the batch to the production sidecar and do not ship Piper/model
  binaries in the client.
- Fail closed on model/config checksum mismatch, incomplete inventory, invalid
  WAV format, missing guards, silent content, full-scale samples or manifest
  hash mismatch.
- Bump both backend event and Flutter pack versions. Mixed old/new deployments
  therefore use the existing server-audio fallback instead of composing with a
  mismatched pack.
- Keep `data/payment-cue-prefix.wav` unchanged. The runtime cue remains the
  already-deployed “Phong Vũ đã nhận:” asset.

## Evidence

The generated pack contains 1,103 PCM16 mono 24 kHz WAV files totaling
74,793,470 bytes. Mean content duration is 911.64 ms, p95 is 1,161.00 ms and
the maximum is 1,277.08 ms. Generation and an independent full-pack verifier
both completed without missing, silent, corrupt-guard or full-scale assets.

The model source repository declares mixed licensing. The client pack records
source and checksum provenance in its manifest and notice; Piper and the model
remain build-time-only dependencies.

## Consequences

The client preserves the low-latency local composition path while announcements
use the same Piper voice family as production. Installer payload is smaller than
the superseded VieNeu corpus. Changing model, voice, grammar, speed, gain or
boundary policy requires a new immutable pack version and client build.
