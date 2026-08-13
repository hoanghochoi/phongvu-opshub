# Decisions

Record durable decisions that constrain future work. Keep entries short:
context, decision, consequences, and validation impact.

Use `docs/templates/decision.md` for new decisions.

## Current OpsHub Decisions

- `0029-adopt-upstream-repository-protocol-and-retire-protocol-v1.md` records
  the staged upstream Harness cutover and legacy retirement boundary.

The local `harness.db` is a read-only migration/archive input, not a current
decision authority. Record accepted decisions in Git under this directory and
link their implementation/proof to the Linear issue. Protocol-v1/SQLite
producer code is retired; only sanitized migration evidence and historical ADRs
remain in the current tree.
