# Harness

Harness makes a repository legible and operable to coding agents so humans can
specify intent and agents can execute reliable work with minimal supervision.

The app is what users touch. The harness is the repository knowledge, tools,
constraints, and feedback loops that let agents understand and improve it.

The canonical task flow is in `docs/WORKFLOW.md`.

For an ordinary repository task, start from the requested outcome and use the
smallest relevant product, code, and validation authority.

## Mental Model

```text
human intent
  -> small repository map
  -> relevant product and design truth
  -> real code, application, and development tools
  -> implementation inside mechanical boundaries
  -> executable or observable validation
  -> Git-visible result and durable decisions when warranted
  -> targeted cleanup when repeated problems become enforceable rules
```

Human time and attention are the scarce resources. Harness capabilities should
reduce repeated explanation, manual reproduction, review, or recovery. A
capability that produces more process records without improving execution or
proof is not part of the default path.

## Core Responsibilities

### Repository Map

`AGENTS.md` is a compact table of contents and authority boundary. It points to
the workflow and repository truth; it does not attempt to contain every rule.

### Repository Knowledge

Knowledge that agents need should be versioned and discoverable:

- product behavior in the README and `docs/product/`;
- architecture in `docs/ARCHITECTURE.md`;
- lasting decisions in `docs/decisions/`;
- active and completed complex work in `docs/plans/`;
- development and compatibility commands in `scripts/README.md`; and
- executable truth in code, tests, CI, schemas, and generated references.

Prefer an index and progressive disclosure over a monolithic manual.

### Application Legibility

The highest-value Harness tools let an agent operate the real system: start an
isolated instance, reproduce a bug, drive user-visible behavior, inspect logs
and metrics, run focused checks, and observe the result. Installed consumers
define stack-specific commands as their applications emerge.

Harness must not fabricate generic commands and claim they passed. When a
validation or observability capability is missing, report the concrete gap.

### Mechanical Invariants

Encode important, repeatable boundaries in tests, linters, schemas, and CI.
Enforce architecture and correctness constraints while leaving local
implementation choices flexible.

Good invariants include dependency direction, boundary parsing, structured
logging, schema integrity, naming rules, file-size limits, and platform-specific
reliability requirements when the project actually needs them. Error messages
should tell an agent how to remediate the violation.

### Durable Planning

Bounded changes use ephemeral plans. Complex or multi-session work uses one
evolving plan under `docs/plans/active/`. The plan carries progress, task-local
decisions, validation, and recovery. Move it to `docs/plans/completed/` only
after recording the result.

Promote a decision into `docs/decisions/` only when future work needs to inherit
it independently of the plan.

### Garbage Collection

Repeated defects should become targeted repository improvements: a clearer
index, an application-facing tool, a mechanical rule, or a bounded cleanup.
Prefer recurring agents that find concrete violations and open focused fixes
over a self-referential backlog of process metadata.

## Default Request Flows

### Read-Only

Answers, explanations, reviews, diagnoses, plans, and status reports inspect
only the material needed for an evidence-backed response. They do not edit files
or mutate Harness state.

### Bounded Change

Restate the observable outcome, read the relevant repository truth, inspect the
affected implementation and proof, make the change, run behavior-appropriate
validation, and report the result. No control-plane operation is required.

### Durable Planned Change

Create or resume one active plan, update it as evidence changes the approach,
implement in coherent groups, validate the outcome, promote lasting decisions,
and move the completed plan to history.

### Human Judgment

Pause only when intent is ambiguous, alternatives have materially different
product consequences, the action is difficult to recover, validation would be
weakened, or the requested authority is insufficient.

## Source Hierarchy

```text
explicit user intent and accepted product direction
  -> current product contract
  -> current architecture and durable decisions
  -> active execution plan for complex work
  -> implementation, tests, schemas, CI, and observable runtime behavior
  -> completed plans and historical evidence
```

When sources conflict, prefer current accepted behavior and executable evidence
over historical plans or compatibility records. Correct or clearly demote stale
material instead of adding another parallel truth.

## Completion

A change is complete when:

- the requested behavior exists or the blocker is explicit;
- relevant repository truth is current;
- suitable executable or observable proof has passed, or missing proof is
  disclosed without overstating the result;
- the active plan is current when the work required one; and
- the final report identifies the outcome, important changed surfaces,
  validation, limitations, and unattempted work.

Git diffs, tests, CI, application interaction, screenshots, logs, metrics, and
plan progress are evidence. Manually filled process fields are commentary.

## End-Of-Life Boundary

The former SQLite `harness-cli` and machine protocol v1 are historical
products. They are available only from immutable historical Git tags and the
sanitized migration evidence under `docs/migrations/`. The current tree does
not build, install, test, publish, or use that control plane.

The local `harness.db`, WAL/SHM files, downloaded legacy binaries, and raw
archive copies are consumer-owned read-only migration inputs. This repository
does not import, refresh, rewrite, or delete them. Current behavior and
accepted decisions live in Git and Linear, not in a legacy database.

The current local interface is the upstream `harness` maintenance binary:

```text
scripts/bin/harness status [--json]
scripts/bin/harness doctor [--json]
scripts/bin/harness update --dry-run
scripts/bin/harness update
scripts/bin/harness update --continue --dry-run
scripts/bin/harness update --continue
scripts/bin/harness update --abort
```

`scripts/verify-task.mjs` owns changed-path and affected-consumer proof for
OpsHub. It is separate from the upstream repository updater and does not write
Harness state.

### Upstream updater blocked-upstream runbook

If `status --json` and `doctor --json` pass but `update --dry-run` stops while
merging customized repository guidance, classify the result as
`blocked-upstream` and preserve the no-write boundary. Git's `merge-file`
conflict exit is a hunk count in the range `1..=127`; an upstream adapter that
accepts only exit `1` can therefore misclassify a conflict as a hard updater
failure. The sanitized evidence for this boundary is
`docs/migrations/ops-189-updater-blocked-upstream.json` and its contract is
checked with:

```text
node scripts/verify-harness-updater-blocked.mjs
```

Until a tagged upstream release contains the exit-range fix, do not bump the
release pin, patch the downloaded binary, fork the upstream core, or run an
update against the source archive. Reproduce the lifecycle only in a
disposable consumer copy, retain source/binary hashes before and after a
dry-run, and use `update --abort` when a transaction has actually started.
Network failures such as a release lookup `429` are also recorded as
fail-closed observations; they are not evidence that the updater is healthy.

## Consumer Boundary

Installing Harness does not select a consumer application's stack, create fake
product domains, or invent validation commands. A consumer starts with the
repository map, workflow, documentation structure, compatibility tooling, and
templates. Product knowledge and executable capabilities are added only from
real accepted work.
