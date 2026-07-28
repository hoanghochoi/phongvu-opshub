# Desktop routing verification

Run after the project is trusted and a new Desktop session/worktree has loaded
the project layer. Do not treat a role's natural-language self-report as
identity evidence.

1. Run `scripts/validate_config.py` and confirm the project config/agent files
   are tracked, while local archive/log artifacts remain ignored.
2. Open a fresh trusted session; existing sessions may retain old configuration.
3. Spawn bounded no-op/non-mutating tasks in batches of at most three. Capture
   actual agent type, model, reasoning effort, and inherited permission metadata
   when the surface exposes them. If metadata is unavailable, return
   `Unverified`. Record the parent permission as the effective child boundary
   and require unchanged-state proof for no-op/review waves.
4. Require a real child/receiver thread id before calling a spawn successful.
   A role listing proves discovery only; an empty receiver list, failed fork,
   or parent-authored child result keeps dispatch `Unverified`. Do not retry by
   enabling experimental features or changing user-level configuration.
5. Verify intended routing for spec, explorer, implementer, test, code review,
   security, UI, and release-audit roles. Do not run a write canary in the
   repository; use metadata plus unchanged-state proof instead.
6. Smoke the decision gates: missing Figma blocks the writer; bug triage keeps
   hotfix/full-fix lanes; review stays within three children; release audit
   never emits a protected mutation.

Record standalone CLI portability as a separate follow-up. Use the
Desktop-managed runtime for Desktop proof, and do not change user-level config
as part of this routing smoke.
