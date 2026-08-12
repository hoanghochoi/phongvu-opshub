from __future__ import annotations

import importlib.util
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[2] / "scripts" / "archive-harness-legacy.py"
SPEC = importlib.util.spec_from_file_location("archive_harness_legacy", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def create_db(path: Path) -> None:
    connection = sqlite3.connect(path)
    connection.executescript(
        """
        PRAGMA foreign_keys=ON;
        CREATE TABLE schema_version(version INTEGER PRIMARY KEY);
        CREATE TABLE intake(id INTEGER PRIMARY KEY, status TEXT NOT NULL);
        CREATE TABLE story(
            id TEXT PRIMARY KEY,
            status TEXT NOT NULL,
            contract_doc TEXT
        );
        CREATE TABLE decision(
            id TEXT PRIMARY KEY,
            status TEXT NOT NULL,
            doc_path TEXT
        );
        CREATE TABLE backlog(id INTEGER PRIMARY KEY, status TEXT NOT NULL);
        CREATE TABLE trace(
            id INTEGER PRIMARY KEY,
            status TEXT NOT NULL,
            intake_id INTEGER REFERENCES intake(id)
        );
        CREATE TABLE auxiliary(key TEXT PRIMARY KEY, value BLOB);
        """
    )
    connection.executemany(
        "INSERT INTO schema_version(version) VALUES (?)",
        [(value,) for value in range(1, 13)],
    )
    for table, count in MODULE.EXPECTED_COUNTS.items():
        if table == "story":
            connection.executemany(
                "INSERT INTO story(id,status,contract_doc) VALUES (?,?,?)",
                [
                    (f"STORY-{index + 1:03d}", "implemented", None)
                    for index in range(count)
                ],
            )
        elif table == "decision":
            connection.executemany(
                "INSERT INTO decision(id,status,doc_path) VALUES (?,?,?)",
                [
                    (f"{index + 1:04d}", "accepted", None)
                    for index in range(count)
                ],
            )
        elif table == "trace":
            connection.executemany(
                "INSERT INTO trace(id,status,intake_id) VALUES (?,?,?)",
                [(index + 1, "recorded", None) for index in range(count)],
            )
        else:
            connection.executemany(
                f"INSERT INTO {table}(id,status) VALUES (?,?)",
                [(index + 1, "recorded") for index in range(count)],
            )
    connection.execute("INSERT INTO auxiliary(key,value) VALUES (?,?)", ("binary", b"\x00\xff"))
    connection.commit()
    connection.close()


def namespace(**values: object) -> object:
    return type("Args", (), values)()


class ArchiveHarnessLegacyTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.source = self.root / "source" / "harness.db"
        self.source.parent.mkdir()
        create_db(self.source)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def export_disposition(self, output: Path | None = None) -> Path:
        output = output or self.root / "local" / "disposition.json"
        args = namespace(
            source=self.source,
            repository_root=self.root,
            output=output,
        )
        self.assertEqual(MODULE.disposition(args), 0)
        return output

    def archive(self, disposition: Path) -> tuple[Path, Path, Path]:
        primary = self.root / "primary"
        secondary = self.root / "secondary"
        manifest = self.root / "evidence" / "manifest.json"
        args = namespace(
            source=self.source,
            primary=primary,
            secondary=secondary,
            manifest=manifest,
            disposition=disposition,
            repository_revision="0" * 40,
            legacy_tool_tag=MODULE.LEGACY_TOOL_TAG,
            legacy_tool_sha256="a" * 64,
            residual_risk="same-physical-disk-not-off-host",
        )
        self.assertEqual(MODULE.archive(args), 0)
        return primary / "harness.db", secondary / "harness.db", manifest

    def test_source_metadata_requires_exact_schema_counts_and_all_table_digests(self) -> None:
        metadata = MODULE.source_metadata(self.source)
        self.assertEqual(metadata["schemaVersions"], list(range(1, 13)))
        self.assertEqual(metadata["logicalCounts"], MODULE.EXPECTED_COUNTS)
        self.assertIn("auxiliary", metadata["tableDigests"])
        self.assertRegex(metadata["logicalStateSha256"], r"^[0-9a-f]{64}$")
        self.assertRegex(metadata["schemaSha256"], r"^[0-9a-f]{64}$")

    def test_archive_creates_and_validates_two_online_backups(self) -> None:
        source_before = MODULE.source_file_hashes(self.source)
        disposition = self.export_disposition()
        primary_db, secondary_db, manifest_path = self.archive(disposition)

        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        self.assertEqual(manifest["source"]["logicalCounts"], MODULE.EXPECTED_COUNTS)
        self.assertEqual(manifest["dispositionSha256"], MODULE.sha256(disposition))
        self.assertEqual(
            manifest["copies"][0]["logicalStateSha256"],
            manifest["source"]["logicalStateSha256"],
        )
        self.assertEqual(source_before, MODULE.source_file_hashes(self.source))
        self.assertEqual(
            MODULE.validate_archive(
                namespace(
                    manifest=manifest_path,
                    disposition=disposition,
                    primary_db=primary_db,
                    secondary_db=secondary_db,
                )
            ),
            0,
        )

    def test_archive_detects_logical_tampering_even_when_counts_match(self) -> None:
        disposition = self.export_disposition()
        primary_db, secondary_db, manifest_path = self.archive(disposition)
        connection = sqlite3.connect(primary_db)
        connection.execute("UPDATE auxiliary SET value=? WHERE key='binary'", (b"changed",))
        connection.commit()
        connection.close()

        with self.assertRaisesRegex(ValueError, "ARCHIVE_COPY_HASH_MISMATCH"):
            MODULE.validate_archive(
                namespace(
                    manifest=manifest_path,
                    disposition=disposition,
                    primary_db=primary_db,
                    secondary_db=secondary_db,
                )
            )

    def test_validate_archive_can_require_existing_disposition_targets(self) -> None:
        docs = self.root / "docs"
        docs.mkdir()
        (docs / "authority.md").write_text("authority\n", encoding="utf-8")
        connection = sqlite3.connect(self.source)
        connection.execute(
            "UPDATE story SET contract_doc=? WHERE id='STORY-001'",
            ("docs/authority.md",),
        )
        connection.commit()
        connection.close()
        disposition = self.export_disposition()
        primary_db, secondary_db, manifest_path = self.archive(disposition)
        self.assertEqual(
            MODULE.validate_archive(
                namespace(
                    manifest=manifest_path,
                    disposition=disposition,
                    primary_db=primary_db,
                    secondary_db=secondary_db,
                    repository_root=self.root,
                )
            ),
            0,
        )
        (docs / "authority.md").unlink()
        with self.assertRaisesRegex(ValueError, "DISPOSITION_TARGET_NOT_FOUND"):
            MODULE.validate_archive(
                namespace(
                    manifest=manifest_path,
                    disposition=disposition,
                    primary_db=primary_db,
                    secondary_db=secondary_db,
                    repository_root=self.root,
                )
            )

    def test_archive_rejects_target_that_contains_source(self) -> None:
        disposition = self.export_disposition()
        args = namespace(
            source=self.source,
            primary=self.source.parent,
            secondary=self.root / "secondary",
            manifest=self.root / "manifest.json",
            disposition=disposition,
            repository_revision="0" * 40,
            legacy_tool_tag=MODULE.LEGACY_TOOL_TAG,
            legacy_tool_sha256="a" * 64,
            residual_risk="physical-disk-separation-unverified",
        )
        with self.assertRaisesRegex(ValueError, "ARCHIVE_PATH_CONTAINS_SOURCE"):
            MODULE.archive(args)

    def test_outputs_cannot_replace_source_sidecars_or_archive_copy(self) -> None:
        with self.assertRaisesRegex(ValueError, "OUTPUT_MUST_NOT_REPLACE_SOURCE"):
            MODULE.ensure_output_does_not_replace_source(
                Path(f"{self.source}-wal"), self.source
            )
        disposition = self.export_disposition()
        primary = self.root / "primary"
        secondary = self.root / "secondary"
        args = namespace(
            source=self.source,
            primary=primary,
            secondary=secondary,
            manifest=primary / "harness.db",
            disposition=disposition,
            repository_revision="0" * 40,
            legacy_tool_tag=MODULE.LEGACY_TOOL_TAG,
            legacy_tool_sha256="a" * 64,
            residual_risk="physical-disk-separation-unverified",
        )
        with self.assertRaisesRegex(ValueError, "MANIFEST_MUST_NOT_REPLACE_ARCHIVE_COPY"):
            MODULE.archive(args)

    def test_json_evidence_writer_refuses_to_overwrite_existing_file(self) -> None:
        output = self.root / "evidence.json"
        output.write_text("keep\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "OUTPUT_ALREADY_EXISTS"):
            MODULE.write_json(output, {"replacement": True})
        self.assertEqual(output.read_text(encoding="utf-8"), "keep\n")

    def test_disposition_is_deterministic_complete_and_payload_free(self) -> None:
        authoritative = self.root / "docs" / "product.md"
        authoritative.parent.mkdir()
        authoritative.write_text("authority\n", encoding="utf-8")
        connection = sqlite3.connect(self.source)
        connection.execute(
            "UPDATE story SET contract_doc=? WHERE id='STORY-001'",
            ("docs/product.md",),
        )
        connection.commit()
        connection.close()

        first = self.export_disposition(self.root / "first.json")
        second = self.export_disposition(self.root / "second.json")
        first_bytes = first.read_bytes()
        self.assertEqual(first_bytes, second.read_bytes())
        document = json.loads(first_bytes)
        self.assertEqual(document["recordCount"], 199)
        self.assertEqual(
            sum(1 for record in document["records"] if record["entity"] == "story"),
            MODULE.EXPECTED_COUNTS["story"],
        )
        story = next(
            record
            for record in document["records"]
            if record["entity"] == "story" and record["sourceId"] == "STORY-001"
        )
        self.assertEqual(story["targetRef"], "docs/product.md")
        self.assertEqual(story["disposition"], "already-authoritative")
        self.assertEqual(MODULE.validate_disposition(namespace(input=first)), 0)

    def test_disposition_does_not_export_absolute_or_traversal_paths(self) -> None:
        outside = self.root.parent / "outside-authority.md"
        outside.write_text("outside\n", encoding="utf-8")
        try:
            connection = sqlite3.connect(self.source)
            connection.execute(
                "UPDATE story SET contract_doc=? WHERE id='STORY-001'",
                (str(outside),),
            )
            connection.execute(
                "UPDATE story SET contract_doc=? WHERE id='STORY-002'",
                ("../outside-authority.md",),
            )
            connection.commit()
            connection.close()
            output = self.export_disposition()
            document = json.loads(output.read_text(encoding="utf-8"))
            targets = {
                record["sourceId"]: record["targetRef"]
                for record in document["records"]
                if record["entity"] == "story"
            }
            self.assertIsNone(targets["STORY-001"])
            self.assertIsNone(targets["STORY-002"])
        finally:
            outside.unlink(missing_ok=True)

    def test_validator_rejects_wrong_entity_distribution_and_required_target(self) -> None:
        output = self.export_disposition()
        document = json.loads(output.read_text(encoding="utf-8"))
        document["records"][0]["entity"] = "trace"
        document["records"][0]["sourceId"] = "unexpected-extra-record"
        document["records"].sort(key=lambda record: (record["entity"], record["sourceId"]))
        with self.assertRaisesRegex(ValueError, "DISPOSITION_ENTITY_COUNTS_MISMATCH"):
            MODULE.validate_disposition_document(document)

        document = json.loads(output.read_text(encoding="utf-8"))
        document["records"][0]["disposition"] = "promoted"
        document["records"][0]["targetRef"] = None
        with self.assertRaisesRegex(ValueError, "DISPOSITION_TARGET_REQUIRED"):
            MODULE.validate_disposition_document(document)

    def test_archive_rejects_disposition_payload_drift_against_source(self) -> None:
        disposition = self.export_disposition()
        document = json.loads(disposition.read_text(encoding="utf-8"))
        document["records"][0]["payloadSha256"] = "0" * 64
        drifted = self.root / "drifted-disposition.json"
        drifted.write_text(
            json.dumps(document, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
            + "\n",
            encoding="utf-8",
        )
        args = namespace(
            source=self.source,
            primary=self.root / "primary-drift",
            secondary=self.root / "secondary-drift",
            manifest=self.root / "manifest-drift.json",
            disposition=drifted,
            repository_revision="0" * 40,
            legacy_tool_tag=MODULE.LEGACY_TOOL_TAG,
            legacy_tool_sha256="a" * 64,
            residual_risk="same-physical-disk-not-off-host",
        )
        with self.assertRaisesRegex(ValueError, "DISPOSITION_SOURCE_PAYLOAD_MISMATCH"):
            MODULE.archive(args)

    def test_disposition_requires_source_revision(self) -> None:
        output = self.export_disposition()
        document = json.loads(output.read_text(encoding="utf-8"))
        document.pop("sourceRevision")
        with self.assertRaisesRegex(ValueError, "DISPOSITION_DOCUMENT_INVALID"):
            MODULE.validate_disposition_document(document)

    def test_archive_requires_exact_immutable_tool_identity(self) -> None:
        with self.assertRaisesRegex(ValueError, "LEGACY_TOOL_TAG_INVALID"):
            MODULE.validate_legacy_tool("0" * 40, "harness-cli-v0.1.11", "a" * 64)
        with self.assertRaisesRegex(ValueError, "LEGACY_TOOL_SHA256_INVALID"):
            MODULE.validate_legacy_tool("0" * 40, MODULE.LEGACY_TOOL_TAG, "not-a-hash")

    def test_archive_acl_hardening_is_a_noop_on_non_windows(self) -> None:
        # Windows applies the real icacls restriction; this test keeps the
        # exporter portable for CI hosts that do not expose Windows ACLs.
        MODULE.harden_archive_acl(self.root)


if __name__ == "__main__":
    unittest.main()
