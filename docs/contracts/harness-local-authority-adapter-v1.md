# Harness Local-Authority Adapter v1

Status: implementation proof only (OPS-15). This contract is not a Harness
core fork and it does not authorize a changeset, a database migration, or a
pull request.

## Intent

The OpsHub project already has historical Harness state in the local schema-12
database. The upstream CLI currently executes against schema 14. The adapter
provides a lossless, preservation-first projection for a disposable schema-14
target while keeping the local database and project Markdown authoritative.

The source is read-only. The target is an isolated database created outside the
repository. The adapter must never run `import brownfield`, `migrate`, or any
write command against the authoritative local database.

## Authority and snapshot rules

1. Take the source with `harness-cli db snapshot --output <path> --json`; a raw
   `Copy-Item harness.db` is not a valid source snapshot because WAL pages may
   not be included.
2. Bind the proof to the snapshot file SHA-256, source schema version `12`,
   the per-table canonical row digests, and the root database file SHA-256 as
   evidence only. The root file is never opened for write.
3. The committed golden fixture is digest-only and contains no notes, commands,
   absolute paths, tokens, or other row payloads. The complete snapshot and
   sidecar are retained in the external proof-artifact directory.
4. A source digest mismatch is fail-closed. The adapter does not “refresh” the
   fixture and does not guess whether a changed row is harmless.

## Target requirements

The target must already be initialized by the pinned upstream CLI and report
schema `14` through `query contract --json`. It must be empty for all source
tables before projection. Existing target rows are a hard failure; the adapter
does not overwrite or merge them.

Projection is one SQLite transaction. Any constraint or mapping failure rolls
the target back to its pre-projection state. The source and target are separate
files, so rollback cannot affect the source.

## Field mapping

| Local schema-12 entity | Schema-14 projection | Preservation rule |
| --- | --- | --- |
| `intake` | Common fields copied; deterministic `uid=ops15.local.intake.<id>` | `bug_fix` is projected to upstream-compatible `change_request`; the original enum and row IDs are recorded in the sidecar. `checkpoint_*` fields are sidecar-only. |
| `story` | Common fields copied; `revision=0` | `path_contracts`, `affected_verify_command`, and all `last_affected_*` fields are sidecar-only. No proof/status field is rewritten. |
| `decision` | Common fields copied; `revision=0` | All local values are copied exactly. |
| `backlog` | Common fields copied; `uid=ops15.local.backlog.<id>`, `revision=0` | Local `kind` is sidecar-only. Upstream proposal/outcome fields are left `NULL`; they are not inferred from old prose. |
| `trace` | Common fields copied; `uid=ops15.local.trace.<id>`, `intake_uid` derived from `intake_id` | `recorded_at_unix_ns` is `NULL` because the local timestamp precision/zone is not authoritative for a new upstream field. The original `created_at` remains unchanged. |
| `tool` | Common fields copied; `revision=0` | All local values are copied exactly. |
| `intervention` | Common fields copied; `uid=ops15.local.intervention.<id>` | All local values are copied exactly. |
| `changeset_applied` | Common fields copied; `content_sha256=NULL` when absent locally | The source is currently empty. A future non-empty row must keep the local ID/path/time in the sidecar; no content hash may be invented. |
| `story_dependency`, `story_hierarchy` | Rows copied exactly | Foreign-key and self-link constraints are checked by the target transaction. |
| upstream-only tables (`audit_evidence_episode`, `legacy_evidence_snapshot`, proposal/outcome links, etc.) | No synthetic rows | They remain empty until a later, explicitly reviewed policy adapter has evidence to populate them. |

The adapter preserves row order for comparison by primary key (or `rowid` only
when a table has no primary key). JSON text is hashed as UTF-8 with sorted keys,
compact separators, and no trailing record delimiter.

## Sidecar contract

The sidecar is an external, immutable companion to the target snapshot. It
contains:

- the adapter contract and source snapshot SHA;
- a digest for every local-only column projection;
- every `bug_fix` source ID/digest and its explicit `change_request`
  compatibility projection.

The sidecar is not a replacement database and is not a changeset. A consumer
must refuse to claim parity if the sidecar is absent, has a different digest,
or is not bound to the same source snapshot.

## Proof gates

`harness_local_authority_v1.py parity` must pass all gates:

1. source snapshot file SHA and schema 12 match the committed golden fixture;
2. SQLite integrity and foreign-key checks pass;
3. every source table count, column list, and canonical row digest matches;
4. target schema 14 and required tables are present and valid;
5. every mapped common field matches after the one explicit enum projection;
6. deterministic UIDs and intake-to-trace UID links are stable;
7. sidecar content matches the fixture and the source snapshot;
8. the result reports `changeset_created=false`.

Failure codes are fail-closed (`SOURCE_*`, `TARGET_*`, `SIDECAR_*`, or
`TARGET_VALUE_MISMATCH`). A tampered source, target, fixture, or sidecar must
produce a non-zero exit without modifying the authoritative database.

## Follow-up boundary

Only after this contract and proof pass may a separate change propose a strict
consumer/orchestrator wrapper. That wrapper must keep local strict audit
semantics, define its own evidence policy, and use a reviewed adapter output;
it must not add `audit --strict` to the upstream CLI or alter upstream Rust
logic. Changeset generation/application and a PR are separate approved steps.
