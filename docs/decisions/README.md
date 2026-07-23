# Decisions

Record durable decisions that constrain future work. Keep entries short:
context, decision, consequences, and validation impact.

Use `docs/templates/decision.md` for new decisions.

When the authoritative local `harness.db` is initialized, also record
meaningful decisions with the approved local compatibility adapter so the
decision list is queryable. The legacy wrapper is currently available only in
the root workspace; use the upstream CLI only after an approved schema/state
adapter is committed.
