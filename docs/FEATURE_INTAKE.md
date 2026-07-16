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
| Weak proof | unclear or missing tests around the affected area |
| Multi-domain | more than one product domain changes at once |

## Lanes

| Lane | Use when | Requirements |
| --- | --- | --- |
| Tiny | 0-1 flags and narrow blast radius | Patch directly, run quick proof |
| Normal | bounded behavior change or 2-3 flags | Story packet, test matrix update, relevant tests |
| High-risk | hard gate or 4+ flags | High-risk story folder, design/validation plan, human confirmation if direction is ambiguous |

Hard gates default to high-risk: auth, authorization, data loss or migration,
audit/security, external provider behavior, and removing validation.

## Output Shape

Before implementation, be able to say:

```text
Lane: normal
Reason: touches API contract and existing FIFO behavior.
Docs: docs/product/fifo.md
Story: docs/stories/US-XXX-name.md
Validation: Flutter tests plus NestJS unit tests.
```

When the durable harness DB is initialized, record normal/high-risk work with
`scripts/harness intake ...` and update proof with `scripts/harness story ...`
instead of editing structured status by hand. Markdown product docs and story
packets remain the readable contract; the DB stores queryable operational
records.

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
- Proof status, 2026-07-17: `staging_verified`. All minimum proof passed on the
  staging release ending at `ad7efa03`; 60 synthetic users were revoked/deleted
  with zero remaining records and all raw artifacts removed. Production
  promotion still requires the normal deploy workflow and passive stability
  observation.
