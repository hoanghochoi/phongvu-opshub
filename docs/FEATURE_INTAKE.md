# Feature Intake

Every implementation prompt enters this gate before code changes. A new project
spec also enters through this gate before it becomes product docs, stories, or
implementation work.

The human does not need to classify risk. The harness does.

## Intake Flow

```text
User prompt
    |
    v
Classify input type
    |
    v
Restate as work item
    |
    v
Find affected product docs and stories
    |
    v
Run risk checklist
    |
    v
Choose lane: tiny, normal, or high-risk
    |
    v
Capture Git/worktree checkpoint and map protected old consumers
    |
    v
Record durable intake/proof when useful
```

## Input Types

| Type | Use when | Typical artifact |
| --- | --- | --- |
| Change request | Changing accepted app behavior | Story packet or direct patch |
| Bug fix | Restoring intended behavior | Direct patch or story if risky |
| New spec | Turning a user-provided project spec into harness-ready docs | Product docs, candidate epics, decisions |
| Spec slice | Implementing selected behavior from an accepted spec | Story packet |
| New initiative | Adding a larger product area | Product doc plus story packets |
| Maintenance | Dependency, infra, performance, security, or tooling work | Story, validation report, or decision |
| Documentation | Clarifying existing truth | Direct docs patch |
| Harness improvement | Improving this workflow | Direct harness patch or backlog item |

## Risk Flags

Mark every flag that applies.

| Flag | Applies when work touches |
| --- | --- |
| Auth | login, logout, sessions, JWT, password auth |
| Authorization | staff scope, admin access, allowed domains, roles |
| Data model | Prisma schema, migrations, uniqueness, deletion, retention |
| Audit/security | sensitive data, access logs, upload paths, service accounts |
| External systems | BigQuery, Redis, Google APIs, file storage, provider SDKs |
| Public contracts | API shape, response envelope, mobile-visible behavior |
| Cross-platform | Android, iOS, web, desktop, deep links, permissions |
| Existing behavior | changing a flow already used by staff |
| Shared runtime | auth/session context, guards, routing, throttling, shared shell/navigation, shared providers or scope resolution |
| Background pipeline | cron, queue, worker startup order, retries, reconciliation or cache refresh |
| Upgrade state | old sessions, old database rows, partial migrations, rolling replicas or data created by an earlier build |
| Runtime artifact | config/env, CSV/assets, generated client, mounted path, package manifest or deploy-time file |
| Weak proof | unclear or missing tests around the affected area |
| Multi-domain | more than one product domain changes at once |

## Lanes

| Lane | Use when | Requirements |
| --- | --- | --- |
| Tiny | 0-1 flags and narrow blast radius | Patch directly, run quick proof |
| Normal | bounded behavior change or 2-3 flags | Story packet, test matrix update, relevant tests |
| High-risk | hard gate or 4+ flags | High-risk story folder, design/validation plan, human confirmation if direction is ambiguous |

Hard gates default to high-risk: auth, authorization, data loss or migration,
audit/security, external provider behavior, shared runtime chokepoints, upgrade
state, background startup ordering, runtime artifacts, and removing validation.

## Protected Existing Behavior

Before editing normal/high-risk runtime work, list both the new behavior and the
old behavior that must continue working. Map changed paths to durable story
contracts with `--paths` and focused consumer proof with `--affected-verify`.
Examples of old-state proof include:

- Auth producer plus Flutter bootstrap/session consumer, including old saved
  sessions and Redis/cache failure modes.
- Shared MAP provider plus Payment Monitor, Sao ke, and VietQR consumers.
- Shared app shell plus every existing navigation destination and compact-screen
  geometry.
- Migration on a fresh database, an upgraded database, and a recoverable partial
  failure fixture.
- Worker/projection changes across Vietnam-day boundaries, startup ordering, and
  post-deploy reconciliation.
