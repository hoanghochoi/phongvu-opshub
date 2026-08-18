# Staging zero-downtime cutover rehearsal

This runbook is the execution contract for the OPS-78 staging rehearsal. It is
not production authorization. The rehearsal is blocked until OPS-200's ADR is
approved by the operational owner and the exact run window is recorded in
Linear.

## Required checkpoint

Record outside the repository, then attach only sanitized identifiers:

- exact Git SHA and workflow run;
- active and candidate release directories and image digests;
- current Caddy upstream/config digest;
- database migration state and expand/contract compatibility result;
- PostgreSQL/Redis health, pool/headroom and connection counts;
- operator, approver, monitor and UTC release-window start/end;
- rollback deadline and previous release pointer.

Do not begin if the worktree, source SHA, image digest, migration state or
rollback target changes after this checkpoint.

## Rehearsal sequence

1. Freeze merges for the window and verify the exact allowlisted staging
   hostnames. Disable ERP/MAP/VietQR/SMTP side effects as required by the Home
   load runbook.
2. Start the candidate color in an isolated Compose project/network. Do not
   stop the active color. Run the candidate healthcheck, direct-origin health,
   authenticated bootstrap/me, Home 1/7/30/90 parity and app-version checks.
3. Run the approved migration preflight. Only expand/contract-compatible
   migrations may proceed. Any failed or ambiguous migration state stops the
   rehearsal and leaves the active color serving traffic.
4. Reload Caddy atomically to the candidate HTTP and WebSocket upstreams. Do
   not restart Caddy. Record the reload result and the exact config digest.
5. Verify new HTTP requests and WebSocket ticket/upgrades reach the candidate.
   Keep existing WebSocket sessions on the old color and observe a maximum
   120-second drain. Stop and reload the old upstream if the drain/error gate
   fails.
6. Run the authenticated Home parity/load profile from
   `deploy/staging/load-proof-runbook.md` only with its exact approval and k6
   checksum. Keep raw tokens/output outside Git.
7. Observe the approved window. A single unexpected write/side effect,
   restart, OOM, deadlock, Redis eviction, 429/5xx/timeout, parity mismatch,
   SLO breach, unhealthy dependency or unexplained connection drop fails the
   rehearsal.
8. On pass, retain the old color until the rollback deadline, then remove only
   the released color and temporary evidence after sanitized proof is recorded.
   On failure, reload Caddy to the previous color, verify health/version and
   preserve rollback metadata for investigation.

## Mandatory cleanup

Run the existing load-user cleanup and recovery checks. `verify-empty` must
prove zero synthetic users, assignments, email codes and known references before
removing the protected token manifest. Delete workstation tokens, k6 binaries,
raw logs and snapshots; verify no k6 or test WebSocket process remains. Any
cleanup uncertainty is a failed rehearsal and blocks promotion.

## Pass evidence

Publish only a sanitized report containing SHA, workflow/run IDs, image/config
digests, migration result, HTTP/WebSocket success and drain counts, Home parity
and latency aggregates, resource thresholds, rollback result and cleanup count.
Do not publish credentials, tokens, request IDs, raw logs or full payloads.
