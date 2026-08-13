#!/usr/bin/env python3
"""Export and verify a read-only, WAL-safe archive of the legacy Harness DB.

This migration helper never writes the source database or imports it into the
upstream Harness. Raw databases and the exported ledger remain local-only.
Only the sanitized manifest is suitable for repository evidence.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sqlite3
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


EXPECTED_COUNTS = {
    "intake": 92,
    "story": 37,
    "decision": 7,
    "backlog": 27,
    "trace": 36,
}
EXPECTED_SCHEMA_VERSIONS = list(range(1, 13))
DISPOSITIONS = {
    "promoted",
    "already-authoritative",
    "linear-follow-up",
    "superseded",
    "historical-only",
    "rejected-with-reason",
}
TARGET_REQUIRED_DISPOSITIONS = {
    "promoted",
    "already-authoritative",
    "linear-follow-up",
}
LEGACY_TOOL_TAG = "harness-cli-v0.1.22"
HEX_64 = re.compile(r"[0-9a-f]{64}\Z")
GIT_REVISION = re.compile(r"[0-9a-f]{40}\Z")
REASON_CODE = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*\Z")
SOURCE_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}\Z")
ALLOWED_RESIDUAL_RISKS = {
    "same-physical-disk-not-off-host",
    "physical-disk-separation-unverified",
    "separate-physical-disks-local-only-not-off-host",
}


def canonical(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def digest_json(value: Any) -> str:
    return hashlib.sha256(canonical(value).encode("utf-8")).hexdigest()


def schema_digest(connection: sqlite3.Connection) -> str:
    schema = [
        {
            "type": str(row[0]),
            "name": str(row[1]),
            "tableName": str(row[2]),
            "sql": str(row[3]) if row[3] is not None else None,
        }
        for row in connection.execute(
            "SELECT type,name,tbl_name,sql FROM sqlite_schema "
            "WHERE name NOT LIKE 'sqlite_%' ORDER BY type,name,tbl_name"
        )
    ]
    return digest_json(schema)


def normalized_sqlite_value(value: Any) -> dict[str, Any]:
    if value is None:
        return {"type": "null", "value": None}
    if isinstance(value, bytes):
        return {"type": "blob", "value": value.hex()}
    if isinstance(value, int):
        return {"type": "integer", "value": str(value)}
    if isinstance(value, float):
        return {"type": "real", "value": value.hex()}
    return {"type": "text", "value": str(value)}


def quote_identifier(value: str) -> str:
    return '"' + value.replace('"', '""') + '"'


def connect_readonly(path: Path) -> sqlite3.Connection:
    # SQLite may create a shared-memory sidecar for a WAL database even when
    # the connection is query-only. An immutable URI avoids that side effect
    # when no non-empty WAL is present; a live WAL still requires ordinary
    # read-only mode so the online-backup proof can observe it safely.
    wal_path = Path(f"{path}-wal")
    query = "mode=ro"
    if not wal_path.is_file() or wal_path.stat().st_size == 0:
        query += "&immutable=1"
    uri = f"file:{path.resolve().as_posix()}?{query}"
    connection = sqlite3.connect(uri, uri=True)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA query_only=ON")
    return connection


def source_file_hashes(path: Path) -> dict[str, str | None]:
    wal = Path(f"{path}-wal")
    return {
        "databaseSha256": sha256(path),
        "walSha256": sha256(wal) if wal.is_file() else None,
    }


def table_digest(connection: sqlite3.Connection, table: str) -> tuple[int, str]:
    columns = [
        str(row[1])
        for row in connection.execute(f"PRAGMA table_info({quote_identifier(table)})")
    ]
    if not columns:
        raise ValueError(f"TABLE_HAS_NO_COLUMNS:{table}")
    rows: list[str] = []
    column_sql = ",".join(quote_identifier(column) for column in columns)
    for row in connection.execute(
        f"SELECT {column_sql} FROM {quote_identifier(table)}"
    ):
        rows.append(
            canonical(
                [normalized_sqlite_value(row[column]) for column in columns]
            )
        )
    rows.sort()
    digest = hashlib.sha256()
    for row in rows:
        digest.update(row.encode("utf-8"))
        digest.update(b"\n")
    return len(rows), digest.hexdigest()


def inspect_connection(
    connection: sqlite3.Connection, path: Path
) -> dict[str, Any]:
    integrity_rows = [str(row[0]) for row in connection.execute("PRAGMA integrity_check")]
    if integrity_rows != ["ok"]:
        raise ValueError(f"SOURCE_INTEGRITY_FAILED:{'|'.join(integrity_rows)}")
    foreign = list(connection.execute("PRAGMA foreign_key_check"))
    if foreign:
        raise ValueError(f"SOURCE_FOREIGN_KEY_FAILED:{len(foreign)}")
    versions = [
        int(row[0])
        for row in connection.execute(
            "SELECT version FROM schema_version ORDER BY version"
        )
    ]
    if versions != EXPECTED_SCHEMA_VERSIONS:
        raise ValueError(f"SCHEMA_VERSIONS_MISMATCH:{versions}")
    tables = [
        str(row[0])
        for row in connection.execute(
            "SELECT name FROM sqlite_schema "
            "WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
        )
    ]
    missing = sorted(set(EXPECTED_COUNTS) - set(tables))
    if missing:
        raise ValueError(f"EXPECTED_TABLES_MISSING:{','.join(missing)}")
    table_counts: dict[str, int] = {}
    table_digests: dict[str, str] = {}
    for table in tables:
        count, digest = table_digest(connection, table)
        table_counts[table] = count
        table_digests[table] = digest
    logical_counts = {table: table_counts[table] for table in EXPECTED_COUNTS}
    if logical_counts != EXPECTED_COUNTS:
        raise ValueError(f"ROW_COUNTS_MISMATCH:{logical_counts}")
    file_hashes = source_file_hashes(path)
    logical_state = {
        "schemaSha256": schema_digest(connection),
        "schemaVersions": versions,
        "tableCounts": table_counts,
        "tableDigests": table_digests,
    }
    return {
        **file_hashes,
        "sourceStateSha256": digest_json(file_hashes),
        "logicalStateSha256": digest_json(logical_state),
        "schemaSha256": logical_state["schemaSha256"],
        "schemaVersion": versions[-1],
        "schemaVersions": versions,
        "logicalCounts": logical_counts,
        "tableCounts": table_counts,
        "tableDigests": table_digests,
        "integrityCheck": "ok",
        "foreignKeyCheck": "ok",
    }


def source_metadata(path: Path) -> dict[str, Any]:
    connection = connect_readonly(path)
    try:
        connection.execute("BEGIN")
        try:
            return inspect_connection(connection, path)
        finally:
            connection.rollback()
    finally:
        connection.close()


def ensure_new_directory(path: Path, source: Path) -> None:
    resolved = path.resolve()
    source_resolved = source.resolve()
    if resolved == source_resolved or resolved in source_resolved.parents:
        raise ValueError(f"ARCHIVE_PATH_CONTAINS_SOURCE:{resolved}")
    if path.is_symlink():
        raise ValueError(f"ARCHIVE_TARGET_IS_SYMLINK:{resolved}")
    if path.exists():
        if not path.is_dir() or any(path.iterdir()):
            raise ValueError(f"ARCHIVE_TARGET_NOT_EMPTY:{resolved}")
    else:
        path.mkdir(parents=True)


def harden_archive_acl(path: Path) -> None:
    """Restrict a Windows archive directory to the current user.

    The archive is intentionally local-only. On Windows, remove inherited ACLs
    from the newly-created leaf directory and grant the invoking identity full
    control. Other platforms leave ACL policy to the host and are reported by
    the manifest as local-only evidence.
    """
    if os.name != "nt":
        return
    username = os.environ.get("USERNAME")
    domain = os.environ.get("USERDOMAIN")
    if not username:
        raise ValueError("ARCHIVE_ACL_CURRENT_USER_UNKNOWN")
    identity = f"{domain}\\{username}" if domain else username
    command = [
        "icacls",
        str(path),
        "/inheritance:r",
        "/grant:r",
        f"{identity}:(OI)(CI)(F)",
    ]
    try:
        result = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except OSError as error:
        raise ValueError(f"ARCHIVE_ACL_COMMAND_FAILED:{error}") from error
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip().replace("\n", " ")
        raise ValueError(f"ARCHIVE_ACL_FAILED:{detail[:240]}")


def ensure_disjoint_directories(first: Path, second: Path) -> None:
    first_resolved = first.resolve()
    second_resolved = second.resolve()
    if (
        first_resolved == second_resolved
        or first_resolved in second_resolved.parents
        or second_resolved in first_resolved.parents
    ):
        raise ValueError("ARCHIVE_COPIES_MUST_BE_DISJOINT")


def ensure_output_does_not_replace_source(output: Path, source: Path) -> None:
    protected = {
        source.resolve(),
        Path(f"{source}-wal").resolve(),
        Path(f"{source}-shm").resolve(),
    }
    if output.resolve() in protected:
        raise ValueError("OUTPUT_MUST_NOT_REPLACE_SOURCE")
    if output.is_symlink():
        raise ValueError(f"OUTPUT_IS_SYMLINK:{output.resolve()}")


def write_json(path: Path, value: Any) -> None:
    if path.exists() or path.is_symlink():
        raise ValueError(f"OUTPUT_ALREADY_EXISTS:{path.resolve()}")
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    try:
        with temporary.open("x", encoding="utf-8", newline="\n") as stream:
            stream.write(canonical(value))
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def backup_connection(source: sqlite3.Connection, target: Path) -> None:
    if target.exists():
        raise ValueError(f"ARCHIVE_DATABASE_ALREADY_EXISTS:{target.resolve()}")
    target_connection = sqlite3.connect(target)
    try:
        source.backup(target_connection)
        target_connection.commit()
    finally:
        target_connection.close()


def parity_fields(metadata: dict[str, Any]) -> dict[str, Any]:
    return {
        "schemaSha256": metadata["schemaSha256"],
        "schemaVersions": metadata["schemaVersions"],
        "logicalCounts": metadata["logicalCounts"],
        "tableCounts": metadata["tableCounts"],
        "tableDigests": metadata["tableDigests"],
        "logicalStateSha256": metadata["logicalStateSha256"],
    }


def verify_copy(path: Path, expected: dict[str, Any]) -> dict[str, Any]:
    actual = source_metadata(path)
    if parity_fields(actual) != parity_fields(expected):
        raise ValueError(f"ARCHIVE_LOGICAL_PARITY_MISMATCH:{path.resolve()}")
    return actual


def require_hash(value: Any, label: str) -> str:
    if not isinstance(value, str) or not HEX_64.fullmatch(value):
        raise ValueError(f"{label}_INVALID")
    return value


def safe_repository_target(value: Any, repository_root: Path) -> str | None:
    if value is None or value == "":
        return None
    if not isinstance(value, str) or any(ord(character) < 32 for character in value):
        return None
    candidate = Path(value.replace("\\", "/"))
    if candidate.is_absolute() or ".." in candidate.parts:
        return None
    resolved_root = repository_root.resolve()
    resolved_candidate = (resolved_root / candidate).resolve()
    if resolved_candidate == resolved_root or resolved_root not in resolved_candidate.parents:
        return None
    if not resolved_candidate.is_file():
        return None
    return candidate.as_posix()


def safe_payload_digest(row: sqlite3.Row) -> str:
    payload = {
        key: normalized_sqlite_value(row[key])
        for key in sorted(row.keys())
    }
    return digest_json(payload)


def disposition_for_row(
    entity: str, row: sqlite3.Row, repository_root: Path
) -> tuple[str, str | None, str]:
    if entity in {"intake", "trace"}:
        return "historical-only", None, "operational-history-retained-in-local-archive"
    candidate = row["contract_doc"] if entity == "story" else row["doc_path"] if entity == "decision" else None
    target = safe_repository_target(candidate, repository_root)
    if target:
        return "already-authoritative", target, "current-git-document-exists"
    if entity == "decision" and row["status"] == "superseded":
        return "superseded", None, "legacy-decision-is-marked-superseded"
    return "historical-only", None, "requires-phase-3-authority-review"


def read_json_object(path: Path) -> dict[str, Any]:
    document = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(document, dict):
        raise ValueError("JSON_DOCUMENT_MUST_BE_OBJECT")
    return document


def validate_disposition_document(document: dict[str, Any]) -> None:
    expected_keys = {
        "formatVersion",
        "sourceRevision",
        "sourceSchemaVersion",
        "sourceDatabaseSha256",
        "sourceLogicalStateSha256",
        "recordCount",
        "allowedDispositions",
        "records",
    }
    if set(document) != expected_keys or document.get("formatVersion") != 1:
        raise ValueError("DISPOSITION_DOCUMENT_INVALID")
    if not GIT_REVISION.fullmatch(str(document.get("sourceRevision", ""))):
        raise ValueError("DISPOSITION_SOURCE_REVISION_INVALID")
    require_hash(document.get("sourceDatabaseSha256"), "SOURCE_DATABASE_SHA256")
    require_hash(document.get("sourceLogicalStateSha256"), "SOURCE_LOGICAL_STATE_SHA256")
    if document.get("sourceSchemaVersion") != EXPECTED_SCHEMA_VERSIONS[-1]:
        raise ValueError("DISPOSITION_SCHEMA_VERSION_INVALID")
    if document.get("allowedDispositions") != sorted(DISPOSITIONS):
        raise ValueError("DISPOSITION_ALLOWLIST_INVALID")
    records = document.get("records")
    if not isinstance(records, list) or document.get("recordCount") != len(records):
        raise ValueError("DISPOSITION_RECORD_COUNT_INVALID")
    expected_record_keys = {
        "entity",
        "sourceId",
        "sourceStatus",
        "payloadSha256",
        "disposition",
        "targetRef",
        "reasonCode",
    }
    seen: set[tuple[str, str]] = set()
    entity_counts = {entity: 0 for entity in EXPECTED_COUNTS}
    previous_key: tuple[str, str] | None = None
    for record in records:
        if not isinstance(record, dict) or set(record) != expected_record_keys:
            raise ValueError("DISPOSITION_RECORD_KEYS_INVALID")
        entity = record.get("entity")
        source_id = record.get("sourceId")
        if entity not in EXPECTED_COUNTS:
            raise ValueError(f"DISPOSITION_ENTITY_INVALID:{entity}")
        if not isinstance(source_id, str) or not SOURCE_ID.fullmatch(source_id):
            raise ValueError("DISPOSITION_SOURCE_ID_INVALID")
        key = (entity, source_id)
        if key in seen:
            raise ValueError(f"DISPOSITION_DUPLICATE:{key}")
        if previous_key is not None and key < previous_key:
            raise ValueError("DISPOSITION_ORDER_INVALID")
        seen.add(key)
        previous_key = key
        entity_counts[entity] += 1
        status = record.get("sourceStatus")
        if not isinstance(status, str) or not status or any(ord(character) < 32 for character in status):
            raise ValueError("DISPOSITION_SOURCE_STATUS_INVALID")
        require_hash(record.get("payloadSha256"), "DISPOSITION_PAYLOAD_SHA256")
        disposition_value = record.get("disposition")
        if disposition_value not in DISPOSITIONS:
            raise ValueError(f"DISPOSITION_VALUE_INVALID:{disposition_value}")
        target = record.get("targetRef")
        if disposition_value in TARGET_REQUIRED_DISPOSITIONS and not target:
            raise ValueError("DISPOSITION_TARGET_REQUIRED")
        if target is not None:
            if (
                not isinstance(target, str)
                or Path(target).is_absolute()
                or ".." in Path(target).parts
                or "\\" in target
                or ":" in target
                or any(ord(character) < 32 for character in target)
            ):
                raise ValueError("DISPOSITION_TARGET_INVALID")
        reason = record.get("reasonCode")
        if not isinstance(reason, str) or not REASON_CODE.fullmatch(reason):
            raise ValueError("DISPOSITION_REASON_INVALID")
    if entity_counts != EXPECTED_COUNTS:
        raise ValueError(f"DISPOSITION_ENTITY_COUNTS_MISMATCH:{entity_counts}")


def disposition(args: argparse.Namespace) -> int:
    source = args.source.resolve()
    if not source.is_file():
        raise ValueError(f"SOURCE_NOT_FOUND:{source}")
    ensure_output_does_not_replace_source(args.output, source)
    repository_root = args.repository_root.resolve()
    if not repository_root.is_dir():
        raise ValueError(f"REPOSITORY_ROOT_NOT_FOUND:{repository_root}")
    records: list[dict[str, Any]] = []
    connection = connect_readonly(source)
    try:
        connection.execute("BEGIN")
        try:
            metadata = inspect_connection(connection, source)
            for entity in EXPECTED_COUNTS:
                rows = connection.execute(
                    f"SELECT * FROM {quote_identifier(entity)}"
                ).fetchall()
                for row in rows:
                    source_id = str(row["id"])
                    status = str(row["status"]) if "status" in row.keys() else "recorded"
                    disposition_value, target, reason = disposition_for_row(
                        entity, row, repository_root
                    )
                    records.append(
                        {
                            "entity": entity,
                            "sourceId": source_id,
                            "sourceStatus": status,
                            "payloadSha256": safe_payload_digest(row),
                            "disposition": disposition_value,
                            "targetRef": target,
                            "reasonCode": reason,
                        }
                    )
        finally:
            connection.rollback()
    finally:
        connection.close()
    after = source_metadata(source)
    if (
        metadata["sourceStateSha256"] != after["sourceStateSha256"]
        or parity_fields(metadata) != parity_fields(after)
    ):
        raise ValueError("SOURCE_CHANGED_DURING_DISPOSITION_EXPORT")
    records.sort(key=lambda item: (item["entity"], item["sourceId"]))
    result = {
        "formatVersion": 1,
        "sourceRevision": getattr(
            args, "source_revision", "0" * 40
        ),
        "sourceSchemaVersion": metadata["schemaVersion"],
        "sourceDatabaseSha256": metadata["databaseSha256"],
        "sourceLogicalStateSha256": metadata["logicalStateSha256"],
        "recordCount": len(records),
        "allowedDispositions": sorted(DISPOSITIONS),
        "records": records,
    }
    validate_disposition_document(result)
    write_json(args.output, result)
    print(json.dumps({"recordCount": len(records), "sha256": sha256(args.output)}, sort_keys=True))
    return 0


def validate_disposition(args: argparse.Namespace) -> int:
    document = read_json_object(args.input)
    validate_disposition_document(document)
    print(json.dumps({"result": "PASS", "recordCount": document["recordCount"]}, sort_keys=True))
    return 0


def validate_legacy_tool(repository_revision: str, tag: str, artifact_hash: str) -> None:
    if not GIT_REVISION.fullmatch(repository_revision):
        raise ValueError("REPOSITORY_REVISION_INVALID")
    if tag != LEGACY_TOOL_TAG:
        raise ValueError("LEGACY_TOOL_TAG_INVALID")
    require_hash(artifact_hash, "LEGACY_TOOL_SHA256")


def validate_disposition_matches_source(
    document: dict[str, Any], metadata: dict[str, Any]
) -> None:
    validate_disposition_document(document)
    if document["sourceDatabaseSha256"] != metadata["databaseSha256"]:
        raise ValueError("DISPOSITION_SOURCE_DATABASE_MISMATCH")
    if document["sourceLogicalStateSha256"] != metadata["logicalStateSha256"]:
        raise ValueError("DISPOSITION_SOURCE_LOGICAL_STATE_MISMATCH")


def validate_disposition_records_against_source(
    document: dict[str, Any], connection: sqlite3.Connection
) -> None:
    """Compare each exported identity/status/payload digest with the source."""
    actual = {
        (str(record["entity"]), str(record["sourceId"])): record
        for record in document["records"]
    }
    for entity in EXPECTED_COUNTS:
        rows = connection.execute(
            f"SELECT * FROM {quote_identifier(entity)}"
        ).fetchall()
        for row in rows:
            key = (entity, str(row["id"]))
            record = actual.get(key)
            if record is None:
                raise ValueError(f"DISPOSITION_SOURCE_RECORD_MISSING:{entity}:{row['id']}")
            expected_status = str(row["status"]) if "status" in row.keys() else "recorded"
            if record["sourceStatus"] != expected_status:
                raise ValueError(f"DISPOSITION_SOURCE_STATUS_MISMATCH:{entity}:{row['id']}")
            if record["payloadSha256"] != safe_payload_digest(row):
                raise ValueError(f"DISPOSITION_SOURCE_PAYLOAD_MISMATCH:{entity}:{row['id']}")


def validate_disposition_targets(
    document: dict[str, Any], repository_root: Path
) -> None:
    """Fail closed when a promoted target is missing or escapes the repository."""
    root = repository_root.resolve()
    if not root.is_dir():
        raise ValueError(f"REPOSITORY_ROOT_NOT_FOUND:{root}")
    for record in document["records"]:
        target = record.get("targetRef")
        if target is None:
            continue
        safe_target = safe_repository_target(target, root)
        if safe_target != target:
            raise ValueError(
                f"DISPOSITION_TARGET_NOT_FOUND:{record['entity']}:{record['sourceId']}:{target}"
            )


def archive(args: argparse.Namespace) -> int:
    source = args.source.resolve()
    if not source.is_file():
        raise ValueError(f"SOURCE_NOT_FOUND:{source}")
    validate_legacy_tool(
        args.repository_revision, args.legacy_tool_tag, args.legacy_tool_sha256
    )
    ensure_output_does_not_replace_source(args.manifest, source)
    disposition_path = args.disposition.resolve()
    ensure_output_does_not_replace_source(disposition_path, source)
    disposition_document = read_json_object(disposition_path)
    primary = args.primary.resolve()
    secondary = args.secondary.resolve()
    ensure_disjoint_directories(primary, secondary)
    ensure_new_directory(primary, source)
    ensure_new_directory(secondary, source)
    harden_archive_acl(primary)
    harden_archive_acl(secondary)
    primary_db = primary / "harness.db"
    secondary_db = secondary / "harness.db"
    if args.manifest.resolve() in {primary_db.resolve(), secondary_db.resolve()}:
        raise ValueError("MANIFEST_MUST_NOT_REPLACE_ARCHIVE_COPY")
    source_connection = connect_readonly(source)
    try:
        source_connection.execute("BEGIN")
        try:
            before = inspect_connection(source_connection, source)
            validate_disposition_matches_source(disposition_document, before)
            validate_disposition_records_against_source(
                disposition_document, source_connection
            )
            backup_connection(source_connection, primary_db)
            backup_connection(source_connection, secondary_db)
        finally:
            source_connection.rollback()
    finally:
        source_connection.close()
    primary_meta = verify_copy(primary_db, before)
    secondary_meta = verify_copy(secondary_db, before)
    after = source_metadata(source)
    if (
        before["sourceStateSha256"] != after["sourceStateSha256"]
        or parity_fields(before) != parity_fields(after)
    ):
        raise ValueError("SOURCE_CHANGED_DURING_ARCHIVE")
    manifest = {
        "formatVersion": 1,
        "source": {
            "repositoryRevision": args.repository_revision,
            "schemaVersion": before["schemaVersion"],
            "schemaVersions": before["schemaVersions"],
            "createdAtUtc": datetime.now(timezone.utc)
            .replace(microsecond=0)
            .isoformat(),
            "databaseSha256": before["databaseSha256"],
            "walSha256": before["walSha256"],
            "sourceStateSha256": before["sourceStateSha256"],
            "logicalStateSha256": before["logicalStateSha256"],
            "schemaSha256": before["schemaSha256"],
            "logicalCounts": before["logicalCounts"],
            "tableCounts": before["tableCounts"],
            "tableDigests": before["tableDigests"],
            "residualRisk": args.residual_risk,
        },
        "legacyTool": {
            "releaseTag": args.legacy_tool_tag,
            "artifactSha256": args.legacy_tool_sha256,
        },
        "copies": [
            {
                "label": "primary-local",
                "fileName": "harness.db",
                "sha256": primary_meta["databaseSha256"],
                "logicalStateSha256": primary_meta["logicalStateSha256"],
                "integrityResult": "PASS",
                "foreignKeyResult": "PASS",
            },
            {
                "label": "secondary-local",
                "fileName": "harness.db",
                "sha256": secondary_meta["databaseSha256"],
                "logicalStateSha256": secondary_meta["logicalStateSha256"],
                "integrityResult": "PASS",
                "foreignKeyResult": "PASS",
            },
        ],
        "dispositionSha256": sha256(disposition_path),
    }
    validate_manifest_document(manifest)
    write_json(args.manifest, manifest)
    print(json.dumps(manifest, ensure_ascii=True, sort_keys=True))
    return 0


def validate_manifest_document(document: dict[str, Any]) -> None:
    if set(document) != {"formatVersion", "source", "legacyTool", "copies", "dispositionSha256"}:
        raise ValueError("ARCHIVE_MANIFEST_KEYS_INVALID")
    if document.get("formatVersion") != 1:
        raise ValueError("ARCHIVE_MANIFEST_VERSION_INVALID")
    source = document.get("source")
    expected_source_keys = {
        "repositoryRevision",
        "schemaVersion",
        "schemaVersions",
        "createdAtUtc",
        "databaseSha256",
        "walSha256",
        "sourceStateSha256",
        "logicalStateSha256",
        "schemaSha256",
        "logicalCounts",
        "tableCounts",
        "tableDigests",
        "residualRisk",
    }
    if not isinstance(source, dict) or set(source) != expected_source_keys:
        raise ValueError("ARCHIVE_SOURCE_INVALID")
    if not GIT_REVISION.fullmatch(str(source.get("repositoryRevision", ""))):
        raise ValueError("ARCHIVE_REPOSITORY_REVISION_INVALID")
    if source.get("schemaVersion") != 12 or source.get("schemaVersions") != EXPECTED_SCHEMA_VERSIONS:
        raise ValueError("ARCHIVE_SCHEMA_INVALID")
    if source.get("logicalCounts") != EXPECTED_COUNTS:
        raise ValueError("ARCHIVE_COUNTS_INVALID")
    for key in (
        "databaseSha256",
        "sourceStateSha256",
        "logicalStateSha256",
        "schemaSha256",
    ):
        require_hash(source.get(key), f"ARCHIVE_{key.upper()}")
    if source.get("walSha256") is not None:
        require_hash(source.get("walSha256"), "ARCHIVE_WAL_SHA256")
    table_counts = source.get("tableCounts")
    table_digests = source.get("tableDigests")
    if (
        not isinstance(table_counts, dict)
        or not isinstance(table_digests, dict)
        or set(table_counts) != set(table_digests)
    ):
        raise ValueError("ARCHIVE_TABLE_PARITY_INVALID")
    for digest in table_digests.values():
        require_hash(digest, "ARCHIVE_TABLE_DIGEST")
    residual_risk = source.get("residualRisk")
    if residual_risk not in ALLOWED_RESIDUAL_RISKS:
        raise ValueError("ARCHIVE_RESIDUAL_RISK_INVALID")
    legacy_tool = document.get("legacyTool")
    if not isinstance(legacy_tool, dict) or set(legacy_tool) != {"releaseTag", "artifactSha256"}:
        raise ValueError("ARCHIVE_LEGACY_TOOL_INVALID")
    validate_legacy_tool(
        str(source["repositoryRevision"]),
        legacy_tool.get("releaseTag"),
        legacy_tool.get("artifactSha256"),
    )
    copies = document.get("copies")
    if not isinstance(copies, list) or [copy.get("label") for copy in copies if isinstance(copy, dict)] != ["primary-local", "secondary-local"]:
        raise ValueError("ARCHIVE_COPIES_INVALID")
    copy_keys = {
        "label",
        "fileName",
        "sha256",
        "logicalStateSha256",
        "integrityResult",
        "foreignKeyResult",
    }
    for copy in copies:
        if not isinstance(copy, dict) or set(copy) != copy_keys:
            raise ValueError("ARCHIVE_COPY_KEYS_INVALID")
        if copy["fileName"] != "harness.db" or copy["integrityResult"] != "PASS" or copy["foreignKeyResult"] != "PASS":
            raise ValueError("ARCHIVE_COPY_RESULT_INVALID")
        require_hash(copy["sha256"], "ARCHIVE_COPY_SHA256")
        require_hash(copy["logicalStateSha256"], "ARCHIVE_COPY_LOGICAL_SHA256")
        if copy["logicalStateSha256"] != source["logicalStateSha256"]:
            raise ValueError("ARCHIVE_COPY_LOGICAL_STATE_MISMATCH")
    require_hash(document.get("dispositionSha256"), "ARCHIVE_DISPOSITION_SHA256")


def validate_archive(args: argparse.Namespace) -> int:
    manifest = read_json_object(args.manifest)
    validate_manifest_document(manifest)
    disposition_document = read_json_object(args.disposition)
    validate_disposition_document(disposition_document)
    repository_root = getattr(args, "repository_root", None)
    if repository_root is not None:
        validate_disposition_targets(disposition_document, repository_root)
    if sha256(args.disposition) != manifest["dispositionSha256"]:
        raise ValueError("ARCHIVE_DISPOSITION_HASH_MISMATCH")
    if disposition_document["sourceDatabaseSha256"] != manifest["source"]["databaseSha256"]:
        raise ValueError("ARCHIVE_DISPOSITION_SOURCE_MISMATCH")
    if disposition_document["sourceLogicalStateSha256"] != manifest["source"]["logicalStateSha256"]:
        raise ValueError("ARCHIVE_DISPOSITION_LOGICAL_STATE_MISMATCH")
    copy_paths: Iterable[Path] = (args.primary_db, args.secondary_db)
    for copy_path, copy_manifest in zip(copy_paths, manifest["copies"]):
        if not copy_path.is_file() or sha256(copy_path) != copy_manifest["sha256"]:
            raise ValueError(f"ARCHIVE_COPY_HASH_MISMATCH:{copy_manifest['label']}")
        metadata = source_metadata(copy_path)
        if metadata["logicalStateSha256"] != manifest["source"]["logicalStateSha256"]:
            raise ValueError(f"ARCHIVE_COPY_PARITY_MISMATCH:{copy_manifest['label']}")
    print(json.dumps({"result": "PASS", "copies": 2, "recordCount": disposition_document["recordCount"]}, sort_keys=True))
    return 0


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    sub = root.add_subparsers(dest="command", required=True)

    archive_parser = sub.add_parser("archive")
    archive_parser.add_argument("--source", type=Path, required=True)
    archive_parser.add_argument("--primary", type=Path, required=True)
    archive_parser.add_argument("--secondary", type=Path, required=True)
    archive_parser.add_argument("--manifest", type=Path, required=True)
    archive_parser.add_argument("--disposition", type=Path, required=True)
    archive_parser.add_argument("--repository-revision", required=True)
    archive_parser.add_argument("--legacy-tool-tag", required=True)
    archive_parser.add_argument("--legacy-tool-sha256", required=True)
    archive_parser.add_argument(
        "--residual-risk", choices=sorted(ALLOWED_RESIDUAL_RISKS), required=True
    )
    archive_parser.set_defaults(handler=archive)

    disposition_parser = sub.add_parser("disposition")
    disposition_parser.add_argument("--source", type=Path, required=True)
    disposition_parser.add_argument("--repository-root", type=Path, required=True)
    disposition_parser.add_argument("--output", type=Path, required=True)
    disposition_parser.add_argument(
        "--source-revision", default="0" * 40,
        help="40-character repository revision captured with the export",
    )
    disposition_parser.set_defaults(handler=disposition)

    validate_disposition_parser = sub.add_parser("validate-disposition")
    validate_disposition_parser.add_argument("--input", type=Path, required=True)
    validate_disposition_parser.set_defaults(handler=validate_disposition)

    validate_archive_parser = sub.add_parser("validate-archive")
    validate_archive_parser.add_argument("--manifest", type=Path, required=True)
    validate_archive_parser.add_argument("--disposition", type=Path, required=True)
    validate_archive_parser.add_argument("--primary-db", type=Path, required=True)
    validate_archive_parser.add_argument("--secondary-db", type=Path, required=True)
    validate_archive_parser.add_argument(
        "--repository-root",
        type=Path,
        help="Optional repository root used to verify every non-null targetRef",
    )
    validate_archive_parser.set_defaults(handler=validate_archive)
    return root


def main() -> int:
    try:
        args = parser().parse_args()
        return args.handler(args)
    except (OSError, sqlite3.Error, ValueError, json.JSONDecodeError) as error:
        print(json.dumps({"result": "FAIL", "error": str(error)}, sort_keys=True), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