- Deploy/package changes against a built artifact manifest, not only source-tree
  existence.

An unmatched runtime or verification path in a high-risk intake is a planning
failure. Add the contract owner and proof before implementation; do not
downgrade the lane or weaken/delete an old test to make the gate green.
A rename counts as deletion of the old path plus addition of the new path; both
sides must map to the contracts whose behavior they can affect.

## Output Shape

Before implementation, be able to say:

```text
Lane: normal
Reason: touches API contract and existing FIFO behavior.
Docs: docs/product/fifo.md
Story: docs/stories/US-XXX-name.md
Validation: Flutter tests plus NestJS unit tests.
Protected behavior: existing FIFO list and detail consumers.
Affected guard: path contracts mapped; focused proof command selected.
```

When the durable harness DB is initialized, record normal/high-risk work with
`scripts/harness intake ...` and update proof with `scripts/harness story ...`
instead of editing structured status by hand. Markdown product docs and story
packets remain the readable contract; the DB stores queryable operational
records.

On Windows PowerShell, use the Git for Windows login shell explicitly for the
whole sequence. The checkpoint and proof fingerprint cover branch/HEAD,
worktree blobs, staged/index state, Git-normalized modes/deletions, guard source,
story contracts/commands/status, and the intake checkpoint:

```powershell
$gitBash = "${env:ProgramFiles}\Git\bin\bash.exe"
& $gitBash --login scripts/harness intake --type <type> --summary <text> --lane <lane> --story <id>
& $gitBash --login scripts/harness story update --id <id> --paths '<csv-globs>' --affected-verify '<command>'
& $gitBash --login scripts/harness story verify-affected --intake <id> --strict
# implement
& $gitBash --login scripts/harness story verify-affected --intake <id> --run --record --strict
& $gitBash --login scripts/harness story verify-affected --intake <id> --check --strict
```

With Codex configured as `Agent environment = Windows native`, the agent keeps
the PowerShell/Git-Bash route even if the integrated terminal is WSL. A person
working inside that WSL terminal may use `bash scripts/harness` for read-only
`doctor`, `query`, and `audit`, plus `bash scripts/validate ...`. Arbitrary
stored proof commands are not automatically WSL-safe, so do not move an intake
between execution backends; keep `--run --record` and final `--check` on the
Windows-native Git Bash route unless every affected command uses a reviewed
cross-platform wrapper.

Run the final `--check --strict` only after the last source, test, documentation,
contract, and Harness edit. Any later participating change makes the proof stale.

## Active high-risk intake: AUTH-CONTEXT-001

- Type: maintenance/performance.
- Domains: auth, authorization, PostgreSQL, Redis, realtime, Home scopes and
  multi-replica deployment.
- Risk flags: Auth, Authorization, Data model, Audit/security, External
  systems, Public contracts, Existing behavior and Multi-domain.
- Minimum proof: backward-compatible route tests, atomic access-version
  migration test, Redis outage and cross-replica cache proof, staging smoke,
  ladder `25 -> 50 -> 100 QPS`, Node/PostgreSQL profiling and mandatory
  synthetic-user cleanup before production promotion is considered.
- Proof status, 2026-07-17: performance work `staging_verified`, production
  hotfix `local_verified`. All minimum proof passed on the staging release
  ending at `ad7efa03`; 60 synthetic users were revoked/deleted
  with zero remaining records and all raw artifacts removed. Production
  promotion was attempted at `62f204a` and rolled back application-first to
  `1b174205` after build `100127` rejected the otherwise successful bootstrap
  response because its user projection omitted authenticated identity. The
  two-layer contract/session hotfix is `local_verified`: Flutter analyze, 545
  tests with 3 skips, Nest build, 73 suites/720 tests, Go 62 tests/vet, Windows
  debug build, Android staging debug build and diff check passed. A fresh
  staging upgrade smoke and passive observation remain mandatory before
  production is promoted again.
