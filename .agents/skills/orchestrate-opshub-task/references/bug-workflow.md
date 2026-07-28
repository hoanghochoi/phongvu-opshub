# Bug workflow

1. Capture expected behavior, actual behavior, reproduction evidence, affected
   production impact, and the exact source/base SHA.
2. Triage two lanes before editing: the smallest reversible hotfix and the
   durable full fix (cleanup, migration, backfill, or architecture). Record
   residual full-fix scope instead of silently closing it with the hotfix.
3. Have `opshub_spec_analyst` define acceptance and stop conditions,
   `opshub_repo_explorer` trace the root-cause path, and
   `opshub_test_engineer` create or identify a failing reproduction. Serialize
   any test-file edits before production edits.
4. Delegate the smallest root-cause change to one `opshub_implementer`. Preserve
   permissions, API/data contracts, Vietnamese copy, AppLogger, and old
   consumers.
5. Re-run the reproduction and affected regressions, then use code/security/UI
   reviews only when their triggers apply.
6. Report recovery point, rollback path, unverified runtime proof, and the next
   full-fix issue/action in the Linear tracking comment before status changes.
