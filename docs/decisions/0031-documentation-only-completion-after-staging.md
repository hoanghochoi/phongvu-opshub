# 0031 Documentation-Only Completion After Staging

Date: 2026-08-19

## Status

Accepted for repository and Linear lifecycle tracking.

## Context

OpsHub previously required every issue to reach production before Linear could
be marked `Done`. That is appropriate for runtime, deployment, dependency,
asset, permission, and production-configuration changes, but it leaves a
documentation-only task open after its exact staging proof has passed. The
open state then incorrectly suggests that the documentation task still needs a
production rollout even though it changes no production artifact or behavior.

## Decision

1. A task may use the `documentation-only` completion lane only when its
   changed paths are limited to repository documentation and evidence, such as
   Markdown, ADRs, plans, story packets, indexes, sanitized JSON manifests, or
   repository guidance. The task must not change runtime source/tests,
   dependencies or lockfiles, generated assets, deployment workflows/config,
   secrets/environment inputs, permissions, routes, API/data contracts, or
   user-visible product behavior.
2. The PR and Linear proof comment must explicitly state
   `documentation-only`, list the changed-path scope, and record exact CI,
   staging deploy, QA, affected-consumer and `git diff --check` results. The
   normal PR/review/lifecycle cleanup gates still apply.
3. After the exact staging deploy and required QA pass, a qualifying
   documentation-only issue may transition directly from `Testing` or `Ready
   for QA` to `Done`. Production promotion is not required for that issue.
   `Done` means repository execution is complete; it does not claim that the
   documentation has been published to a production host.
4. Any scope ambiguity, a mixed documentation/runtime diff, or a document that
   is itself a production release/configuration input uses the normal
   `Ready for Release` -> `Releasing` -> production deployment -> `Done` lane.
   The narrower lane never waives production safety or release approval.

## Consequences

- OPS-64-style docs-only reconciliation can close after exact staging proof
  without waiting for a production promotion of unchanged runtime behavior.
- Runtime and production-affecting tasks remain protected by the existing
  production deployment gate.
- Classification is an explicit, reviewable claim; it must never be inferred
  solely from a file extension or a green staging build.

## Validation impact

Update `AGENTS.md`, `docs/WORKFLOW.md`, the release playbook and the
GIT-WORKFLOW-001 contract together. Existing runtime/UI/release plans retain
their production gate unless they explicitly qualify for this lane.
