from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[2] / "scripts" / "promote-harness-authority.py"
SPEC = importlib.util.spec_from_file_location("promote_harness_authority", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class PromoteHarnessAuthorityTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.root = Path(__file__).parents[2]
        cls.ledger_path = cls.root / "docs/migrations/harness-v1-disposition.json"
        cls.archive_manifest_path = cls.root / "docs/migrations/harness-v1-archive-manifest.json"
        cls.target_path = cls.root / "docs/migrations/harness-v1-linear-targets.json"
        cls.report = json.loads(
            (cls.root / "docs/migrations/harness-v1-authority-promotion.json").read_text(
                encoding="utf-8"
            )
        )

    def test_target_manifest_requires_complete_backlog_coverage(self) -> None:
        document = {
            "formatVersion": 1,
            "targets": [
                {"id": "OPS-76", "kind": "child-issue", "scope": "scope", "sourceBacklogIds": [1]}
            ],
        }
        with self.assertRaisesRegex(ValueError, "LINEAR_TARGET_BACKLOG_COVERAGE_INVALID"):
            MODULE.validate_target_manifest(document)

    def test_safe_path_rejects_missing_and_traversal(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "docs").mkdir()
            (root / "docs" / "authority.md").write_text("ok\n", encoding="utf-8")
            self.assertEqual(MODULE.safe_path(root, "docs/authority.md"), "docs/authority.md")
            with self.assertRaisesRegex(ValueError, "TARGET_PATH_NOT_FOUND"):
                MODULE.safe_path(root, "docs/missing.md")
            with self.assertRaisesRegex(ValueError, "TARGET_PATH_INVALID"):
                MODULE.safe_path(root, "../outside.md")

    def test_policy_is_explicitly_non_mutating(self) -> None:
        policy = {
            "archiveReadOnly": True,
            "databaseWritten": False,
            "rawPayloadCommitted": False,
            "rowForRowMarkdownMigration": False,
        }
        self.assertEqual(policy["archiveReadOnly"], True)
        self.assertFalse(policy["databaseWritten"])
        self.assertFalse(policy["rawPayloadCommitted"])
        self.assertFalse(policy["rowForRowMarkdownMigration"])

    def test_backlog_groups_match_the_tracked_linear_manifest(self) -> None:
        manifest = json.loads(
            (Path(__file__).parents[2] / "docs/migrations/harness-v1-linear-targets.json").read_text(
                encoding="utf-8"
            )
        )
        targets = MODULE.validate_target_manifest(manifest)
        self.assertEqual(targets["OPS-78"]["sourceBacklogIds"], [14, 17, 26])
        self.assertNotIn(17, targets["OPS-79"]["sourceBacklogIds"])

    def test_report_semantics_are_recomputed_from_ledger(self) -> None:
        MODULE.validate_report(
            self.report,
            self.root,
            self.ledger_path,
            self.archive_manifest_path,
            self.target_path,
        )
        tampered = json.loads(json.dumps(self.report))
        tampered["summary"]["recordCount"] += 1
        with self.assertRaisesRegex(ValueError, "PROMOTION_REPORT_SEMANTIC_MISMATCH"):
            MODULE.validate_report(
                tampered,
                self.root,
                self.ledger_path,
                self.archive_manifest_path,
                self.target_path,
            )

    def test_report_source_must_match_archive_manifest(self) -> None:
        tampered = json.loads(json.dumps(self.report))
        tampered["source"]["schemaVersion"] = 11
        with self.assertRaisesRegex(ValueError, "PROMOTION_REPORT_SOURCE_SCHEMAVERSION_MISMATCH"):
            MODULE.validate_report(
                tampered,
                self.root,
                self.ledger_path,
                self.archive_manifest_path,
                self.target_path,
            )


if __name__ == "__main__":
    unittest.main()
