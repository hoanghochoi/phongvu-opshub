# 0022 Control-Plane Freeze And Compatibility Runway

Date: 2026-07-21

## Status

Accepted and active. Reduction Phase 4 completed the decision on 2026-07-21;
the explicit compatibility boundary remains current policy.

## Context

Decisions 0019 through 0021 moved ordinary work to repository-native product,
design, plan, decision, code, test, and runtime evidence. The default install no
longer contains the Rust CLI or SQLite lifecycle, but the source repository
still maintains a writable upstream database, tracked reconstruction inputs,
legacy lifecycle commands, and a published protocol used by optional external
orchestration.

The current ignored database illustrates the split. It still contains planned
self-improvement stories, proposed backlog work, manual traces, interventions,
and decision rows that are not present in the current Git-native indexes. Those
records are valuable history and compatibility evidence. Treating them as the
current roadmap would contradict the repository-centered workflow; mutating
them merely to match the new model would rewrite historical facts.

An immediate write shutdown would also be unsafe. Protocol v1 advertises story,
dependency, hierarchy, changeset, and isolated-database mutation capabilities.
External consumers selected that contract explicitly and need a migration path
before any behavior is rejected.

## Decision

Reduction Phase 4 freezes the SQLite control plane through a staged,
compatibility-first runway.

1. Current repository authority comes from Git-native product documents,
   architecture, active plans, current decisions, code, tests, CI, and runtime
   evidence. SQLite row status does not reactivate work absent from those
   surfaces.
2. Existing databases, tracked snapshots, changesets, schemas, and historical
   rows remain readable and reconstructable. The freeze does not rewrite or
   delete history.
3. Intake, manual trace, intervention, backlog/proposal, tool-registry, durable
   decision-row, and human-operated story lifecycle mutations are legacy
   lifecycle writes. They are not used for new upstream repository work.
4. Read-only queries, initialization/migration, integrity/rebuild operations,
   and published protocol-v1 orchestration remain supported during the runway.
5. A human-oriented legacy lifecycle mutation targeting the upstream default
   database is rejected before a write transaction unless the maintainer adds
   the global `--compatibility-write` flag. An explicitly selected write warns
   and then retains the existing mutation and semantic-capture behavior.
6. Machine JSON operations, isolated database fixtures, explicit database
   paths, installed consumers, read operations, and maintenance/recovery remain
   behaviorally unchanged.
7. Direct consumer inventory is recorded in
   `docs/compatibility/phase-4-write-consumer-inventory.md`. It proves that
   protocol-v1 and explicit CLI-profile consumers still require the
   implementation, so schema removal, state compaction, and code deletion are
   outside the completed Phase 4 boundary.
8. The old Phase 4 mechanical-verification roadmap is compatibility history.
   The active Phase 4 objective is this control-plane freeze.

The staged sequence is:

```text
repository-centered default already active
  -> warn on new upstream legacy lifecycle writes
  -> inventory real compatibility consumers and required mutations
  -> export any still-current authority to Git-native surfaces
  -> require explicit compatibility intent
  -> freeze obsolete writes
  -> retain compatibility implementation while supported consumers exist
```

## Alternatives Considered

1. **Delete the CLI and database now.** Rejected because it would strand
   historical state and break a published external protocol without migration.
2. **Keep compatibility indefinitely without a freeze signal.** Rejected
   because new upstream lifecycle rows would continue extending the dual-truth
   system after the default workflow had rejected it.
3. **Mark every old open row implemented or rejected.** Rejected because status
   rewriting would manufacture historical outcomes. Authority can move without
   falsifying the old record.
4. **Warn every installed CLI user.** Rejected for the first stage because
   explicit CLI-profile installation already expresses compatibility intent and
   indiscriminate warnings would disrupt consumers without improving the source
   migration.
5. **Change protocol v1 immediately.** Rejected because deprecation and
   migration must precede a breaking protocol decision.

## Consequences

Positive:

- New upstream work has one inspectable Git-native authority path.
- Existing data remains recoverable and queryable.
- The source repository receives an immediate signal when it starts extending
  the superseded lifecycle.
- External orchestration keeps its published behavior during the runway.
- Later deletion can be based on observed usage rather than assumption.

Tradeoffs:

- The compatibility implementation and its tests remain sizable during the
  runway.
- Explicit compatibility maintenance remains possible, but it is visible in
  the command line and stderr rather than occurring accidentally.
- Current Git and historical SQLite status intentionally differ.
- A separate consumer migration decision will be needed before protocol writes
  can be removed or relocated.

## Follow-Up

- Retain the inventory and native-artifact boundary test as release evidence.
- Revisit implementation deletion only if direct consumer evidence changes and
  a versioned migration plus recovery rehearsal exists.
