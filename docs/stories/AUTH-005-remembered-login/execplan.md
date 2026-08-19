# AUTH-005 Execution Plan

## Delivery state

Implementation is complete in the guarded task worktree
`codex/ops-208-remember-password`, based on
`152ee7ea8c7533ba3f1cddbccb0242b54296bc17`. The issue remains In Progress until
staging and device proof are complete.

## Ordered scope

1. Read and approve the OPS-208 Figma R1 node map for all declared viewport and
   state variants before changing the login UI.
2. Add the versioned, environment-namespaced secure credential store and inject
   it into `AuthProvider` without changing the session preference boundary.
3. Add the shared accessible `AppCheckbox` and integrate async prefill, opt-in
   save, immediate clear, fail-closed storage feedback and password-change/
   reset invalidation into `/login`.
4. Protect existing auth consumers with store/provider/widget tests and update
   auth product, ADR, test-matrix and active-plan documentation.
5. Run local analyzer, focused/full Flutter proof, platform builds and the
   affected-consumer verification wrapper; then record the evidence in OPS-208.
6. Deploy the exact candidate to staging and complete authenticated Chrome
   visual comparison plus real Windows/Web and Android/iOS secure-storage
   checks before any release status transition.

## Recovery boundary

The feature is isolated to Flutter/auth storage and documentation; no backend
or API migration is required. Reverting the task branch removes the feature,
and the versioned secure-storage key can be cleared independently.
