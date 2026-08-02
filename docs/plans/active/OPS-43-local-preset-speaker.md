# Execution Plan: OPS-43 Local preset-only payment speaker

Date: 2026-08-02

## Status

Active

## Outcome

Ship the approved three-voice Windows payment speaker packs, use them for
local-only playback with a 50 ms amount-boundary crossfade, and let each
speaker PC choose its voice locally. The result must not download or play
server-generated audio on the supported Windows-speaker path.

## Context

- Linear OPS-43 records the local-only speaker and audio-prefix policy.
- `docs/decisions/0014-piper-offline-payment-audio-assets.md` establishes the
  previous local-composition contract; OPS-43 supersedes its cue-prefix policy
  for the new three-voice packs.
- New immutable source packs live under `artifacts/tts-samples/` and contain
  PCM16 mono 22,050 Hz WAV files, including `phong-vu-da-nhan.wav`.
- Product listening QA chốt crossfade 50 ms for every internal amount-preset
  join. The independent cue/prefix joins remain 120 ms and 150 ms.

## Scope

In scope:

- Package the three source packs as Git LFS Windows installer assets with
  fail-closed manifests, including each voice's rendered `prefix.wav`.
- Replace the Windows speaker local branch with selected-pack composition and
  local prefix playback; a missing/invalid pack ends delivery as `FAILED` and
  never requests server audio.
- Add a Windows-speaker setting for voice selection, persisted locally per PC.

Out of scope:

- WNS, background/realtime or updater implementation.
- Production release or physical speaker QA.

## Approach

1. Import the immutable source packs through a reproducible fail-closed tool.
   Each pack has 1,103 number chunks and `prefix.wav`, canonical chunk IDs,
   SHA-256/byte/frame metadata, PCM16 mono 22,050 Hz format, and the approved
   50 ms crossfade policy.
2. Store the three installer packs through Git LFS and configure CI checkout,
   verifier, and Windows CMake installation for exactly those packs.
3. Refactor Flutter composition to resolve the selected voice pack, validate
   every loaded hash/format, and crossfade every internal amount join by 50 ms
   after trimming source boundary padding. Pass the validated pack prefix to
   the speaker for the separately approved 150 ms prefix-to-amount join.
4. Make the supported speaker path local-only: a non-local event or local-pack
   failure logs/audits terminal `FAILED`; it does not call `/audio` or fall
   back to a server waveform. Preserve FIFO, claim, delivery acknowledgements,
   and the existing maximum of three playback attempts.
5. Persist the voice ID locally per Windows speaker PC. Default new installs
   to `mien-bac-thanh-ha`; switching takes effect for the next notification.

## Risks And Recovery

- The three packs add approximately 160 MB. Mitigation: track only WAV packs
  through Git LFS and fetch LFS before CI verification/build; recovery is a
  revert of the manifest/CMake/asset import together.
- A wrong/corrupt pack may silence a notification. Mitigation: fail closed,
  log/audit `FAILED`, retain the existing three playback retries only for audio
  device/playback failures, and show the actionable speaker error card.
- Crossfading can cause clipping if source tails overlap. Mitigation: verify
  all generated packs and test mix saturation; recovery is regenerate/import
  from immutable source packs without TTS.

## Progress

- [x] Confirm product policy in OPS-43 and measure source-pack boundary silence.
- [x] Create clean task worktree from live `origin/staging`.
- [x] Inspect exact cue and representative amount source files.
- [x] Generate and validate three prefixes plus audition announcements.
- [x] Obtain product listening QA and approve a 50 ms internal amount crossfade.
- [x] Import three production voice packs and validate their installer form.
- [x] Implement local-only selected-voice Flutter playback and setting.
- [x] Run asset, focused Flutter/backend, analyzer, and full Flutter test proof.
- [ ] Complete Windows release build and physical speaker QA.

## Decisions

- 2026-08-02: Prefix is pre-rendered per voice instead of runtime sequential
  playback, to eliminate MP3 decode/player sequencing risk.
- 2026-08-02: No separate silence WAV. The source-pack tail distribution would
  otherwise cause inconsistent double gaps.
- 2026-08-02: Use 120 ms for cue -> phrase and 150 ms for prefix -> amount;
  listening QA has approved these alongside the 50 ms internal amount crossfade.
- 2026-08-02: Audition-only voice gain is +1.25 dB. +2 dB was rejected
  fail-closed because a large-number chunk would clip. The amount join is
  reduced from 45 ms to 0 ms after listening feedback. Intermediate amount
  chunks trim source padding at -60 dBFS, preserve a 15 ms onset pre-roll and
  crossfade **every** internal preset boundary by 50 ms; the final “đồng” keeps
  its natural tail. The first amount chunk remains outside this rule because
  prefix -> amount has its separate 150 ms product pause. Product listening QA
  then approved this runtime policy at 50 ms crossfade.
- 2026-08-02: New Windows installations default to `mien-bac-thanh-ha`.
  Selection is local to each speaker PC and never changes the user or server.
- 2026-08-02: All shipped preset WAV files use Git LFS. The old Piper pack is
  not installed by the updated CMake path; it remains in source history for
  reversible compatibility until a separately reviewed cleanup.
- 2026-08-02: The audition tool extracts the deployed PCM cue segment from
  `data/payment-cue-prefix.wav` rather than decoding `ting_ting.mp3`. This
  preserves the current local cue gain/format for the audition; it does not
  modify the original MP3 or runtime asset wiring.

## Validation

- Focused proof: imported-pack verifier, manifest/hash/format/frame checks,
  crossfade unit tests, selected-pack and fail-closed provider tests, and
  existing delivery retry tests.
- Build proof: Windows CMake install output verification with Git LFS fetched.
- Repository-required checks: `flutter analyze`, focused Flutter and Nest tests,
  `git diff --check`, and changed-file inspection.

## Result

Implemented and partially release-verified. Generated ignored local audition assets at
`artifacts/tts-samples/<voice>/prefix.wav` and
`artifacts/tts-samples/audition/<voice>/payment-123000.wav` plus
`payment-12345678.wav` in the source artifact workspace. The representative
announcements are “Phong Vũ đã nhận: một trăm hai mươi ba nghìn đồng” and
“Phong Vũ đã nhận: mười hai triệu ba trăm bốn mươi lăm nghìn sáu trăm bảy mươi
tám đồng”. Independent validation passed for all nine WAVs: PCM16 mono 22,050
Hz, zero full-scale samples and manifest SHA-256 match. Prefix durations are
2,764–2,783 ms and announcements are 4,301–6,165 ms. Listening QA is approved
at 50 ms.

The implementation packages all three voice packs, composes selected-pack
amount chunks with a 50 ms crossfade, passes each selected prefix directly to
the speaker, fails terminally without a server-audio fallback, and persists the
voice selection locally. Backend streaming now defaults to `LOCAL_ASSET` with
`local-preset-speaker-v1`; TTS remains only behind the explicit legacy
`PAYMENT_SPEAKER_STREAMING_ENABLED=false` rollback mode.

Verified: all three installer packs using
`python scripts/verify_payment_audio_assets.py --presets-root ...`, targeted
backend Jest (44 tests), Flutter analyzer, full Flutter test suite (699 passed,
3 skipped), targeted speaker/settings tests (60 passed), backend build, and
`git diff --check`. A local Windows release build was started but could not be
completed in this workstation because the `super_native_extensions` Rust
build-tool stage hung with neither `cargo` nor `rustc` installed; the build
process was stopped. CI has Git LFS checkout plus source/release pack
verification, but CI/physical Windows speaker proof remains required.
