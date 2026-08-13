# Test Suite Map

Use this map to answer four questions before changing or deleting a test:

1. What behavior does it protect?
2. Who observes the failure?
3. Which validation entry point invokes it?
4. What product or compatibility boundary must disappear before the test can
   be removed?

The normal entry point is `scripts/validate-premerge.sh`. It runs the
retirement ledger, generic verification, migration evidence, documentation,
and repository workflow contracts. Upstream Harness release/installer tests
run in the upstream repository; OpsHub keeps only the consumer boundary and
migration proof here.

## Current Core

| Location | Protects | Failure visible to | Invocation | Removal boundary |
| --- | --- | --- | --- | --- |
| Upstream `harness` release checks | Core installation, provenance, status/doctor, and agent-resolvable three-way updates | Every default Harness installation | Disposable `harness-v0.1.8` smoke recorded in the active plan | Keep in the upstream repository; OpsHub does not fork or publish core tests |
| `tests/workflow/` | Repository-centered read-only, bounded, durable-plan, and authority behavior | Agents and maintainers using the default workflow | Directly from `scripts/validate-premerge.sh` | Replace only with stronger real-agent outcome evaluation |
| `tests/docs/test-doc-contracts.sh` | Current authority, documentation indexes, installation boundaries, and validation entry points remain coherent | Contributors and installed-core maintainers | Directly from `scripts/validate-premerge.sh` | Remove only after equivalent link and authority checks exist elsewhere |
| `scripts/verify-harness-retirement.mjs` | Every retired producer path has an explicit disposition and staged deletions cannot evade the ledger | OpsHub migration maintainers | Directly from `scripts/validate-premerge.sh` | Keep with the migration evidence |

## Retired Compatibility Proof

SQLite schemas, snapshots, changesets, protocol-v1 commands, and `harness-cli`
release tests were retired in OPS-70 after archive/disposition and upstream
adoption gates. Their source remains available through Git history and the
sanitized migration manifest; it is not run by the current product.

## Historical Migration Proof

One-time E11 repository-separation and cutover executables were removed after
their caller audit found no current pre-merge, release-workflow, installed
payload, or protocol requirement. Their completed plans, frozen evidence, and
Git history retain the historical result without making the old verifiers look
like current product tests.

Removed groups include `tests/cutover/`, `tests/history/`, E11-specific boundary
allowlists, and `scripts/e11-*` / `scripts/verify-e11-*`. Reintroducing one
requires a current observable invariant and a normal validation entry point;
historical provenance alone is insufficient.

## Shared Support

- `tests/fixtures/` contains product and verification fixtures; it is not an
  independently executable suite.
- `tests/*/assert-*.sh` scripts are helpers. A zero direct-reference count does
  not prove they are unused because wrappers may resolve them relative to their
  own directory.

When adding a test, place it under the product boundary it protects and update
this map. Avoid phase-number names for new tests; name the observable invariant
instead.
