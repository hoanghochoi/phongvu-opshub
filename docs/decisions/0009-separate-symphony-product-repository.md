# 0009 Separate Symphony Into Its Own Product Repository

Date: 2026-07-11

## Status

Accepted

## Context

`repository-harness` is intended to be a reusable, stack-neutral repository
template. Decision `0003-generic-spec-intake-harness` removed baked-in product
domains so a freshly installed Harness does not confuse an example product with
the target repository's product truth.

Symphony grew inside this repository as the first consumer of Harness stories.
That introduced a second product with its own Rust runtime, React Web UI,
Electron shell, product contract, stories, run state, PR workflow, and release
needs. The shared workspace now causes concrete reverse coupling:

- Harness CLI releases run Symphony's test suite.
- A Symphony dependency change can make post-merge automation bump the Harness
  CLI because both products share `Cargo.toml` and `Cargo.lock`.
- The Harness installer copies README files that link to Symphony files it does
  not install.
- The active local Harness database, tool registry, backlog, and committed
  changesets contain Symphony work, so core development can surface Symphony
  suggestions.
- Repository-local `.codex`, `.agents`, `.impeccable`, `.symphony`, and run
  artifacts add product-specific noise to the template repository.

The separate `git@github.com:hoangnb24/symphony.git` repository and its local
clone at `/Users/themrb/Documents/personal/symphony` are empty, so the split can
preserve history before the target develops an incompatible lineage.

## Decision

Make `hoangnb24/symphony` the canonical product repository for Symphony and
restore `hoangnb24/repository-harness` as the canonical reusable Harness
template and Harness CLI repository.

The separation follows these rules:

1. Use a one-time, provenance-preserving filtered import from the accepted
   source baseline. Do not start Symphony with an untraceable snapshot.
2. Preserve `crates/harness-symphony/` during the first extraction. Path
   flattening is a later refactor, not part of the product split.
3. Symphony depends on a versioned, machine-readable Harness CLI protocol and
   released Harness artifacts. Neither repository uses a path dependency,
   submodule, or copied fork of the other product's source.
4. Harness retains generic capabilities that Symphony helped motivate,
   including isolated database selection, semantic operation logging,
   changeset apply/rebuild, story dependencies and hierarchy, explicit story
   completion, and validation-environment quarantine.
5. Symphony must stop mutating Harness tables directly and stop parsing
   human-oriented CLI output before it is declared independent. All Harness
   writes go through the Harness CLI; supported reads use versioned JSON CLI
   contracts.
6. Bootstrap and validate Symphony in the target before deleting any source,
   docs, or history from `repository-harness`.
7. Tracked live `.harness/changesets` are not a test fixture. Preserve legacy
   evidence through Git history and explicit backups, replace core replay tests
   with small synthetic fixtures, and keep active operational files out of the
   template checkout. Retain the generic consumer template rule that allows a
   consuming repository to commit its own semantic changesets.
8. Do not vendor `.agents/skills/impeccable`, `.codex/hooks.json`, or local
   `.impeccable` consent/configuration in the Harness core. Optional design and
   agent tools must be externally installable and cleanly absent.
9. Merge or publish the working Symphony target first. The Harness removal
   change is gated by standalone parity and a recoverable source tag/bundle.
10. Cross-repository story handoff preserves dependency truth with non-runnable
    source proxies and checksummed target completion receipts. Never retire a
    source row merely to make a dependency appear satisfied.

## Alternatives Considered

1. Keep both products in one workspace. Rejected because reverse release,
   documentation, durable-state, and agent-context coupling already causes the
   product confusion this decision must remove.
2. Copy the current Symphony directory into a new initial commit. Rejected
   because it discards the implementation and review history while the target
   is still empty enough to preserve it safely.
3. Maintain Symphony as a Git submodule or permanent subtree of Harness.
   Rejected because it preserves source-level ownership coupling and makes a
   Harness checkout responsible for Symphony version selection.
4. Move Harness CLI source into Symphony. Rejected because the CLI, schemas,
   installer, and repository operating model are the reusable Harness product.
5. Delete all historical Symphony records immediately. Rejected because an
   irreversible cleanup before target parity would remove the only working
   baseline and destroy useful provenance.

## Consequences

Positive:

- Each repository has one product contract, release cycle, dependency graph,
  backlog, and agent context.
- Harness installations no longer contain broken Symphony guidance.
- Symphony can release its CLI, Web UI, and desktop shell without causing a
  Harness CLI release.
- The runtime dependency becomes explicit and testable instead of relying on
  sibling source layout and SQLite internals.
- Core Harness validation becomes smaller and uses purpose-built fixtures
  instead of replaying product history.

Tradeoffs:

- The split requires coordinated work across two repositories and a temporary
  dual-copy period.
- A public Harness orchestration contract must be designed and supported.
- Legacy changesets and the local database need ownership-aware migration;
  blanket deletion is unsafe.
- Historical docs and changelog entries need an explicit allowlist because the
  word "Symphony" cannot disappear from the decision that records the split.
- Cross-repository compatibility CI becomes necessary.

## Follow-Up

- Execute `docs/stories/epics/E11-symphony-repository-separation/README.md` in
  dependency order.
- Keep the source implementation authoritative until the standalone parity
  gate passes.
- Record any change to the protocol, history policy, or cutover order as an
  amendment or a superseding decision.
