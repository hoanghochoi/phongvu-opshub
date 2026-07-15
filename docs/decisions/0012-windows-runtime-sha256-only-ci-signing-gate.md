# 0012 Windows Runtime SHA-256 Only With A Mandatory CI Signing Gate

Date: 2026-07-15

## Status

accepted

## Context

OpsHub distributes a Windows Inno Setup installer from the same environment
that publishes `/app-version`. Runtime signer pinning made certificate rotation
and internal trust deployment part of the client update path. The product owner
accepted removing that runtime pin, while retaining a fail-closed artifact
release boundary in CI.

SHA-256 alone proves that the downloaded bytes match the published metadata; it
does not establish an independent publisher identity when an attacker can
replace both metadata and the installer. That limitation must remain explicit.

## Decision

- The Windows client accepts only an HTTPS, same-origin, allowlisted installer
  URL with the expected package type and bounded size, rejects redirects, then
  requires the exact `packageSha256` and `packageSizeBytes` before launch.
- The Flutter release build no longer receives
  `WINDOWS_UPDATE_SIGNER_SHA256`. Runtime does not run an Authenticode signer
  pin check.
- Production and staging release CI remain fail-closed. The appropriate PFX,
  password and expected signer fingerprint are mandatory; the final app and
  installer must have a valid Authenticode signature with a trusted timestamp,
  match the configured signer pin, and pass the Microsoft Defender artifact
  scan before checksum generation or publication. Unsigned artifacts are
  rejected.
- CI keeps the signer fingerprint only as a release-gate input. It must not be
  reintroduced as a Flutter runtime build define without a new decision.
- Runtime failures have stable `code` and `stage` values. Contract, integrity,
  native-install and unexpected failures upload a sanitized error log when the
  user is authenticated; expected network, timeout and incomplete-download
  failures remain local warnings and feed the daily activity summary.

## Consequences

- Certificate rotation no longer blocks an already installed client's runtime
  updater, while every published release is still signed, timestamped and
  malware-scanned.
- Compromise of both `/app-version` metadata and the hosted package can bypass
  the runtime integrity boundary. This is an explicitly accepted residual risk;
  SHA-256-only must not be described as publisher authentication.
- Safe logs contain only code, stage, duration, platform/build, sanitized host
  and byte counts. They contain no URL query, token, payload or local file path.
- Validation must prove runtime signer-pin removal, SHA mismatch cleanup,
  mandatory CI signing/timestamp/pin/Defender checks, signed staging artifact
  inspection, and an installed staging build N to N+1 update without affecting
  the production installation.
