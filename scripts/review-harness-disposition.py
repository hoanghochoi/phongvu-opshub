#!/usr/bin/env python3
"""Review the sanitized legacy Harness archive without mutating any database.

The Phase 3 review is deliberately separate from the archive exporter.  It
reads a WAL-safe archive copy, maps only current Git authority or an existing
Linear follow-up, and writes a payload-free ledger.  The source database is
opened immutable/read-only and is never refreshed, migrated, or written.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sqlite3
from pathlib import Path
from typing import Any


EXPECTED_COUNTS = {"intake": 92, "story": 37, "decision": 7, "backlog": 27, "trace": 36}
EXPECTED_SCHEMA_VERSIONS = list(range(1, 13))
DISPOSITIONS = {
    "already-authoritative",
    "historical-only",
    "linear-follow-up",
    "promoted",
    "rejected-with-reason",
    "superseded",
}
REQUIRED_TARGET = {"already-authoritative", "linear-follow-up", "promoted"}
SOURCE_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}\Z")
HASH = re.compile(r"[0-9a-f]{64}\Z")
GIT_SHA = re.compile(r"[0-9a-f]{40}\Z")
LINEAR_ID = re.compile(r"OPS-[0-9]+\Z")
REASON_CODE = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*\Z")


def canonical(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def digest_json(value: Any) -> str:
    return hashlib.sha256(canonical(value).encode("utf-8")).hexdigest()


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


def table_digest(connection: sqlite3.Connection, table: str) -> tuple[int, str]:
    columns = [
        str(row[1])
        for row in connection.execute(f"PRAGMA table_info({quote_identifier(table)})")
    ]
    if not columns:
        raise ValueError(f"ARCHIVE_TABLE_HAS_NO_COLUMNS:{table}")
    column_sql = ",".join(quote_identifier(column) for column in columns)
    rows: list[str] = []
    for row in connection.execute(
        f"SELECT {column_sql} FROM {quote_identifier(table)}"
    ):
        rows.append(
            canonical([normalized_sqlite_value(row[column]) for column in columns])
        )
    rows.sort()
    digest = hashlib.sha256()
    for row in rows:
        digest.update(row.encode("utf-8"))
        digest.update(b"\n")
    return len(rows), digest.hexdigest()


def logical_state(connection: sqlite3.Connection) -> dict[str, Any]:
    integrity = [str(row[0]) for row in connection.execute("PRAGMA integrity_check")]
    if integrity != ["ok"]:
        raise ValueError(f"ARCHIVE_INTEGRITY_FAILED:{integrity}")
    foreign = list(connection.execute("PRAGMA foreign_key_check"))
    if foreign:
        raise ValueError(f"ARCHIVE_FOREIGN_KEY_FAILED:{len(foreign)}")
    versions = [
        int(row[0])
        for row in connection.execute(
            "SELECT version FROM schema_version ORDER BY version"
        )
    ]
    if versions != EXPECTED_SCHEMA_VERSIONS:
        raise ValueError(f"ARCHIVE_SCHEMA_VERSIONS_INVALID:{versions}")
    tables = [
        str(row[0])
        for row in connection.execute(
            "SELECT name FROM sqlite_schema WHERE type='table' "
            "AND name NOT LIKE 'sqlite_%' ORDER BY name"
        )
    ]
    table_counts: dict[str, int] = {}
    table_digests: dict[str, str] = {}
    for table in tables:
        count, digest = table_digest(connection, table)
        table_counts[table] = count
        table_digests[table] = digest
    logical_counts = {entity: table_counts.get(entity) for entity in EXPECTED_COUNTS}
    if logical_counts != EXPECTED_COUNTS:
        raise ValueError(f"ARCHIVE_COUNTS_INVALID:{logical_counts}")
    state = {
        "schemaSha256": schema_digest(connection),
        "schemaVersions": versions,
        "tableCounts": table_counts,
        "tableDigests": table_digests,
    }
    return {
        **state,
        "logicalCounts": logical_counts,
        "logicalStateSha256": digest_json(state),
    }


def validate_manifest_source(manifest: dict[str, Any], archive: Path) -> dict[str, Any]:
    if manifest.get("formatVersion") != 1:
        raise ValueError("ARCHIVE_MANIFEST_VERSION_INVALID")
    source = manifest.get("source")
    if not isinstance(source, dict):
        raise ValueError("ARCHIVE_MANIFEST_SOURCE_INVALID")
    if not GIT_SHA.fullmatch(str(source.get("repositoryRevision", ""))):
        raise ValueError("ARCHIVE_MANIFEST_REVISION_INVALID")
    if source.get("schemaVersion") != 12 or source.get("schemaVersions") != EXPECTED_SCHEMA_VERSIONS:
        raise ValueError("ARCHIVE_MANIFEST_SCHEMA_INVALID")
    if source.get("logicalCounts") != EXPECTED_COUNTS:
        raise ValueError("ARCHIVE_MANIFEST_COUNTS_INVALID")
    for key in ("databaseSha256", "sourceStateSha256", "logicalStateSha256", "schemaSha256"):
        if not HASH.fullmatch(str(source.get(key, ""))):
            raise ValueError(f"ARCHIVE_MANIFEST_{key.upper()}_INVALID")
    expected_source_state = digest_json(
        {
            "databaseSha256": source["databaseSha256"],
            "walSha256": source.get("walSha256"),
        }
    )
    if source["sourceStateSha256"] != expected_source_state:
        raise ValueError("ARCHIVE_MANIFEST_SOURCE_STATE_INVALID")
    copies = manifest.get("copies")
    if not isinstance(copies, list) or len(copies) != 2:
        raise ValueError("ARCHIVE_MANIFEST_COPIES_INVALID")
    archive_hash = file_sha256(archive)
    matching_copy = False
    labels: set[str] = set()
    for copy in copies:
        if not isinstance(copy, dict):
            raise ValueError("ARCHIVE_MANIFEST_COPY_INVALID")
        label = copy.get("label")
        if label not in {"primary-local", "secondary-local"} or label in labels:
            raise ValueError("ARCHIVE_MANIFEST_COPY_LABEL_INVALID")
        labels.add(label)
        if copy.get("fileName") != "harness.db" or copy.get("integrityResult") != "PASS":
            raise ValueError("ARCHIVE_MANIFEST_COPY_RESULT_INVALID")
        if not HASH.fullmatch(str(copy.get("sha256", ""))):
            raise ValueError("ARCHIVE_MANIFEST_COPY_HASH_INVALID")
        if copy.get("logicalStateSha256") != source["logicalStateSha256"]:
            raise ValueError("ARCHIVE_MANIFEST_COPY_LOGICAL_STATE_INVALID")
        matching_copy = matching_copy or copy["sha256"] == archive_hash
    if not matching_copy:
        raise ValueError("ARCHIVE_MANIFEST_ARCHIVE_HASH_MISMATCH")
    return source


def payload_sha256(row: sqlite3.Row) -> str:
    payload = {key: normalized_sqlite_value(row[key]) for key in sorted(row.keys())}
    return hashlib.sha256(canonical(payload).encode("utf-8")).hexdigest()


def safe_target(root: Path, value: str | None) -> str | None:
    if not value or any(ord(char) < 32 for char in value):
        return None
    candidate = Path(value.replace("\\", "/"))
    if candidate.is_absolute() or ".." in candidate.parts:
        return None
    resolved_root = root.resolve()
    resolved = (resolved_root / candidate).resolve()
    if resolved == resolved_root or resolved_root not in resolved.parents:
        return None
    if not resolved.is_file():
        return None
    return candidate.as_posix()


def connect_archive(path: Path) -> sqlite3.Connection:
    if not path.is_file():
        raise ValueError(f"ARCHIVE_NOT_FOUND:{path}")
    if path.is_symlink():
        raise ValueError(f"ARCHIVE_IS_SYMLINK:{path.resolve()}")
    wal_path = Path(f"{path}-wal")
    if wal_path.is_file() and wal_path.stat().st_size:
        raise ValueError(f"ARCHIVE_WAL_PRESENT:{wal_path}")
    # SQLite may leave an orphaned SHM sidecar after the online backup.  It is
    # not a write-ahead log and immutable mode ignores it; a non-empty WAL is
    # the fail-closed signal that the archive is not a stable snapshot.
    uri = f"file:{path.resolve().as_posix()}?mode=ro&immutable=1"
    connection = sqlite3.connect(uri, uri=True)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA query_only=ON")
    logical_state(connection)
    return connection


STORY_TARGETS = {
    "AUTH-001": "docs/product/auth.md",
    "AUTH-002": "docs/stories/AUTH-002-password-reset/overview.md",
    "AUTH-003": "docs/stories/AUTH-003-single-platform-session/overview.md",
    "AUTH-004": "docs/stories/AUTH-004-user-aware-rate-limits/overview.md",
    "AUTH-CONTEXT-001": "docs/stories/AUTH-CONTEXT-001-auth-context-performance.md",
    "CLIENT-LOGS-001": "docs/stories/CLIENT-LOGS-001-daily-activity-log.md",
    "FEEDBACK-001": "docs/product/feedback.md",
    "FIFO-001": "docs/product/fifo.md",
    "FIFO-002": "docs/stories/FIFO-002-copy-serial-location.md",
    "HARNESS-WORKFLOW-001": "docs/WORKFLOW.md",
    "HELP-001": "docs/product/help.md",
    "HOME-DASHBOARD-002": "docs/product/sales-report.md",
    "HOME-DASHBOARD-003": "docs/product/backend-platform.md",
    "OPS-10": "docs/stories/OPS-10-sales-report-design-guard/overview.md",
    "OPS-12": "docs/stories/PAYMENT-STATEMENT-001-bank-statement/overview.md",
    "OPS-8": "docs/stories/OPS-8-flutter-web-break-iterator/overview.md",
    "PAYMENT-MONITOR-001": "docs/stories/PAYMENT-MONITOR-002-realtime-refresh.md",
    "PAYMENT-STATEMENT-001": "docs/stories/PAYMENT-STATEMENT-001-bank-statement/overview.md",
    "PAYMENT-STATEMENT-KEYBOARD-001": "docs/stories/PAYMENT-STATEMENT-KEYBOARD-001/overview.md",
    "PERSONNEL-001": "docs/stories/PERSONNEL-001-role-department-foundation.md",
    "PLATFORM-001": "docs/product/backend-platform.md",
    "PROFILE-ADMIN-001": "docs/stories/PROFILE-ADMIN-001-profile-branch-admin.md",
    "QUICK-ACTIONS-001": "docs/stories/QUICK-ACTIONS-001-quick-actions-v1.md",
    "SALES-REPORT-001": "docs/stories/SALES-REPORT-001-sales-report.md",
    "SALES-REPORT-002": "docs/stories/SALES-REPORT-002-not-purchased-customer-follow-up.md",
    "SETTINGS-001": "docs/product/overview.md",
    "UI-KEYBOARD-001": "docs/stories/UI-KEYBOARD-001/overview.md",
    "UI-PASTE-001": "docs/stories/UI-PASTE-001/overview.md",
    "UI-UX-001": "docs/product/ui-ux.md",
    "UI-UX-002": "docs/stories/UI-UX-002-navigation-groups-top-right-toast.md",
    "UPDATE-001": "docs/stories/UPDATE-002-download-landing.md",
    "UPDATE-003": "docs/stories/UPDATE-003-realtime-update-prompt.md",
    "VIETQR-001": "docs/stories/VIETQR-001-create-transfer-qr.md",
    "WARRANTY-001": "docs/product/warranty.md",
    "WINDOWS-DIST-001": "docs/stories/WINDOWS-DIST-001-windows-distribution-trust.md",
    "WINDOWS-INSTALL-001": "docs/product/windows-distribution.md",
}

DECISION_TARGETS = {
    "0001-adopt-opshub-harness": "docs/decisions/0001-adopt-opshub-harness.md",
    "0002-vietqr-payment-confirmation": "docs/decisions/0002-vietqr-payment-confirmation.md",
    "0007-improvement-proposal-rules": "docs/decisions/0007-improvement-proposal-rules.md",
    "0008-finance-filter-actions": "docs/decisions/0008-finance-filter-actions.md",
    "ADR-0009": "docs/decisions/0009-home-summary-outbox-projection.md",
}

BACKLOG_TARGETS = {
    "1": ("OPS-67", "replaced-by-generic-verification-runner"),
    "2": ("OPS-72", "folded-into-validation-noise-optimization"),
}
for source_id in map(str, range(3, 11)):
    BACKLOG_TARGETS[source_id] = ("OPS-76", "grouped-product-design-follow-up")
for source_id in ("11", "12", "13"):
    BACKLOG_TARGETS[source_id] = ("OPS-77", "grouped-realtime-collaboration-follow-up")
for source_id in ("14", "17", "26"):
    BACKLOG_TARGETS[source_id] = ("OPS-78", "grouped-release-staging-follow-up")
for source_id in map(str, range(15, 26)):
    BACKLOG_TARGETS[source_id] = ("OPS-79", "grouped-verification-guardrail-follow-up")
BACKLOG_TARGETS["27"] = ("OPS-76", "grouped-product-design-follow-up")


def review_row(entity: str, row: sqlite3.Row, root: Path, linear_targets: set[str]) -> tuple[str, str | None, str]:
    source_id = str(row["id"])
    if entity in {"intake", "trace"}:
        return "historical-only", None, "operational-history-retained-in-local-archive"
    if entity == "story":
        source_contract = row["contract_doc"] if "contract_doc" in row.keys() else None
        target = safe_target(root, source_contract)
        if target:
            return "already-authoritative", target, "current-git-document-exists"
        target = safe_target(root, STORY_TARGETS.get(source_id))
        if target:
            return "already-authoritative", target, "current-git-document-exists"
        return "historical-only", None, "no-current-authority-target-confirmed"
    if entity == "decision":
        if source_id in {"0003-adopt-harness-durable-layer", "0014-local-harness-boundary-and-windows-entrypoint"}:
            adr = safe_target(root, "docs/decisions/0029-adopt-upstream-repository-protocol-and-retire-protocol-v1.md")
            if adr:
                return "superseded", adr, "superseded-by-adr-0029"
        source_doc = row["doc_path"] if "doc_path" in row.keys() else None
        target = safe_target(root, source_doc)
        if target:
            return "already-authoritative", target, "current-git-document-exists"
        target = safe_target(root, DECISION_TARGETS.get(source_id))
        if target:
            return "already-authoritative", target, "current-git-document-exists"
        return "historical-only", None, "no-current-authority-target-confirmed"
    target_issue, reason = BACKLOG_TARGETS.get(source_id, (None, "no-current-authority-target-confirmed"))
    if target_issue and target_issue in linear_targets:
        return "linear-follow-up", target_issue, reason
    return "historical-only", None, "linear-follow-up-target-not-confirmed"


def validate(document: dict[str, Any], root: Path, linear_targets: set[str]) -> None:
    if (
        document.get("formatVersion") != 1
        or document.get("sourceSchemaVersion") != 12
        or document.get("allowedDispositions") != sorted(DISPOSITIONS)
    ):
        raise ValueError("DISPOSITION_HEADER_INVALID")
    if not GIT_SHA.fullmatch(document.get("sourceRevision", "")):
        raise ValueError("DISPOSITION_SOURCE_REVISION_INVALID")
    records = document.get("records")
    if not isinstance(records, list):
        raise ValueError("DISPOSITION_RECORDS_INVALID")
    if document.get("recordCount") != len(records):
        raise ValueError("DISPOSITION_RECORD_COUNT_INVALID")
    seen: set[tuple[str, str]] = set()
    counts = {entity: 0 for entity in EXPECTED_COUNTS}
    for record in records:
        if not isinstance(record, dict):
            raise ValueError("DISPOSITION_RECORD_INVALID")
        expected = {"entity", "sourceId", "sourceStatus", "payloadSha256", "disposition", "targetRef", "reasonCode"}
        if set(record) != expected:
            raise ValueError("DISPOSITION_RECORD_KEYS_INVALID")
        entity, source_id = record.get("entity"), record.get("sourceId")
        if entity not in EXPECTED_COUNTS or not isinstance(source_id, str) or not SOURCE_ID.fullmatch(source_id):
            raise ValueError("DISPOSITION_ID_INVALID")
        key = (entity, source_id)
        if key in seen:
            raise ValueError(f"DISPOSITION_DUPLICATE:{key}")
        seen.add(key)
        counts[entity] += 1
        if (
            not isinstance(record["sourceStatus"], str)
            or not record["sourceStatus"]
            or any(ord(char) < 32 for char in record["sourceStatus"])
        ):
            raise ValueError("DISPOSITION_SOURCE_STATUS_INVALID")
        if not HASH.fullmatch(record["payloadSha256"]):
            raise ValueError("DISPOSITION_PAYLOAD_HASH_INVALID")
        if record["disposition"] not in DISPOSITIONS:
            raise ValueError("DISPOSITION_VALUE_INVALID")
        target = record["targetRef"]
        if target is not None and not isinstance(target, str):
            raise ValueError("DISPOSITION_TARGET_INVALID")
        if record["disposition"] in REQUIRED_TARGET and not target:
            raise ValueError("DISPOSITION_TARGET_REQUIRED")
        if target and not (
            safe_target(root, target) == target
            or (LINEAR_ID.fullmatch(target) and target in linear_targets)
        ):
            raise ValueError(f"DISPOSITION_TARGET_INVALID:{entity}:{source_id}:{target}")
        if not isinstance(record["reasonCode"], str) or not REASON_CODE.fullmatch(record["reasonCode"]):
            raise ValueError("DISPOSITION_REASON_INVALID")
    if counts != EXPECTED_COUNTS:
        raise ValueError(f"DISPOSITION_ENTITY_COUNTS_INVALID:{counts}")


def write_output(document: dict[str, Any], output: Path) -> str:
    if output.exists() or output.is_symlink():
        raise ValueError(f"OUTPUT_ALREADY_EXISTS:{output.resolve()}")
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(f".{output.name}.{os.getpid()}.tmp")
    try:
        with temporary.open("x", encoding="utf-8", newline="\n") as stream:
            stream.write(
                f"{json.dumps(document, ensure_ascii=False, sort_keys=True, separators=(',', ':'))}\n"
            )
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, output)
    finally:
        if temporary.exists():
            temporary.unlink()
    return file_sha256(output)


def validate_ledger_against_archive(
    document: dict[str, Any],
    ledger_path: Path,
    connection: sqlite3.Connection,
    source: dict[str, Any],
    root: Path,
    linear_targets: set[str],
    manifest: dict[str, Any],
) -> None:
    validate(document, root, linear_targets)
    if manifest.get("dispositionSha256") != file_sha256(ledger_path):
        raise ValueError("ARCHIVE_MANIFEST_DISPOSITION_HASH_MISMATCH")
    if document.get("sourceRevision") != source["repositoryRevision"]:
        raise ValueError("DISPOSITION_SOURCE_REVISION_MISMATCH")
    if document.get("sourceDatabaseSha256") != source["databaseSha256"]:
        raise ValueError("DISPOSITION_SOURCE_DATABASE_MISMATCH")
    if document.get("sourceLogicalStateSha256") != source["logicalStateSha256"]:
        raise ValueError("DISPOSITION_SOURCE_LOGICAL_STATE_MISMATCH")
    actual = {
        (entity, str(row["id"])): row
        for entity in EXPECTED_COUNTS
        for row in connection.execute(f"SELECT * FROM {quote_identifier(entity)}")
    }
    records = {
        (str(record["entity"]), str(record["sourceId"])): record
        for record in document["records"]
    }
    if set(records) != set(actual):
        missing = sorted(set(actual) - set(records))
        extra = sorted(set(records) - set(actual))
        raise ValueError(f"DISPOSITION_SOURCE_ID_SET_MISMATCH:missing={missing}:extra={extra}")
    for key, row in actual.items():
        record = records[key]
        expected_status = str(row["status"]) if "status" in row.keys() else "recorded"
        if record["sourceStatus"] != expected_status:
            raise ValueError(f"DISPOSITION_SOURCE_STATUS_MISMATCH:{key}")
        if record["payloadSha256"] != payload_sha256(row):
            raise ValueError(f"DISPOSITION_SOURCE_PAYLOAD_MISMATCH:{key}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--repository-root", type=Path, required=True)
    parser.add_argument("--source-manifest", type=Path, required=True)
    parser.add_argument("--linear-targets", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--input", type=Path)
    args = parser.parse_args()
    if bool(args.output) == bool(args.input):
        raise ValueError("EXACTLY_ONE_OF_INPUT_OR_OUTPUT_REQUIRED")
    root = args.repository_root.resolve()
    manifest = json.loads(args.source_manifest.read_text(encoding="utf-8"))
    source = validate_manifest_source(manifest, args.archive.resolve())
    target_doc = json.loads(args.linear_targets.read_text(encoding="utf-8"))
    if target_doc.get("formatVersion") != 1 or not isinstance(target_doc.get("targets"), list):
        raise ValueError("LINEAR_TARGETS_DOCUMENT_INVALID")
    linear_targets: set[str] = set()
    for item in target_doc["targets"]:
        if not isinstance(item, dict) or not LINEAR_ID.fullmatch(str(item.get("id", ""))):
            raise ValueError("LINEAR_TARGET_ID_INVALID")
        if item["id"] in linear_targets:
            raise ValueError(f"LINEAR_TARGET_DUPLICATE:{item['id']}")
        linear_targets.add(item["id"])
    connection = connect_archive(args.archive.resolve())
    try:
        state = logical_state(connection)
        expected_state = {
            "schemaSha256": source["schemaSha256"],
            "schemaVersions": source["schemaVersions"],
            "tableCounts": source["tableCounts"],
            "tableDigests": source["tableDigests"],
        }
        actual_state = {
            "schemaSha256": state["schemaSha256"],
            "schemaVersions": state["schemaVersions"],
            "tableCounts": state["tableCounts"],
            "tableDigests": state["tableDigests"],
        }
        if actual_state != expected_state:
            raise ValueError("ARCHIVE_MANIFEST_TABLE_PARITY_MISMATCH")
        if state["logicalStateSha256"] != source["logicalStateSha256"]:
            raise ValueError("ARCHIVE_MANIFEST_LOGICAL_STATE_MISMATCH")
        if state["schemaSha256"] != source["schemaSha256"]:
            raise ValueError("ARCHIVE_MANIFEST_SCHEMA_DIGEST_MISMATCH")
        if args.input:
            ledger_path = args.input.resolve()
            if not ledger_path.is_file() or ledger_path.is_symlink():
                raise ValueError(f"LEDGER_NOT_FOUND:{ledger_path}")
            document = json.loads(ledger_path.read_text(encoding="utf-8"))
            validate_ledger_against_archive(
                document,
                ledger_path,
                connection,
                source,
                root,
                linear_targets,
                manifest,
            )
            print(json.dumps({"recordCount": document["recordCount"], "result": "PASS", "sha256": file_sha256(ledger_path)}, sort_keys=True))
            return 0
        records: list[dict[str, Any]] = []
        for entity in EXPECTED_COUNTS:
            for row in connection.execute(f"SELECT * FROM {entity}"):
                disposition, target, reason = review_row(entity, row, root, linear_targets)
                records.append({
                    "entity": entity,
                    "sourceId": str(row["id"]),
                    "sourceStatus": str(row["status"]) if "status" in row.keys() else "recorded",
                    "payloadSha256": payload_sha256(row),
                    "disposition": disposition,
                    "targetRef": target,
                    "reasonCode": reason,
                })
    finally:
        connection.close()
    records.sort(key=lambda item: (item["entity"], item["sourceId"]))
    document = {
        "formatVersion": 1,
        "sourceRevision": source["repositoryRevision"],
        "sourceSchemaVersion": source["schemaVersion"],
        "sourceDatabaseSha256": source["databaseSha256"],
        "sourceLogicalStateSha256": source["logicalStateSha256"],
        "recordCount": len(records),
        "allowedDispositions": sorted(DISPOSITIONS),
        "records": records,
    }
    validate(document, root, linear_targets)
    output_sha = write_output(document, args.output)
    print(json.dumps({"recordCount": len(records), "sha256": output_sha, "linearTargets": sorted(linear_targets)}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
