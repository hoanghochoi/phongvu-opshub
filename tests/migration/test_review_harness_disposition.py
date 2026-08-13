from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[2] / "scripts" / "review-harness-disposition.py"
SPEC = importlib.util.spec_from_file_location("review_harness_disposition", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def valid_record(entity: str, source_id: str) -> dict[str, object]:
    return {
        "entity": entity,
        "sourceId": source_id,
        "sourceStatus": "recorded",
        "payloadSha256": "a" * 64,
        "disposition": "historical-only",
        "targetRef": None,
        "reasonCode": "historical-record",
    }


def valid_document() -> dict[str, object]:
    records = []
    for entity, count in MODULE.EXPECTED_COUNTS.items():
        for index in range(1, count + 1):
            records.append(valid_record(entity, str(index)))
    return {
        "formatVersion": 1,
        "sourceRevision": "0" * 40,
        "sourceSchemaVersion": 12,
        "recordCount": len(records),
        "allowedDispositions": sorted(MODULE.DISPOSITIONS),
        "records": records,
    }


class ReviewHarnessDispositionTest(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp())

    def tearDown(self) -> None:
        for path in sorted(self.root.rglob("*"), reverse=True):
            if path.is_file():
                path.unlink()
            elif path.is_dir():
                path.rmdir()
        self.root.rmdir()

    def test_validator_rejects_duplicate_record(self) -> None:
        document = valid_document()
        records = document["records"]
        assert isinstance(records, list)
        records[-1] = dict(records[0])
        with self.assertRaisesRegex(ValueError, "DISPOSITION_DUPLICATE"):
            MODULE.validate(document, self.root, set())

    def test_backlog_target_groups_do_not_overlap(self) -> None:
        self.assertEqual(MODULE.BACKLOG_TARGETS["14"][0], "OPS-78")
        self.assertEqual(MODULE.BACKLOG_TARGETS["17"][0], "OPS-78")
        self.assertEqual(MODULE.BACKLOG_TARGETS["26"][0], "OPS-78")
        for source_id in ("15", "16", "18", "19", "20", "21", "22", "23", "24", "25"):
            self.assertEqual(MODULE.BACKLOG_TARGETS[source_id][0], "OPS-79")

    def test_validator_rejects_missing_entity_record(self) -> None:
        document = valid_document()
        records = document["records"]
        assert isinstance(records, list)
        records.pop()
        document["recordCount"] = len(records)
        with self.assertRaisesRegex(ValueError, "DISPOSITION_ENTITY_COUNTS_INVALID"):
            MODULE.validate(document, self.root, set())

    def test_validator_rejects_missing_linear_target(self) -> None:
        document = valid_document()
        records = document["records"]
        assert isinstance(records, list)
        records[0] = {
            **records[0],
            "entity": "backlog",
            "sourceId": "1",
            "disposition": "linear-follow-up",
            "targetRef": "OPS-999",
        }
        records.sort(key=lambda record: (record["entity"], record["sourceId"]))
        with self.assertRaisesRegex(ValueError, "DISPOSITION_TARGET_INVALID"):
            MODULE.validate(document, self.root, set())

    def test_validator_rejects_payload_hash_mismatch_shape(self) -> None:
        document = valid_document()
        records = document["records"]
        assert isinstance(records, list)
        records[0]["payloadSha256"] = "not-a-hash"
        with self.assertRaisesRegex(ValueError, "DISPOSITION_PAYLOAD_HASH_INVALID"):
            MODULE.validate(document, self.root, set())

    def test_validator_rejects_invalid_reason_code(self) -> None:
        document = valid_document()
        records = document["records"]
        assert isinstance(records, list)
        records[0]["reasonCode"] = "not a reason"
        with self.assertRaisesRegex(ValueError, "DISPOSITION_REASON_INVALID"):
            MODULE.validate(document, self.root, set())

    def test_validator_rejects_non_string_target(self) -> None:
        document = valid_document()
        records = document["records"]
        assert isinstance(records, list)
        records[0]["targetRef"] = 123
        with self.assertRaisesRegex(ValueError, "DISPOSITION_TARGET_INVALID"):
            MODULE.validate(document, self.root, set())

    def test_archive_manifest_source_hash_is_checked(self) -> None:
        archive = self.root / "harness.db"
        archive.write_bytes(b"archive")
        manifest = {
            "formatVersion": 1,
            "source": {
                "repositoryRevision": "0" * 40,
                "schemaVersion": 12,
                "schemaVersions": list(range(1, 13)),
                "logicalCounts": MODULE.EXPECTED_COUNTS,
                "databaseSha256": "a" * 64,
                "sourceStateSha256": MODULE.digest_json({"databaseSha256": "a" * 64, "walSha256": None}),
                "logicalStateSha256": "b" * 64,
                "schemaSha256": "c" * 64,
            },
            "copies": [
                {
                    "label": "primary-local",
                    "fileName": "harness.db",
                    "integrityResult": "PASS",
                    "sha256": "a" * 64,
                    "logicalStateSha256": "b" * 64,
                },
                {
                    "label": "secondary-local",
                    "fileName": "harness.db",
                    "integrityResult": "PASS",
                    "sha256": "a" * 64,
                    "logicalStateSha256": "b" * 64,
                },
            ],
        }
        with self.assertRaisesRegex(ValueError, "ARCHIVE_MANIFEST_ARCHIVE_HASH_MISMATCH"):
            MODULE.validate_manifest_source(manifest, archive)

    def test_output_path_must_not_be_overwritten(self) -> None:
        output = self.root / "ledger.json"
        output.write_text(json.dumps({"keep": True}), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "OUTPUT_ALREADY_EXISTS"):
            MODULE.write_output(valid_document(), output)
        self.assertEqual(json.loads(output.read_text(encoding="utf-8")), {"keep": True})


if __name__ == "__main__":
    unittest.main()
