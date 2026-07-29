#!/usr/bin/env python3
"""Fail-closed strict Harness audit wrapper for the OpsHub consumer layer."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Callable, Sequence

from harness_local_authority_v1 import parity as adapter_parity


CONTRACT_VERSION = "opshub-harness-strict-audit-v1"
ADAPTER_CONTRACT = "harness-local-authority-adapter-v1"
SOURCE_SCHEMA_VERSION = 12
TARGET_SCHEMA_VERSION = 14
TRUSTED_SOURCE_REVISION = "c984d362223d33cf78c9b4874a28723b9a895bfe"
TRUSTED_SOURCE_SNAPSHOT_SHA256 = (
    "dd34da3afd6985e5d5c9c58eebd435863041f96ca3a3daa3eda6aff3566031be"
)
EXIT_CLEAN = 0
EXIT_AUDIT = 2
EXIT_CONFLICT = 3
EXIT_PROVENANCE = 78

TRUSTED_AUDIT_COUNTS = {
    "orphaned_stories": 4,
    "unverified_stories": 7,
    "unverified_decisions": 2,
    "stale_stories": 0,
    "open_backlog_items": 27,
    "broken_tools": 0,
    "intakes_without_traces": 70,
    "dangling_intake_links": 3,
    "entropy_score": 100,
}

TRUSTED_MAPPED_COUNTS = {
    "schema_version": 12,
    "intake": 92,
    "story": 37,
    "decision": 7,
    "backlog": 27,
    "trace": 36,
    "tool": 4,
    "intervention": 1,
    "changeset_applied": 0,
    "story_dependency": 0,
    "story_hierarchy": 0,
}


class ProvenanceArgumentParser(argparse.ArgumentParser):
    """Turn invalid command lines into the wrapper's JSON provenance result."""

    def error(self, message: str) -> None:
        raise ValueError(f"ARGUMENTS_INVALID:{message}")


def _valid_string_list(value: Any) -> bool:
    return (
        isinstance(value, list)
        and all(
            isinstance(item, str)
            and bool(item)
            and item == item.strip()
            for item in value
        )
        and len(set(value)) == len(value)
    )


def _valid_count_map(value: Any) -> bool:
    return isinstance(value, dict) and all(
        isinstance(name, str)
        and bool(name)
        and name == name.strip()
        and isinstance(count, int)
        and not isinstance(count, bool)
        and count >= 0
        for name, count in value.items()
    )


def _normalized_parity(
    value: dict[str, Any] | None,
    extra_failures: Sequence[str] = (),
) -> dict[str, Any]:
    raw = value if isinstance(value, dict) else {}
    raw_failures = raw.get("failures")
    failures = (
        [str(item) for item in raw_failures]
        if isinstance(raw_failures, list)
        else []
    )
    failures.extend(extra_failures)
    mapped_counts = raw.get("mapped_counts")
    normalized_counts = (
        dict(sorted(mapped_counts.items()))
        if _valid_count_map(mapped_counts)
        else {}
    )
    result = "PASS" if raw.get("result") == "PASS" and not failures else "FAIL"
    return {
        "contract": str(raw.get("contract", ADAPTER_CONTRACT)),
        "result": result,
        "failures": sorted(set(failures)),
        "source_snapshot_sha256": raw.get("source_snapshot_sha256"),
        "source_schema_version": raw.get("source_schema_version"),
        "target_schema_version": raw.get("target_schema_version"),
        "mapped_counts": normalized_counts,
        "changeset_created": raw.get("changeset_created"),
    }


def _result(
    *,
    schema_version: int | None,
    audit: dict[str, int],
    state_parity: dict[str, Any],
    changeset_ids: list[str],
    conflict_ids: list[str],
    exit_code: int,
) -> dict[str, Any]:
    return {
        "contract": CONTRACT_VERSION,
        "source_revision": TRUSTED_SOURCE_REVISION,
        "schema_version": schema_version,
        "audit": dict(sorted(audit.items())),
        "state_parity": state_parity,
        "changeset_ids": changeset_ids,
        "conflict_ids": conflict_ids,
        "exit_code": exit_code,
    }


def _strict_exit_code(audit: dict[str, int], conflict_ids: list[str]) -> int:
    if conflict_ids:
        return EXIT_CONFLICT
    if any(value != 0 for value in audit.values()):
        return EXIT_AUDIT
    return EXIT_CLEAN


