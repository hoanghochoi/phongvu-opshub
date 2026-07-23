# 0021 Consumer-First Application Legibility Phase

Date: 2026-07-21

## Status

Accepted and active.

## Context

Decision 0019 removed the SQLite lifecycle from ordinary work and made the
repository the system of record. Decision 0020 reduced the default installation
to a ten-file core and deferred application-legibility claims until a real
consumer supplied observable evidence.

OpenAI's
[Harness engineering: leveraging Codex in an agent-first world](https://openai.com/index/harness-engineering/)
describes autonomy as an end-to-end application loop: agents use standard
development tools, reproduce failures, operate the application, validate fixes
through the application, respond to feedback, recover from failures, and
escalate only when human judgment is required. It also warns that this behavior
depends on repository-specific structure and tooling and should not be assumed
to generalize automatically.

The first real consumer experiment used `e-inna-brain` and the task:

> Add rate-limiting to the /chat endpoint

The reduced core installed without creating a CLI or database prerequisite. A
fresh agent found the product contract, HTTP boundary, configuration, module
wiring, bootstrap, deployment proxy, and adjacent tests without human
navigation. The repository did not define the quota, trusted identity, shared
state topology, SSE semantics, enforcement owner, or public 429 contract.

In the first run the agent recognized that gap but invented configurable
defaults and required interruption. After the core added one compact
policy-authority rule and a concrete example, a clean replay found the same gap
and stopped before editing without intervention.

This is useful application-legibility evidence, but it is not end-to-end
runtime proof. Neither run started the application, created deterministic
state, called `/chat`, retrieved runtime logs, implemented behavior, exercised a
focused test, verified an HTTP before/after result, or rehearsed cleanup.

## Decision

Reduction Phase 3 is a narrow, evidence-producing, consumer-first application-
legibility phase. It is not a generic observability framework.

Phase 3 evaluates one real task through this target loop:

```text
discover execution
-> start an isolated worktree-local instance
-> create deterministic scenario state
-> reproduce through the real interface
-> inspect relevant runtime evidence
-> implement the bounded change
-> run focused executable proof
-> verify through the same interface
-> stop and clean up only that instance
```

The phase may stop earlier when repository authority is genuinely missing.
Such a stop is valid evidence about the consumer and the core, but it proves
only the capabilities exercised before the stop. It does not convert later
steps into implied success.

The `e-inna-brain` rate-limit experiment is the first completed Phase 3
checkpoint. It proves:

1. a real brownfield consumer can receive the reduced core without regaining
   mandatory CLI/SQLite ceremony;
2. a fresh agent can discover the relevant application and deployment truth
   without human navigation; and
3. a compact repository rule can turn an observed speculative-policy failure
   into a self-directed human-judgment stop with no application diff.

It does not prove:

1. simultaneous isolated application runtimes in two worktrees;
2. deterministic scenario seeding or reset;
3. interface-level reproduction;
4. instance-local log or runtime-signal retrieval;
5. implementation and focused product proof;
6. interface-level before/after verification; or
7. independent cleanup and recovery.

Phase 3 therefore remains active. Completion requires a consumer task with
explicit expected behavior to exercise the full target loop, or a later
decision that deliberately changes that exit condition based on new evidence.

Most improvements belong in the consumer application: natural stack-specific
runtime commands, fixtures, readiness, logs, interface support, tests, and
development documentation. `repository-harness` receives only patterns proven
to reduce human intervention across observed work. It must not absorb a
consumer runtime, introduce a legibility database, or distribute generic
browser/observability adapters in the default core.

Durable evidence is Git-native: one execution plan/report per coordinated
experiment, application diffs, test output, runtime observations, and
before/after interface evidence. Intake rows, trace scores, capability
registries, and Harness compliance dashboards are not Phase 3 proof.

## Alternatives Considered

1. **Declare Phase 3 complete from source discovery and correct escalation.**
   Rejected because it would claim runtime, deterministic-state, observability,
   implementation, and interface capabilities that were never exercised.
2. **Reject the e-inna experiment because it stopped before implementation.**
   Rejected because the stop exposed a real product-authority gap and produced
   a successful correction replay with measurable intervention reduction.
3. **Build a generic application-legibility manifest and adapters first.**
   Rejected because it would recreate a registry and platform before one real
   vertical application path demonstrates which capabilities are missing.
4. **Use repository-harness fixtures as the Phase 3 application.** Rejected
   because synthetic CLI/workflow fixtures cannot prove startup, real interface
   operation, runtime diagnosis, or user-visible before/after behavior.

## Consequences

Positive:

- Phase 3 claims remain bounded by observed application behavior.
- The completed e-inna checkpoint is retained rather than overstated or
  discarded.
- Human judgment is treated as an explicit boundary, while routine navigation
  and execution remain automation targets.
- Runtime tooling grows from consumer evidence rather than hypothetical stack
  abstractions.

Tradeoffs:

- Phase 3 is not complete after the first consumer checkpoint.
- A second task with explicit expected behavior is required to test the runtime
  and interface loop.
- Some useful worktree/runtime improvements may remain consumer-specific and
  never enter the generic core.
- One successful replay does not establish reliability across models,
  repositories, or task classes.

## Follow-Up

- Keep `docs/plans/active/application-legibility.md` current with a P3-01
  through P3-07 evidence matrix.
- Retain the completed e-inna pilot and replay reports as the first checkpoint.
- Select a real consumer task whose expected behavior is already authoritative
  and whose interface/runtime can be exercised locally.
- Record baseline human interventions before adding runtime, fixture, logging,
  or interface support.
- Re-run the frozen task after consumer improvements and compare intervention
  count, reproduction time, focused proof, interface proof, isolation, and
  cleanup.
