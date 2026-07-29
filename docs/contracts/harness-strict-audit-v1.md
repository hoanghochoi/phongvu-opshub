# OpsHub Harness Strict Audit v1

Status: consumer/orchestrator contract for OPS-17.

## Intent

This revision-pinned wrapper combines two read-only facts:

1. the canonical schema-12 local strict-audit summary; and
2. the reviewed OPS-15 schema-12 → schema-14 preservation/parity result.

It does not add `audit --strict` to the upstream Rust CLI. It does not migrate,
refresh, import, retire, or write Harness state. It does not create, apply, or
record a changeset.

## Command

```powershell
python scripts/adapter/harness_strict_audit_v1.py `
  --source <wal-safe-schema12-snapshot.db> `
  --target <isolated-schema14-target.db> `
  --fixture tests/fixtures/harness/local-authority-adapter-v1.json `
  --sidecar <projected-sidecar.json> `
  --audit tests/fixtures/harness/local-strict-audit-baseline-v1.json
```

The source must be a WAL-safe snapshot created by the approved adapter flow,
never the writable canonical root database. The target and sidecar must be the
isolated artifacts bound to the same snapshot.

## Input envelope

The audit file is the reviewed, counts-only baseline for exact source revision
`c984d362223d33cf78c9b4874a28723b9a895bfe` and snapshot SHA-256
`dd34da3afd6985e5d5c9c58eebd435863041f96ca3a3daa3eda6aff3566031be`.
It must not contain notes, commands, absolute paths, tokens, or row payloads.

```json
{
  "contract": "opshub-harness-strict-audit-v1",
  "source_revision": "c984d362223d33cf78c9b4874a28723b9a895bfe",
  "schema_version": 12,
  "source_snapshot_sha256": "<64 lowercase hex characters>",
  "audit": {
    "orphaned_stories": 4,
    "unverified_stories": 7,
    "unverified_decisions": 2,
    "stale_stories": 0,
    "open_backlog_items": 27,
    "broken_tools": 0,
    "intakes_without_traces": 70,
    "dangling_intake_links": 3,
    "entropy_score": 100
  },
  "changeset_ids": [],
  "conflict_ids": []
}
```

Every required category must be present and equal the revision-pinned trusted
count. Missing, unknown, changed, negative, boolean, non-integer, or malformed
values fail provenance with exit `78`; values are never inferred as zero. This
binding prevents a caller from replacing known-dirty counts with zeros to
manufacture exit `0`. A changed canonical snapshot requires a reviewed baseline
and contract update before this v1 command can pass provenance.

`source_revision`, `schema_version`, and `source_snapshot_sha256` must equal the
trusted v1 values. Adapter parity must also report the exact reviewed mapped
counts, `result=PASS`, an empty valid `failures` array, and
`changeset_created=false`. Changeset and conflict IDs must be unique, trimmed,
non-empty strings. The wrapper does not open or interpret a changeset payload.

## Output and exit policy

Every run emits one compact JSON object with stable top-level fields:

```json
{
  "contract": "opshub-harness-strict-audit-v1",
  "source_revision": "c984d362223d33cf78c9b4874a28723b9a895bfe",
  "schema_version": 12,
  "audit": {},
  "state_parity": {},
  "changeset_ids": [],
  "conflict_ids": [],
  "exit_code": 0
}
```

Precedence is fail-closed:

| Exit | Meaning |
| --- | --- |
| `78` | Provenance, input, schema, snapshot, sidecar, or state parity is missing/invalid. |
| `3` | Parity passed, but one or more CAS/changeset conflict IDs exist. |
| `2` | Parity passed and no conflict exists, but at least one strict audit category is non-zero. |
| `0` | Parity passed, no conflict exists, and every supplied audit category is zero. |

`state_parity` carries the adapter contract/result, sorted failures, source and
target schemas, source snapshot digest, mapped counts, and
`changeset_created`. A non-empty/malformed failure list, contradictory PASS,
mapped-count drift, or created changeset can never be downgraded by audit
counts. Invalid command arguments and read/adapter errors also emit the stable
JSON envelope with exit `78`; `--help` remains the non-audit help path.

## Write boundary

The wrapper only reads the audit JSON and calls adapter v1 `parity`, whose
source and target connections are read-only. A caller that wants to record
evidence must perform a separate, explicit, reviewed action after the strict
command returns. This contract does not define or authorize that write.