def evaluate_strict_audit(
    audit_document: Any,
    parity_result: Any,
) -> dict[str, Any]:
    """Validate revision-pinned provenance and calculate the strict exit."""

    expected_audit = TRUSTED_AUDIT_COUNTS
    expected_mapped_counts = TRUSTED_MAPPED_COUNTS
    input_failures: list[str] = []
    document = audit_document if isinstance(audit_document, dict) else {}
    if not isinstance(audit_document, dict):
        input_failures.append("AUDIT_DOCUMENT_INVALID")

    if document.get("contract") != CONTRACT_VERSION:
        input_failures.append("AUDIT_CONTRACT_MISMATCH")

    if document.get("source_revision") != TRUSTED_SOURCE_REVISION:
        input_failures.append("SOURCE_REVISION_MISMATCH")

    schema_version = document.get("schema_version")
    if schema_version != SOURCE_SCHEMA_VERSION:
        input_failures.append("SOURCE_SCHEMA_MISMATCH")

    source_snapshot_sha256 = document.get("source_snapshot_sha256")
    if source_snapshot_sha256 != TRUSTED_SOURCE_SNAPSHOT_SHA256:
        input_failures.append("SOURCE_SNAPSHOT_SHA_MISMATCH")

    raw_audit = document.get("audit")
    audit: dict[str, int] = {}
    if not _valid_count_map(raw_audit):
        input_failures.append("AUDIT_CATEGORIES_INVALID")
    else:
        audit = dict(raw_audit)
        missing = sorted(set(expected_audit) - set(audit))
        unknown = sorted(set(audit) - set(expected_audit))
        input_failures.extend(
            f"AUDIT_CATEGORY_MISSING:{name}" for name in missing
        )
        input_failures.extend(
            f"AUDIT_CATEGORY_UNKNOWN:{name}" for name in unknown
        )
        for name in sorted(set(expected_audit) & set(audit)):
            if audit[name] != expected_audit[name]:
                input_failures.append(f"AUDIT_BASELINE_MISMATCH:{name}")

    raw_changeset_ids = document.get("changeset_ids")
    changeset_ids = (
        list(raw_changeset_ids) if _valid_string_list(raw_changeset_ids) else []
    )
    if not _valid_string_list(raw_changeset_ids):
        input_failures.append("CHANGESET_IDS_INVALID")

    raw_conflict_ids = document.get("conflict_ids")
    conflict_ids = (
        list(raw_conflict_ids) if _valid_string_list(raw_conflict_ids) else []
    )
    if not _valid_string_list(raw_conflict_ids):
        input_failures.append("CONFLICT_IDS_INVALID")

    raw_parity = parity_result if isinstance(parity_result, dict) else {}
    if not isinstance(parity_result, dict):
        input_failures.append("STATE_PARITY_INVALID")
    if raw_parity.get("contract") != ADAPTER_CONTRACT:
        input_failures.append("STATE_PARITY_CONTRACT_MISMATCH")
    if raw_parity.get("result") != "PASS":
        input_failures.append("STATE_PARITY_NOT_PASS")

    parity_failures = raw_parity.get("failures")
    if not _valid_string_list(parity_failures):
        input_failures.append("STATE_PARITY_FAILURES_INVALID")
    elif parity_failures:
        input_failures.append("STATE_PARITY_FAILURES_PRESENT")

    if raw_parity.get("source_schema_version") != SOURCE_SCHEMA_VERSION:
        input_failures.append("STATE_PARITY_SOURCE_SCHEMA_MISMATCH")
    if raw_parity.get("target_schema_version") != TARGET_SCHEMA_VERSION:
        input_failures.append("STATE_PARITY_TARGET_SCHEMA_MISMATCH")
    if raw_parity.get("source_snapshot_sha256") != TRUSTED_SOURCE_SNAPSHOT_SHA256:
        input_failures.append("STATE_PARITY_SOURCE_SNAPSHOT_MISMATCH")

    mapped_counts = raw_parity.get("mapped_counts")
    if not _valid_count_map(mapped_counts):
        input_failures.append("STATE_PARITY_MAPPED_COUNTS_INVALID")
    elif mapped_counts != expected_mapped_counts:
        input_failures.append("STATE_PARITY_MAPPED_COUNTS_MISMATCH")

    if raw_parity.get("changeset_created") is not False:
        input_failures.append("STATE_PARITY_CHANGESET_CREATED")

    state_parity = _normalized_parity(raw_parity, input_failures)
    if input_failures:
        return _result(
            schema_version=(
                schema_version
                if isinstance(schema_version, int)
                and not isinstance(schema_version, bool)
                else None
            ),
            audit=audit,
            state_parity=state_parity,
            changeset_ids=changeset_ids,
            conflict_ids=conflict_ids,
            exit_code=EXIT_PROVENANCE,
        )

    exit_code = _strict_exit_code(audit, conflict_ids)
    return _result(
        schema_version=schema_version,
        audit=audit,
        state_parity=state_parity,
        changeset_ids=changeset_ids,
        conflict_ids=conflict_ids,
        exit_code=exit_code,
    )


def build_parser() -> argparse.ArgumentParser:
    parser = ProvenanceArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--target", type=Path, required=True)
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--sidecar", type=Path, required=True)
    parser.add_argument("--audit", type=Path, required=True)
    return parser


def main(
    argv: Sequence[str] | None = None,
    parity_fn: Callable[[Path, Path, Path, Path], dict[str, Any]] = adapter_parity,
) -> int:
    try:
        args = build_parser().parse_args(argv)
        audit_document = json.loads(args.audit.read_text(encoding="utf-8"))
        parity_result = parity_fn(
            args.source,
            args.target,
            args.fixture,
            args.sidecar,
        )
        result = evaluate_strict_audit(audit_document, parity_result)
    except Exception as error:
        result = _result(
            schema_version=None,
            audit={},
            state_parity=_normalized_parity(
                None,
                [f"PROVENANCE_READ_FAILED:{type(error).__name__}"],
            ),
            changeset_ids=[],
            conflict_ids=[],
            exit_code=EXIT_PROVENANCE,
        )
    print(json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    return int(result["exit_code"])


if __name__ == "__main__":
    raise SystemExit(main())
