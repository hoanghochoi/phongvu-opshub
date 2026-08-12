# Repository Workflow

Canonical default workflow. Repository product behavior,
architecture, plans, decisions, code, tests, and runtime signals are the system
of record. Optimize for reliable agent execution with minimal human attention
and process overhead.

## Repository Map

- `AGENTS.md`: small entry map and authority boundary.
- `README.md` and `docs/product/`: current product behavior.
- `docs/ARCHITECTURE.md` and `docs/decisions/`: structural constraints and
  lasting decisions.
- `docs/plans/active/`: complex work currently in progress.
- `docs/plans/completed/`: completed execution history worth retaining.
- Project code, tests, CI, and runtime signals: executable and observable truth.
- `scripts/README.md`: upstream Harness development and compatibility commands.

Use `docs/README.md` for the map; prefer targeted search.

## Select The Work Shape

Answer three questions independently; do not let one risk label decide them.

### Does The Work Need Durable Memory?

Use an ephemeral plan for bounded, single-session work.

Create or update one execution plan in `docs/plans/active/` when work:

- is likely to span sessions;
- coordinates multiple agents or contributors;
- has meaningful dependencies or an important sequence;
- requires an explicit recovery procedure; or
- would be unsafe or expensive to resume from the final diff alone.

Use `docs/templates/exec-plan.md`. Keep progress and task-local decisions in the
same file. Do not create parallel story, design, validation, and trace documents
for the same work unless one has independent long-term value.

### Does The Work Need Human Judgment?

Before editing, identify repository authority for each new externally
observable policy. If materially different choices remain open, stop before
edits and request the smallest necessary decision. Configurable defaults are
not authority.

For example, `Add rate limiting` without a quota, trusted key, enforcement
topology, or response contract must stop. `Enforce the documented 20 requests
per minute per authenticated tenant` may proceed.

Also pause when:

- product intent remains ambiguous;
- the action is irreversible or difficult to recover;
- validation, security, or compatibility requirements would be weakened; or
- the requested work does not authorize the necessary action.

### What Proves The Behavior?

Choose proof from the affected behavior:

- focused tests for local rules;
- integration tests for persistence and service boundaries;
- end-to-end interaction for user-visible behavior;
- recovery rehearsal for migrations and destructive operations; and
- runtime measurements for reliability or performance claims.

Harness rows, proof flags, trace tiers, context scores, and entropy scores do not
prove product behavior by themselves.

## Task Flows

### Read-Only Request

For an answer, explanation, review, diagnosis, plan, or status report:

1. Read `AGENTS.md` and only the material needed for the response.
2. Use read-only inspection commands when useful.
3. Do not edit files or mutate Harness state.
4. Stop when concrete repository evidence supports the answer.

Discovery never grants authority to fix what it finds.

### Explicit Issue Delivery Command

When the user explicitly commands the agent to `xử lý issue`, treat that as
authority to complete the normal issue delivery flow without pausing after
implementation:

1. Read the Linear issue and implement against its accepted product, design,
   permission, security, platform, and affected-consumer authority.
2. Run the issue's focused proof and repository-required validation. Continue
   only when every required gate passes and the exact changeset remains current.
3. Re-inspect the diff, commit it on the issue task branch, and push that task
   branch. Never use this flow for a direct push to `staging` or `main`.
4. Open a feature PR to `staging`, using the required issue-linked title/body,
   then wait for required CI and review. Remediate failures and rerun stale
   proof before proceeding.
5. Squash-merge the approved PR into `staging` only after all merge gates pass.
   This flow never authorizes a production promotion.
6. From the clean canonical `staging` worktree, run
   `scripts/task-lifecycle.mjs finish` as a dry-run and then rerun it with
   `--execute`. Stop fail-closed if either lifecycle gate fails.

Publication authority in this command is limited to the task branch, its PR,
the guarded squash merge into `staging`, and local lifecycle cleanup. It does
not waive Linear intake, Figma approval, tests, affected-consumer proof,
security/review, CI, clean-worktree, exact-SHA, or release gates. Record
implementation/proof in Linear before a forward status transition, and never
mark an issue `Done` before a verified production deployment.

### Bounded Change

1. Restate the observable outcome.
2. Read the relevant product or design material, affected code, adjacent
   patterns, and existing tests.
3. Make the smallest coherent change that satisfies the outcome.
4. Run focused proof plus repository-required checks.
5. Report the outcome, important changed surfaces, proof, and known limitations.

No bootstrap, intake, story, matrix, trace, scoring, audit, or proposal command
is required.

### Durable Planned Change

1. Create or resume one plan in `docs/plans/active/`.
2. Record outcome, context, approach, risks, recovery, progress, decisions, and
   validation in that file.
3. Implement in coherent, independently verifiable groups.
4. Update progress and decisions as reality changes.
5. Run the plan's focused and repository-wide proof.
6. Promote lasting product or architecture decisions into `docs/decisions/`.
7. Record the final result and move the plan to `docs/plans/completed/`.

The plan is working memory, not a prediction frozen at intake. Update it when
evidence changes the approach.

## Completion Standard

A change is complete only when:

- the requested outcome exists or the blocker is explicit;
- relevant product and design truth remains current;
- behavior-appropriate proof has passed, or missing proof is disclosed without
  overstating completion;
- durable plan progress and result are current when a plan was required; and
- the final report separates verified facts, limitations, and unattempted work.

Git history, pull-request discussion, test artifacts, screenshots, videos,
logs, metrics, and plan progress are preferred evidence because they arise from
the work. Manual descriptions may add context but do not replace observed proof.

## Legacy Compatibility Boundary

The Rust CLI and SQLite durable layer remain retained only as read-only
migration/archive evidence until the OPS-64 retirement gate passes. They are not
current task, product or release authority. Do not initialize, refresh, compact,
import or write `harness.db` from this upstream-aligned branch. The legacy CLI
may be used only against a disposable WAL-safe archive copy for read/export
proof.
<!-- Legacy command details are retained in migration documents until Phase 5. -->
If a migration or archive check explicitly needs the legacy CLI, point it at a
disposable WAL-safe archive copy and record the exact artifact/checksum. Current
repository validation uses `scripts/verify-task.mjs`; upstream Harness owns only
repository install/update/status/doctor operations.
