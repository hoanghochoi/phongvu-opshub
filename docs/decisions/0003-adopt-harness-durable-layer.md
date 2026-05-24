# 0003 Adopt Harness Durable Layer

Date: 2026-05-24

## Status

accepted

## Context

OpsHub already adopted the Harness markdown workflow, but ongoing FIFO,
warranty, deployment, and release work creates repeated operational state:
intakes, story proof, decisions, backlog items, and traces. Keeping all of this
only in markdown makes query and evidence updates fragile.

The upstream `harness-experimental` workflow now includes a durable SQLite layer
and the stable `scripts/harness` entrypoint.

## Decision

Adopt the durable layer for OpsHub as an adapted merge:

- Keep OpsHub-specific `AGENTS.md`, product docs, stories, decisions, and test
  matrix as the readable source of truth.
- Add `scripts/harness` and `scripts/schema/001-init.sql`.
- Store generated operational state in local `harness.db`, ignored by git.
- Do not copy upstream Rust source, generic demo decisions, or release tooling
  into OpsHub.
- Keep `scripts/bin/harness-cli` optional and ignored. The shell wrapper may use
  it when present, but can fall back to `sqlite3`.

## Consequences

- Agents can query and record structured harness state through
  `scripts/harness`.
- Existing markdown remains useful for review and code navigation.
- OpsHub avoids generic upstream decision history that would confuse local
  architecture records.
- Each checkout initializes/imports its own local durable DB.

## Validation Impact

Docs-only and harness changes should run:

```bash
scripts/harness init
scripts/harness import brownfield
scripts/harness query matrix
git diff --check
```
