# Feature workflow

Use for a Linear-linked feature or bounded maintenance change.

1. Confirm the issue, team, acceptance criteria, product authority, risk flags,
   and whether a Figma revision is required. Do not infer acceptance from a
   title.
2. From the canonical staging worktree, use the guarded task lifecycle to start
   a branch/worktree at the live `origin/staging` SHA. Record branch, HEAD,
   dirty state, path contracts, and affected-consumer proof before edits.
3. Run `opshub_spec_analyst` and `opshub_repo_explorer` in parallel. Reconcile
   their evidence into a file-level plan with one writer and a proof ladder.
4. Stop for human/product/security/Figma decisions. After the plan is approved,
   delegate `opshub_implementer`; do not let the root edit overlapping files.
5. Delegate `opshub_test_engineer` only in a serialized test wave. Preserve
   existing fake/provider/repository patterns and do not introduce a new test
   stack without authority.
6. Run code review and only triggered security/UI reviews. Recompute affected
   proof after every correction and invalidate stale fingerprints.
7. Write the Linear implementation/proof comment before moving the issue to a
   forward status. Stop before commit/push/PR unless separately authorized.

For user-facing Flutter flows, require AppLogger start/success/failure and
branch logs, Vietnamese-first action copy, shared components, and the canonical
DateRangePicker/command-input/modal contracts.
