# OPS-80 — Home Summary cache coverage hotfix

## Outcome

Keep a valid Home Summary request within the existing 366-day input guard when
comparisons are enabled. The response cache must track the primary and
previous-year periods as separate coverage ranges so a short request never
creates a synthetic 369-day iterable.

## Checkpoint

- Linear issue: `OPS-80`
- Branch: `codex/ops-80-home-summary-cache-coverage`
- Base: `738f907c3b931536bb4cbe77b8f5204c7fb20882`
- Canonical `staging` and `origin/staging` matched at task start.
- Recovery: revert the isolated commit/PR; production remains unchanged until
  staging build, deploy and smoke proof pass.

## Scope and invariants

- Preserve the public Home API, DTOs, permissions, comparison period dates,
  cache identity, TTL, refresh-ahead and projection invalidation semantics.
- Keep `rangeDateKeys` strict: 1–366 days are valid and 367 days still fails
  with the current Vietnamese error.
- Never represent primary plus comparison coverage as one continuous range.
- Keep this hotfix narrow; any broader multi-period cache redesign remains a
  linked follow-up.

## Execution

1. Add separate cache/in-flight coverage ranges and update invalidation.
2. Add production-equivalent regression cases for normal and leap-year short
   ranges, 365/366/367-day boundaries, comparison opt-in and cache storage.
3. Run focused Nest tests, build, affected-consumer verification and diff
   checks.
4. Publish to `staging`, wait for CI/deploy/smoke evidence, update Linear, then
   run the guarded lifecycle finish and remove the task worktree.

## Status

- [x] Checkpoint and Linear implementation note recorded.
- [x] Cache coverage implementation.
- [x] Regression and affected-consumer proof.
- [ ] PR, staging deploy and authenticated smoke.
- [ ] Lifecycle cleanup and final tracking note.

## Local proof before publication

- `npm test -- --runInBand src/home-summary`: 119 passed, 6 skipped.
- Focused cache/comparison matrix: 72 passed.
- `npm run build`: pass.
- Flutter Home affected consumers (`home_dashboard`, details repository,
  repository cache, header/layout): 60/60 passed.
- `node scripts/verify-task.mjs --base origin/staging --full --json
  tmp/verify-ops80-final.json`: all 8 profiles pass, `stale=false`; the
  runner includes Flutter analyze, Nest build, Go tests and deployment/security
  contracts. The artifact is local proof and is not committed.
- Remaining gate: publish PR to `staging`, exact-SHA staging deploy and
  authenticated production-equivalent smoke for a four-day comparison request.
