# Feature Intake

Every implementation prompt enters this gate before code changes.

## Input Types

| Type | Use when | Typical artifact |
| --- | --- | --- |
| Change request | Changing accepted app behavior | Story packet or direct patch |
| Bug fix | Restoring intended behavior | Direct patch or story if risky |
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
