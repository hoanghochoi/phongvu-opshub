# 0010 Proof Before Harness CLI Release Promotion

Date: 2026-07-13

## Status

Accepted

## Context

Post-merge run `29222332569` built and smoke-tested Harness CLI `0.1.16` on
all five supported platforms, but every build job later failed while applying
the current protocol smoke to the immutable `0.1.14` upgrade-source binary.
The current smoke requires SQL and story-completion protections that did not
exist in `0.1.14`, so it is not a valid historical compatibility baseline.

The maintenance workflow had already pushed `harness-cli-v0.1.16` before the
matrix ran. The failed validation therefore left an immutable-looking tag with
no GitHub Release or artifacts. Moving that tag would make source identity
ambiguous for consumers that already observed it.

## Decision

Harness CLI release automation uses two separate proof contracts:

1. The pinned initial upgrade-source artifact runs a frozen baseline containing
   only behavior promised by that version.
2. The built and installed candidate runs the current full protocol and
   installer contract.

Post-merge maintenance may prepare a versioned candidate commit, but it must not
create the release tag. The reusable release workflow builds and validates that
exact commit across every supported platform. Only after all matrix jobs pass
may the publish job create the annotated tag at the proven commit and publish
the matching artifacts.

Candidate identity verification requires the requested tag version to equal
the crate version. If the tag already exists, it must resolve to the candidate
commit. An absent tag is allowed only for the explicit post-merge candidate
path; tag-push and ordinary manual release paths remain strict.

Failed release tags are never moved or deleted automatically. Recovery advances
to a new patch version. For run `29222332569`, `harness-cli-v0.1.16` remains at
its original commit without release assets and the corrected flow publishes a
later patch version.

## Alternatives Considered

1. Retag `harness-cli-v0.1.16` after fixing the workflow. Rejected because an
   externally visible release identity must be immutable.
2. Remove all checks of the initial artifact. Rejected because checksum,
   executability, protocol discovery, and upgrade-source identity are still
   meaningful compatibility proof.
3. Keep creating the tag before the matrix and delete it on failure. Rejected
   because cleanup races with observers and turns a failed validation into a
   destructive external action.
4. Run the evolving current smoke against every historical binary. Rejected
   because new safety requirements describe the candidate, not retroactive
   behavior of an immutable upgrade source.

## Consequences

Positive:

- A published tag identifies a candidate that passed every platform gate.
- Historical compatibility checks cannot fail merely because the current
  contract gained a new guarantee.
- Candidate and installed-candidate proof still exercise all current safety
  requirements.
- Failed tags remain auditable and are recovered through monotonic versions.

Tradeoffs:

- Release verification needs an explicit unpublished-candidate identity mode.
- The frozen baseline must remain intentionally small and version-specific.
- A publish API failure can still occur after tag creation, but compilation or
  platform validation can no longer strand a tag.

## Follow-Up

- Keep the initial compatibility tag and frozen assertions named explicitly in
  release tests.
- Run one Linux and one Windows old-to-candidate transition before merge.
- Treat release workflow, identity, and compatibility-test changes as
  release-affecting so a correction can produce a new patch release.
