#!/usr/bin/env python3
"""Preservation-first local Harness schema-12 -> upstream schema-14 adapter.

The adapter deliberately operates on an isolated target database.  It never
opens the authoritative local database for writing and it never emits or
applies a Harness changeset.  The command is intended for the contract/golden
fixture proof phase of OPS-15.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sqlite3
import sys
from contextlib import closing
from pathlib import Path
from typing import Any, Iterable


CONTRACT_VERSION = "harness-local-authority-adapter-v1"
SOURCE_SCHEMA = 12
TARGET_SCHEMA = 14
UID_PREFIX = "ops15.local"

SOURCE_TABLES = (
    "schema_version",
    "intake",
    "story",
    "decision",
    "backlog",
    "trace",
    "tool",
    "intervention",
    "changeset_applied",
    "story_dependency",
    "story_hierarchy",
)

TARGET_TABLES = (
    "schema_version",
    "intake",
    "story",
    "decision",
    "backlog",
    "trace",
    "tool",
    "intervention",
    "changeset_applied",
    "story_dependency",
    "story_hierarchy",
)

UPSTREAM_ONLY_TABLES = (
    "proposal_evidence_link",
    "audit_evidence_episode",
    "backlog_outcome_observation",
    "story_backlog_link",
    "legacy_evidence_snapshot",
)

LOCAL_ONLY_COLUMNS = {
    "intake": (
        "checkpoint_branch",
        "checkpoint_head",
        "checkpoint_dirty_paths",
        "checkpoint_worktree_state",
    ),
    "story": (
        "path_contracts",
        "affected_verify_command",
        "last_affected_verified_at",
        "last_affected_result",
        "last_affected_fingerprint",
    ),
    "backlog": ("kind",),
}

COMMON_COLUMNS = {
    "intake": (
        "id",
        "created_at",
        "input_type",
        "summary",
        "risk_lane",
        "risk_flags",
        "affected_docs",
        "story_id",
        "notes",
    ),
    "story": (
        "id",
        "title",
        "created_at",
        "risk_lane",
        "contract_doc",
        "status",
        "unit_proof",
        "integration_proof",
        "e2e_proof",
        "platform_proof",
        "evidence",
        "notes",
        "verify_command",
        "last_verified_at",
        "last_verified_result",
    ),
    "decision": (
        "id",
        "title",
        "created_at",
        "status",
        "doc_path",
        "verify_command",
        "last_verified_at",
        "last_verified_result",
        "predicted_impact",
        "actual_outcome",
        "notes",
    ),
    "backlog": (
        "id",
        "created_at",
        "title",
        "discovered_while",
        "current_pain",
        "suggested_improvement",
        "risk",
        "status",
        "predicted_impact",
        "actual_outcome",
        "implemented_at",
        "notes",
    ),
    "trace": (
        "id",
        "created_at",
        "task_summary",
        "intake_id",
        "story_id",
        "agent",
        "actions_taken",
        "files_read",
        "files_changed",
        "decisions_made",
        "errors",
        "outcome",
        "duration_seconds",
        "token_estimate",
        "harness_friction",
        "notes",
    ),
    "tool": (
        "name",
        "created_at",
        "provider",
        "command",
        "description",
        "args",
        "responsibility",
        "since",
        "kind",
        "capability",
        "scan_target",
        "status",
        "checked_at",
    ),
    "intervention": (
        "id",
        "created_at",
        "trace_id",
        "story_id",
        "type",
        "description",
        "source",
        "impact",
    ),
    "changeset_applied": ("id", "path", "applied_at"),
    "story_dependency": ("story_id", "blocks_story_id", "created_at"),
    "story_hierarchy": ("parent_story_id", "child_story_id", "created_at"),
}


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def connect(path: Path, read_only: bool) -> sqlite3.Connection:
    if read_only:
        uri = f"file:{path.as_posix()}?mode=ro"
        connection = sqlite3.connect(uri, uri=True)
    else:
        connection = sqlite3.connect(path)
        connection.execute("PRAGMA foreign_keys = ON")
    connection.row_factory = sqlite3.Row
    return connection


def table_columns(connection: sqlite3.Connection, table: str) -> list[str]:
    return [row[1] for row in connection.execute(f'PRAGMA table_info("{table}")')]


def primary_key_columns(connection: sqlite3.Connection, table: str) -> list[str]:
    rows = list(connection.execute(f'PRAGMA table_info("{table}")'))
    return [row[1] for row in sorted(rows, key=lambda row: row[5]) if row[5]]


def fetch_rows(connection: sqlite3.Connection, table: str) -> list[dict[str, Any]]:
    columns = table_columns(connection, table)
    order_columns = primary_key_columns(connection, table)
    if order_columns:
        order = ", ".join(f'"{column}"' for column in order_columns)
    else:
        order = "rowid"
    rows = connection.execute(f'SELECT * FROM "{table}" ORDER BY {order}').fetchall()
    return [{column: row[column] for column in columns} for row in rows]


def row_digest(rows: Iterable[dict[str, Any]]) -> str:
    payload = "\n".join(canonical_json(row) for row in rows).encode("utf-8")
    return sha256_bytes(payload)


def table_manifest(connection: sqlite3.Connection) -> dict[str, Any]:
    manifest: dict[str, Any] = {}
    for table in SOURCE_TABLES:
        rows = fetch_rows(connection, table)
        manifest[table] = {
            "columns": table_columns(connection, table),
            "count": len(rows),
            "sha256": row_digest(rows),
        }
    return manifest


def source_metadata(source: Path) -> dict[str, Any]:
    with closing(connect(source, read_only=True)) as connection:
        versions = [row[0] for row in connection.execute("SELECT version FROM schema_version ORDER BY version")]
        if not versions or versions[-1] != SOURCE_SCHEMA:
            raise ValueError(f"SOURCE_SCHEMA_MISMATCH:{versions[-1] if versions else 'missing'}")
        integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
        if integrity != "ok":
            raise ValueError(f"SOURCE_INTEGRITY_FAILED:{integrity}")
        foreign = list(connection.execute("PRAGMA foreign_key_check"))
        if foreign:
            raise ValueError(f"SOURCE_FOREIGN_KEY_FAILED:{len(foreign)}")
        return {
            "schema_version": versions[-1],
            "file_sha256": file_sha256(source),
            "tables": table_manifest(connection),
        }


def uid(kind: str, local_id: Any) -> str:
    return f"{UID_PREFIX}.{kind}.{local_id}"


def sidecar_payload(source: Path, metadata: dict[str, Any]) -> dict[str, Any]:
    fields: dict[str, Any] = {}
    with closing(connect(source, read_only=True)) as connection:
        for table, columns in LOCAL_ONLY_COLUMNS.items():
            rows = fetch_rows(connection, table)
            projection = [
                {"key": row.get("id"), **{column: row.get(column) for column in columns}}
                for row in rows
            ]
            fields[table] = {
                "columns": list(columns),
                "count": len(projection),
                "sha256": row_digest(projection),
            }
        bug_fix_rows = [
            {"id": row["id"], "input_type": row["input_type"]}
            for row in fetch_rows(connection, "intake")
            if row["input_type"] == "bug_fix"
        ]
        fields["intake.input_type.bug_fix"] = {
            "count": len(bug_fix_rows),
            "sha256": row_digest(bug_fix_rows),
            "projection": "change_request",
        }
    return {
        "contract": CONTRACT_VERSION,
        "source_schema_version": SOURCE_SCHEMA,
        "source_snapshot_sha256": metadata["file_sha256"],
        "local_only_fields": fields,
    }


def target_metadata(target: Path) -> dict[str, Any]:
    with closing(connect(target, read_only=True)) as connection:
        versions = [row[0] for row in connection.execute("SELECT version FROM schema_version ORDER BY version")]
        if not versions or versions[-1] != TARGET_SCHEMA:
            raise ValueError(f"TARGET_SCHEMA_MISMATCH:{versions[-1] if versions else 'missing'}")
        missing = [
            table
            for table in (*TARGET_TABLES, *UPSTREAM_ONLY_TABLES)
            if not table_columns(connection, table)
        ]
        if missing:
            raise ValueError(f"TARGET_TABLES_MISSING:{','.join(missing)}")
        integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
        if integrity != "ok":
            raise ValueError(f"TARGET_INTEGRITY_FAILED:{integrity}")
        foreign = list(connection.execute("PRAGMA foreign_key_check"))
        if foreign:
            raise ValueError(f"TARGET_FOREIGN_KEY_FAILED:{len(foreign)}")
        return {"schema_version": versions[-1]}


def assert_target_empty(connection: sqlite3.Connection) -> None:
    for table in (*TARGET_TABLES, *UPSTREAM_ONLY_TABLES):
        if table == "schema_version":
            continue
        count = connection.execute(f'SELECT COUNT(*) FROM "{table}"').fetchone()[0]
        if count:
            raise ValueError(f"TARGET_NOT_EMPTY:{table}:{count}")


def append_target_extension_failures(
    table: str,
    target_row: dict[str, Any],
    source_row: dict[str, Any],
    index: int,
    failures: list[str],
) -> None:
    expected: dict[str, Any] = {}
    if table == "intake":
        expected = {"uid": uid("intake", source_row["id"])}
    elif table in ("story", "decision", "tool"):
        expected = {"revision": 0}
    elif table == "backlog":
        expected = {
            "uid": uid("backlog", source_row["id"]),
            "proposal_key": None,
            "predecessor_uid": None,
            "occurrence_kind": None,
            "accepted_at": None,
            "closed_at": None,
            "resolution_evidence": None,
            "outcome_schedule_kind": None,
            "outcome_due_at": None,
            "outcome_after_traces": None,
            "outcome_baseline_trace_count": None,
            "rejection_reason": None,
            "revision": 0,
        }
    elif table == "trace":
        expected = {
            "uid": uid("trace", source_row["id"]),
            "intake_uid": uid("intake", source_row["intake_id"])
            if source_row["intake_id"] is not None
            else None,
            "recorded_at_unix_ns": None,
        }
    elif table == "intervention":
        expected = {"uid": uid("intervention", source_row["id"])}
    elif table == "changeset_applied":
        expected = {"content_sha256": None}
    for column, value in expected.items():
        if target_row.get(column) != value:
            failures.append(f"TARGET_EXTENSION_MISMATCH:{table}:{index}:{column}")


def insert_rows(source: Path, target: Path, sidecar_path: Path, metadata: dict[str, Any]) -> None:
    sidecar = sidecar_payload(source, metadata)
    with closing(connect(source, read_only=True)) as source_connection, closing(
        connect(target, read_only=False)
    ) as target_connection:
        target_metadata(target)
        assert_target_empty(target_connection)
        source_rows = {table: fetch_rows(source_connection, table) for table in SOURCE_TABLES}
        target_connection.execute("BEGIN IMMEDIATE")
        try:
            for row in source_rows["intake"]:
                values = [
                    row[column] if row["input_type"] != "bug_fix" or column != "input_type" else "change_request"
                    for column in COMMON_COLUMNS["intake"]
                ]
                columns = ", ".join((*COMMON_COLUMNS["intake"], "uid"))
                placeholders = ", ".join("?" for _ in range(len(values) + 1))
                target_connection.execute(
                    f'INSERT INTO intake ({columns}) VALUES ({placeholders})',
                    (*values, uid("intake", row["id"])),
                )
            for table in ("story", "decision"):
                columns = ", ".join((*COMMON_COLUMNS[table], "revision"))
                placeholders = ", ".join("?" for _ in range(len(COMMON_COLUMNS[table]) + 1))
                for row in source_rows[table]:
                    target_connection.execute(
                        f'INSERT INTO "{table}" ({columns}) VALUES ({placeholders})',
                        tuple(row[column] for column in COMMON_COLUMNS[table]) + (0,),
                    )
            columns = ", ".join((*COMMON_COLUMNS["backlog"], "uid", "revision"))
            placeholders = ", ".join("?" for _ in range(len(COMMON_COLUMNS["backlog"]) + 2))
            for row in source_rows["backlog"]:
                target_connection.execute(
                    f'INSERT INTO backlog ({columns}) VALUES ({placeholders})',
                    tuple(row[column] for column in COMMON_COLUMNS["backlog"])
                    + (uid("backlog", row["id"]), 0),
                )
            columns = ", ".join((*COMMON_COLUMNS["trace"], "uid", "intake_uid", "recorded_at_unix_ns"))
            placeholders = ", ".join("?" for _ in range(len(COMMON_COLUMNS["trace"]) + 3))
            for row in source_rows["trace"]:
                intake_uid = uid("intake", row["intake_id"]) if row["intake_id"] is not None else None
                target_connection.execute(
                    f'INSERT INTO trace ({columns}) VALUES ({placeholders})',
                    tuple(row[column] for column in COMMON_COLUMNS["trace"])
                    + (uid("trace", row["id"]), intake_uid, None),
                )
            columns = ", ".join((*COMMON_COLUMNS["tool"], "revision"))
            placeholders = ", ".join("?" for _ in range(len(COMMON_COLUMNS["tool"]) + 1))
            for row in source_rows["tool"]:
                target_connection.execute(
                    f'INSERT INTO tool ({columns}) VALUES ({placeholders})',
                    tuple(row[column] for column in COMMON_COLUMNS["tool"]) + (0,),
                )
            columns = ", ".join((*COMMON_COLUMNS["intervention"], "uid"))
            placeholders = ", ".join("?" for _ in range(len(COMMON_COLUMNS["intervention"]) + 1))
            for row in source_rows["intervention"]:
                target_connection.execute(
                    f'INSERT INTO intervention ({columns}) VALUES ({placeholders})',
                    tuple(row[column] for column in COMMON_COLUMNS["intervention"])
                    + (uid("intervention", row["id"]),),
                )
            for table in ("changeset_applied", "story_dependency", "story_hierarchy"):
                columns = ", ".join(COMMON_COLUMNS[table])
                placeholders = ", ".join("?" for _ in COMMON_COLUMNS[table])
                for row in source_rows[table]:
                    target_connection.execute(
                        f'INSERT INTO "{table}" ({columns}) VALUES ({placeholders})',
                        tuple(row[column] for column in COMMON_COLUMNS[table]),
                    )
            target_connection.commit()
        except Exception:
            target_connection.rollback()
            raise
    sidecar_path.parent.mkdir(parents=True, exist_ok=True)
    sidecar_path.write_text(canonical_json(sidecar) + "\n", encoding="utf-8", newline="\n")


def parity(source: Path, target: Path, fixture_path: Path, sidecar_path: Path) -> dict[str, Any]:
    fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
    metadata = source_metadata(source)
    failures: list[str] = []
    expected = fixture["source"]
    if metadata["schema_version"] != expected["schema_version"]:
        failures.append("SOURCE_SCHEMA_MISMATCH")
    if metadata["file_sha256"] != expected["snapshot_file_sha256"]:
        failures.append("SOURCE_SNAPSHOT_SHA_MISMATCH")
    for table, expected_table in expected["tables"].items():
        actual_table = metadata["tables"].get(table)
        if actual_table != expected_table:
            failures.append(f"SOURCE_TABLE_MISMATCH:{table}")
    try:
        target_metadata(target)
    except ValueError as error:
        failures.append(str(error))
    expected_sidecar = fixture["sidecar"]
    actual_sidecar = sidecar_payload(source, metadata)
    if actual_sidecar != expected_sidecar:
        failures.append("SIDECAR_PROJECTION_MISMATCH")
    if not sidecar_path.exists() or json.loads(sidecar_path.read_text(encoding="utf-8")) != expected_sidecar:
        failures.append("SIDECAR_ARTIFACT_MISMATCH")
    mapped_counts: dict[str, int] = {}
    with closing(connect(source, read_only=True)) as source_connection, closing(
        connect(target, read_only=True)
    ) as target_connection:
        for table in SOURCE_TABLES:
            source_rows = fetch_rows(source_connection, table)
            mapped_counts[table] = len(source_rows)
            if table == "schema_version":
                continue
            target_rows = fetch_rows(target_connection, table)
            if len(source_rows) != len(target_rows):
                failures.append(f"TARGET_COUNT_MISMATCH:{table}")
                continue
            if table in COMMON_COLUMNS:
                for index, source_row in enumerate(source_rows):
                    target_row = target_rows[index]
                    for column in COMMON_COLUMNS[table]:
                        source_value = source_row[column]
                        if table == "intake" and column == "input_type" and source_value == "bug_fix":
                            source_value = "change_request"
                        if target_row[column] != source_value:
                            failures.append(f"TARGET_VALUE_MISMATCH:{table}:{index}:{column}")
                            break
                    append_target_extension_failures(
                        table,
                        target_row,
                        source_row,
                        index,
                        failures,
                    )
        for table in UPSTREAM_ONLY_TABLES:
            count = target_connection.execute(f'SELECT COUNT(*) FROM "{table}"').fetchone()[0]
            if count:
                failures.append(f"TARGET_SYNTHETIC_ROWS:{table}:{count}")
        if failures:
            result = "FAIL"
        else:
            result = "PASS"
    return {
        "contract": CONTRACT_VERSION,
        "result": result,
        "failures": failures,
        "source_snapshot_sha256": metadata["file_sha256"],
        "source_schema_version": metadata["schema_version"],
        "target_schema_version": TARGET_SCHEMA,
        "mapped_counts": mapped_counts,
        "changeset_created": False,
    }


def build_manifest(source: Path, output: Path, source_root_sha256: str | None) -> None:
    metadata = source_metadata(source)
    sidecar = sidecar_payload(source, metadata)
    payload = {
        "fixture": CONTRACT_VERSION,
        "purpose": "redacted golden digest derived from a WAL-safe copy of local harness.db",
        "source": {
            "schema_version": metadata["schema_version"],
            "snapshot_file_sha256": metadata["file_sha256"],
            "root_file_sha256": source_root_sha256,
            "tables": metadata["tables"],
        },
        "sidecar": sidecar,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(canonical_json(payload) + "\n", encoding="utf-8", newline="\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    manifest_parser = subparsers.add_parser("manifest")
    manifest_parser.add_argument("--source", type=Path, required=True)
    manifest_parser.add_argument("--output", type=Path, required=True)
    manifest_parser.add_argument("--source-root-sha256")
    project_parser = subparsers.add_parser("project")
    project_parser.add_argument("--source", type=Path, required=True)
    project_parser.add_argument("--target", type=Path, required=True)
    project_parser.add_argument("--sidecar", type=Path, required=True)
    parity_parser = subparsers.add_parser("parity")
    parity_parser.add_argument("--source", type=Path, required=True)
    parity_parser.add_argument("--target", type=Path, required=True)
    parity_parser.add_argument("--fixture", type=Path, required=True)
    parity_parser.add_argument("--sidecar", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == "manifest":
            build_manifest(args.source, args.output, args.source_root_sha256)
            return 0
        if args.command == "project":
            metadata = source_metadata(args.source)
            insert_rows(args.source, args.target, args.sidecar, metadata)
            return 0
        result = parity(args.source, args.target, args.fixture, args.sidecar)
        print(json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
        return 0 if result["result"] == "PASS" else 1
    except (OSError, sqlite3.Error, ValueError, json.JSONDecodeError) as error:
        print(json.dumps({"contract": CONTRACT_VERSION, "result": "FAIL", "error": str(error)}, ensure_ascii=False, sort_keys=True), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
