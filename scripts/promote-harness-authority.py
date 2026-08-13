#!/usr/bin/env python3
"""Validate and record Phase 3B Harness authority promotion.

This command consumes only the sanitized Phase 3A ledger and tracked target
manifest. It never opens the legacy database, writes a database, or copies a
legacy row into a Markdown document. The output is a payload-free manifest of
current Git destinations and deduplicated Linear follow-ups.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
from collections import Counter
from pathlib import Path
from typing import Any


EXPECTED_COUNTS = {
    "intake": 92,
    "story": 37,
    "decision": 7,
    "backlog": 27,
    "trace": 36,
}
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
REASON = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*\Z")


def canonical(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_object(path: Path) -> dict[str, Any]:
    document = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(document, dict):
        raise ValueError(f"JSON_DOCUMENT_MUST_BE_OBJECT:{path}")
    return document


def safe_path(root: Path, value: str) -> str:
    if not value or any(ord(char) < 32 for char in value):
        raise ValueError("TARGET_PATH_INVALID")
    candidate = Path(value.replace("\\", "/"))
    if candidate.is_absolute() or ".." in candidate.parts or ":" in value:
        raise ValueError(f"TARGET_PATH_INVALID:{value}")
    resolved_root = root.resolve()
    resolved = (resolved_root / candidate).resolve()
    if resolved_root not in resolved.parents or not resolved.is_file():
        raise ValueError(f"TARGET_PATH_NOT_FOUND:{value}")
    return candidate.as_posix()


def validate_target_manifest(document: dict[str, Any]) -> dict[str, dict[str, Any]]:
    if document.get("formatVersion") != 1 or not isinstance(document.get("targets"), list):
        raise ValueError("LINEAR_TARGETS_DOCUMENT_INVALID")
    targets: dict[str, dict[str, Any]] = {}
    for item in document["targets"]:
        if not isinstance(item, dict):
            raise ValueError("LINEAR_TARGET_INVALID")
        target_id = str(item.get("id", ""))
        if not LINEAR_ID.fullmatch(target_id) or target_id in targets:
            raise ValueError(f"LINEAR_TARGET_ID_INVALID:{target_id}")
        if item.get("kind") != "child-issue" or not isinstance(item.get("scope"), str):
            raise ValueError(f"LINEAR_TARGET_METADATA_INVALID:{target_id}")
        source_ids = item.get("sourceBacklogIds")
        if not isinstance(source_ids, list) or any(
            not isinstance(source_id, int) or source_id < 1 for source_id in source_ids
        ):
            raise ValueError(f"LINEAR_TARGET_SOURCE_IDS_INVALID:{target_id}")
        if len(source_ids) != len(set(source_ids)):
            raise ValueError(f"LINEAR_TARGET_SOURCE_IDS_DUPLICATE:{target_id}")
        targets[target_id] = item
    flattened = [source_id for item in targets.values() for source_id in item["sourceBacklogIds"]]
    if sorted(flattened) != list(range(1, EXPECTED_COUNTS["backlog"] + 1)):
        raise ValueError("LINEAR_TARGET_BACKLOG_COVERAGE_INVALID")
    return targets


def validate_ledger(
    ledger: dict[str, Any],
    root: Path,
    target_manifest: dict[str, dict[str, Any]],
    archive_manifest: dict[str, Any],
) -> tuple[list[dict[str, Any]], dict[str, dict[str, Any]]]:
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
    if set(ledger) != expected_keys or ledger.get("formatVersion") != 1:
        raise ValueError("DISPOSITION_DOCUMENT_INVALID")
    if not GIT_SHA.fullmatch(str(ledger.get("sourceRevision", ""))):
        raise ValueError("DISPOSITION_SOURCE_REVISION_INVALID")
    if ledger.get("sourceSchemaVersion") != 12:
        raise ValueError("DISPOSITION_SOURCE_SCHEMA_INVALID")
    for key in ("sourceDatabaseSha256", "sourceLogicalStateSha256"):
        if not HASH.fullmatch(str(ledger.get(key, ""))):
            raise ValueError(f"DISPOSITION_{key.upper()}_INVALID")
    records = ledger.get("records")
    if not isinstance(records, list) or ledger.get("recordCount") != len(records):
        raise ValueError("DISPOSITION_RECORD_COUNT_INVALID")
    if len(records) != sum(EXPECTED_COUNTS.values()):
        raise ValueError("DISPOSITION_RECORD_COUNT_INVALID")

    seen: set[tuple[str, str]] = set()
    entity_counts = Counter()
    target_records: list[dict[str, Any]] = []
    for record in records:
        if not isinstance(record, dict):
            raise ValueError("DISPOSITION_RECORD_INVALID")
        expected_record_keys = {
            "entity",
            "sourceId",
            "sourceStatus",
            "payloadSha256",
            "disposition",
            "targetRef",
            "reasonCode",
        }
        if set(record) != expected_record_keys:
            raise ValueError("DISPOSITION_RECORD_KEYS_INVALID")
        entity = record["entity"]
        source_id = record["sourceId"]
        if entity not in EXPECTED_COUNTS or not isinstance(source_id, str) or not SOURCE_ID.fullmatch(source_id):
            raise ValueError("DISPOSITION_RECORD_ID_INVALID")
        key = (entity, source_id)
        if key in seen:
            raise ValueError(f"DISPOSITION_DUPLICATE:{entity}:{source_id}")
        seen.add(key)
        entity_counts[entity] += 1
        if not isinstance(record["sourceStatus"], str) or not record["sourceStatus"]:
            raise ValueError("DISPOSITION_SOURCE_STATUS_INVALID")
        if not HASH.fullmatch(str(record["payloadSha256"])):
            raise ValueError("DISPOSITION_PAYLOAD_HASH_INVALID")
        disposition = record["disposition"]
        if disposition not in DISPOSITIONS:
            raise ValueError("DISPOSITION_VALUE_INVALID")
        if not isinstance(record["reasonCode"], str) or not REASON.fullmatch(record["reasonCode"]):
            raise ValueError("DISPOSITION_REASON_INVALID")
        target = record["targetRef"]
        if target is not None and not isinstance(target, str):
            raise ValueError("DISPOSITION_TARGET_INVALID")
        if disposition in REQUIRED_TARGET and not target:
            raise ValueError(f"DISPOSITION_TARGET_REQUIRED:{entity}:{source_id}")
        if target:
            if LINEAR_ID.fullmatch(target):
                if target not in target_manifest:
                    raise ValueError(f"LINEAR_TARGET_NOT_FOUND:{target}")
            else:
                safe_path(root, target)
            target_records.append(record)

    if dict(entity_counts) != EXPECTED_COUNTS:
        raise ValueError(f"DISPOSITION_ENTITY_COUNTS_INVALID:{dict(entity_counts)}")

    # Every backlog record is represented exactly once by its declared child.
    backlog_records = {
        int(record["sourceId"]): record
        for record in records
        if record["entity"] == "backlog"
    }
    if sorted(backlog_records) != list(range(1, EXPECTED_COUNTS["backlog"] + 1)):
        raise ValueError("BACKLOG_SOURCE_ID_COVERAGE_INVALID")
    for target_id, target in target_manifest.items():
        for source_id in target["sourceBacklogIds"]:
            record = backlog_records[source_id]
            if record["disposition"] != "linear-follow-up" or record["targetRef"] != target_id:
                raise ValueError(f"BACKLOG_TARGET_MISMATCH:{source_id}:{target_id}")

    by_target: dict[str, dict[str, Any]] = {}
    for record in target_records:
        target = str(record["targetRef"])
        item = by_target.setdefault(
            target,
            {"targetRef": target, "recordCount": 0, "sourceRecords": [], "dispositions": set(), "reasonCodes": set()},
        )
        item["recordCount"] += 1
        item["sourceRecords"].append({"entity": record["entity"], "sourceId": record["sourceId"]})
        item["dispositions"].add(record["disposition"])
        item["reasonCodes"].add(record["reasonCode"])
    return target_records, by_target


def normalize_destinations(destinations: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    normalized = []
    for target, item in sorted(destinations.items()):
        normalized.append(
            {
                "targetRef": target,
                "targetKind": "linear-issue" if LINEAR_ID.fullmatch(target) else "git-path",
                "recordCount": item["recordCount"],
                "sourceRecords": sorted(item["sourceRecords"], key=lambda value: (value["entity"], value["sourceId"])),
                "dispositions": sorted(item["dispositions"]),
                "reasonCodes": sorted(item["reasonCodes"]),
            }
        )
    return normalized


def build_report(
    ledger: dict[str, Any],
    ledger_path: Path,
    archive_manifest: dict[str, Any],
    target_document: dict[str, Any],
    target_manifest: dict[str, dict[str, Any]],
    repository_revision: str,
    destinations: dict[str, dict[str, Any]],
    target_path: Path,
) -> dict[str, Any]:
    records = ledger["records"]
    dispositions = Counter(record["disposition"] for record in records)
    entities = Counter(record["entity"] for record in records)
    linear_destinations = [item for item in destinations.values() if LINEAR_ID.fullmatch(item["targetRef"])]
    git_destinations = [item for item in destinations.values() if not LINEAR_ID.fullmatch(item["targetRef"])]
    return {
        "formatVersion": 1,
        "initiative": "OPS-64",
        "phase": "3B",
        "repositoryRevision": repository_revision,
        "source": {
            "dispositionSha256": sha256(ledger_path),
            "manifestDispositionSha256": archive_manifest["dispositionSha256"],
            "databaseSha256": ledger["sourceDatabaseSha256"],
            "logicalStateSha256": ledger["sourceLogicalStateSha256"],
            "schemaVersion": ledger["sourceSchemaVersion"],
        },
        "summary": {
            "recordCount": len(records),
            "entityCounts": dict(sorted(entities.items())),
            "dispositionCounts": dict(sorted(dispositions.items())),
            "targetBearingRecordCount": sum(item["recordCount"] for item in destinations.values()),
            "uniqueDestinationCount": len(destinations),
            "gitDestinationCount": len(git_destinations),
            "linearFollowUpCount": len(linear_destinations),
            "historicalOnlyCount": dispositions["historical-only"],
        },
        "gitDestinations": normalize_destinations({item["targetRef"]: item for item in git_destinations}),
        "linearFollowUps": [
            {
                **item,
                "scope": target_manifest[item["targetRef"]]["scope"],
                "sourceBacklogIds": target_manifest[item["targetRef"]]["sourceBacklogIds"],
            }
            for item in normalize_destinations({item["targetRef"]: item for item in linear_destinations})
        ],
        "policy": {
            "rawPayloadCommitted": False,
            "rowForRowMarkdownMigration": False,
            "databaseWritten": False,
            "archiveReadOnly": True,
        },
        "targetManifest": {
            "sha256": sha256(target_path),
            "targetIds": sorted(target_document["targets"], key=lambda item: item["id"]),
        },
    }


def validate_target_manifest_ids(document: dict[str, Any], target_manifest: dict[str, dict[str, Any]]) -> None:
    """Ensure the report carries the complete, deterministic target ledger."""
    reported = document.get("targetManifest", {}).get("targetIds")
    expected = sorted(target_manifest.values(), key=lambda item: item["id"])
    if reported != expected:
        raise ValueError("PROMOTION_REPORT_TARGET_IDS_INVALID")


def validate_source_parity(
    ledger: dict[str, Any], archive_manifest: dict[str, Any], report_source: dict[str, Any]
) -> None:
    """Keep the promotion proof tied to the same immutable Phase 3A source."""
    manifest_source = archive_manifest.get("source")
    if not isinstance(manifest_source, dict):
        raise ValueError("PROMOTION_REPORT_ARCHIVE_SOURCE_INVALID")
    expected = {
        "databaseSha256": ledger.get("sourceDatabaseSha256"),
        "logicalStateSha256": ledger.get("sourceLogicalStateSha256"),
        "schemaVersion": ledger.get("sourceSchemaVersion"),
    }
    for key, value in expected.items():
        if report_source.get(key) != value:
            raise ValueError(f"PROMOTION_REPORT_SOURCE_{key.upper()}_MISMATCH")
        if manifest_source.get(key) != value:
            raise ValueError(f"PROMOTION_REPORT_MANIFEST_SOURCE_{key.upper()}_MISMATCH")


def validate_report_semantics(
    document: dict[str, Any],
    ledger: dict[str, Any],
    ledger_path: Path,
    archive_manifest: dict[str, Any],
    target_document: dict[str, Any],
    target_manifest: dict[str, dict[str, Any]],
    root: Path,
    target_path: Path,
) -> None:
    """Reject payloads that are shaped correctly but no longer deterministic."""
    _, destinations = validate_ledger(ledger, root, target_manifest, archive_manifest)
    expected = build_report(
        ledger,
        ledger_path,
        archive_manifest,
        target_document,
        target_manifest,
        document["repositoryRevision"],
        destinations,
        target_path,
    )
    if canonical(document) != canonical(expected):
        raise ValueError("PROMOTION_REPORT_SEMANTIC_MISMATCH")


def write_json(document: dict[str, Any], path: Path) -> str:
    if path.exists() or path.is_symlink():
        raise ValueError(f"OUTPUT_ALREADY_EXISTS:{path.resolve()}")
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    try:
        with temporary.open("x", encoding="utf-8", newline="\n") as stream:
            stream.write(canonical(document) + "\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()
    return sha256(path)


def validate_report(
    document: dict[str, Any],
    root: Path,
    ledger_path: Path,
    archive_manifest_path: Path,
    target_path: Path,
) -> None:
    if document.get("formatVersion") != 1 or document.get("phase") != "3B":
        raise ValueError("PROMOTION_REPORT_HEADER_INVALID")
    if not GIT_SHA.fullmatch(str(document.get("repositoryRevision", ""))):
        raise ValueError("PROMOTION_REPORT_REVISION_INVALID")
    source = document.get("source")
    if not isinstance(source, dict) or source.get("dispositionSha256") != sha256(ledger_path):
        raise ValueError("PROMOTION_REPORT_LEDGER_HASH_INVALID")
    ledger = read_object(ledger_path)
    archive_manifest = read_object(archive_manifest_path)
    if archive_manifest.get("dispositionSha256") != sha256(ledger_path):
        raise ValueError("PROMOTION_REPORT_MANIFEST_LEDGER_HASH_INVALID")
    if source.get("manifestDispositionSha256") != archive_manifest.get("dispositionSha256"):
        raise ValueError("PROMOTION_REPORT_MANIFEST_HASH_INVALID")
    target_document = read_object(target_path)
    target_manifest = validate_target_manifest(target_document)
    if document.get("targetManifest", {}).get("sha256") != sha256(target_path):
        raise ValueError("PROMOTION_REPORT_TARGET_HASH_INVALID")
    validate_target_manifest_ids(document, target_manifest)
    validate_source_parity(ledger, archive_manifest, source)
    for item in document.get("gitDestinations", []):
        safe_path(root, item["targetRef"])
    for item in document.get("linearFollowUps", []):
        if not LINEAR_ID.fullmatch(item["targetRef"]):
            raise ValueError("PROMOTION_REPORT_LINEAR_TARGET_INVALID")
    if document.get("policy") != {
        "archiveReadOnly": True,
        "databaseWritten": False,
        "rawPayloadCommitted": False,
        "rowForRowMarkdownMigration": False,
    }:
        raise ValueError("PROMOTION_REPORT_POLICY_INVALID")
    validate_report_semantics(
        document,
        ledger,
        ledger_path,
        archive_manifest,
        target_document,
        target_manifest,
        root,
        target_path,
    )


def git_revision(root: Path) -> str:
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=root, check=True, capture_output=True, text=True
    )
    value = result.stdout.strip().lower()
    if not GIT_SHA.fullmatch(value):
        raise ValueError("GIT_HEAD_INVALID")
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository-root", type=Path, required=True)
    parser.add_argument("--disposition", type=Path, required=True)
    parser.add_argument("--archive-manifest", type=Path, required=True)
    parser.add_argument("--linear-targets", type=Path, required=True)
    parser.add_argument("--repository-revision")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--input", type=Path)
    args = parser.parse_args()
    if bool(args.output) == bool(args.input):
        raise ValueError("EXACTLY_ONE_OF_OUTPUT_OR_INPUT_REQUIRED")
    root = args.repository_root.resolve()
    ledger_path = args.disposition.resolve()
    manifest_path = args.archive_manifest.resolve()
    target_path = args.linear_targets.resolve()
    ledger = read_object(ledger_path)
    archive_manifest = read_object(manifest_path)
    target_document = read_object(target_path)
    target_manifest = validate_target_manifest(target_document)
    if archive_manifest.get("dispositionSha256") != sha256(ledger_path):
        raise ValueError("ARCHIVE_MANIFEST_DISPOSITION_HASH_MISMATCH")
    _, destinations = validate_ledger(ledger, root, target_manifest, archive_manifest)
    if args.input:
        report = read_object(args.input.resolve())
        validate_report(report, root, ledger_path, manifest_path, target_path)
        print(json.dumps({"result": "PASS", "sha256": sha256(args.input.resolve())}, sort_keys=True))
        return 0
    revision = args.repository_revision or git_revision(root)
    if not GIT_SHA.fullmatch(revision):
        raise ValueError("PROMOTION_REPORT_REVISION_INVALID")
    report = build_report(
        ledger,
        ledger_path,
        archive_manifest,
        target_document,
        target_manifest,
        revision,
        destinations,
        target_path,
    )
    report["targetManifest"]["sha256"] = sha256(target_path)
    report["source"]["manifestDispositionSha256"] = archive_manifest["dispositionSha256"]
    validate_report(report, root, ledger_path, manifest_path, target_path)
    output_sha = write_json(report, args.output.resolve())
    print(json.dumps({"result": "PASS", "recordCount": report["summary"]["recordCount"], "sha256": output_sha}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
