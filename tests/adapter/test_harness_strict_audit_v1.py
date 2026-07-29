from __future__ import annotations

import contextlib
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "adapter" / "harness_strict_audit_v1.py"
sys.path.insert(0, str(ROOT / "scripts" / "adapter"))

import harness_strict_audit_v1 as strict  # noqa: E402


def baseline_document() -> dict[str, object]:
    return {
        "contract": strict.CONTRACT_VERSION,
        "source_revision": strict.TRUSTED_SOURCE_REVISION,
        "schema_version": strict.SOURCE_SCHEMA_VERSION,
        "source_snapshot_sha256": strict.TRUSTED_SOURCE_SNAPSHOT_SHA256,
        "audit": dict(strict.TRUSTED_AUDIT_COUNTS),
        "changeset_ids": [],
        "conflict_ids": [],
    }


def passing_parity() -> dict[str, object]:
    return {
        "contract": strict.ADAPTER_CONTRACT,
        "result": "PASS",
        "failures": [],
        "source_snapshot_sha256": strict.TRUSTED_SOURCE_SNAPSHOT_SHA256,
        "source_schema_version": strict.SOURCE_SCHEMA_VERSION,
        "target_schema_version": strict.TARGET_SCHEMA_VERSION,
        "mapped_counts": dict(strict.TRUSTED_MAPPED_COUNTS),
        "changeset_created": False,
    }


def run_main(
    document: dict[str, object],
    parity: dict[str, object] | None = None,
    parity_error: Exception | None = None,
) -> tuple[int, dict[str, object], str]:
    with tempfile.TemporaryDirectory() as directory:
        audit_path = Path(directory) / "audit.json"
        audit_path.write_text(json.dumps(document), encoding="utf-8")
        output = io.StringIO()

        def parity_fn(*_: object) -> dict[str, object]:
            if parity_error is not None:
                raise parity_error
            return parity if parity is not None else passing_parity()

        with contextlib.redirect_stdout(output):
            exit_code = strict.main(
                [
                    "--source",
                    str(Path(directory) / "source.db"),
                    "--target",
                    str(Path(directory) / "target.db"),
                    "--fixture",
                    str(Path(directory) / "fixture.json"),
                    "--sidecar",
                    str(Path(directory) / "sidecar.json"),
                    "--audit",
                    str(audit_path),
                ],
                parity_fn=parity_fn,
            )
    rendered = output.getvalue().strip()
    return exit_code, json.loads(rendered), rendered


class StrictAuditEvaluationTests(unittest.TestCase):
    def test_committed_baseline_fixture_matches_trusted_binding(self) -> None:
        fixture = json.loads(
            (
                ROOT
                / "tests"
                / "fixtures"
                / "harness"
                / "local-strict-audit-baseline-v1.json"
            ).read_text(encoding="utf-8")
        )
        self.assertEqual(baseline_document(), fixture)

    def test_revision_pinned_baseline_returns_two_with_stable_fields(self) -> None:
        result = strict.evaluate_strict_audit(
            baseline_document(),
            passing_parity(),
        )
        self.assertEqual(2, result["exit_code"])
        self.assertEqual(
            {
                "contract",
                "source_revision",
                "schema_version",
                "audit",
                "state_parity",
                "changeset_ids",
                "conflict_ids",
                "exit_code",
            },
            set(result),
        )
        self.assertEqual("PASS", result["state_parity"]["result"])
        self.assertIs(False, result["state_parity"]["changeset_created"])

    def test_reviewed_clean_binding_returns_zero(self) -> None:
        document = baseline_document()
        clean_counts = {
            name: 0 for name in strict.TRUSTED_AUDIT_COUNTS
        }
        document["audit"] = clean_counts
        with mock.patch.object(
            strict,
            "TRUSTED_AUDIT_COUNTS",
            clean_counts,
        ):
            result = strict.evaluate_strict_audit(
                document,
                passing_parity(),
            )
        self.assertEqual(0, result["exit_code"])

    def test_conflict_returns_three_before_audit_failure(self) -> None:
        document = baseline_document()
        document["conflict_ids"] = ["changeset-42"]
        result = strict.evaluate_strict_audit(
            document,
            passing_parity(),
        )
        self.assertEqual(3, result["exit_code"])

    def test_zeroed_caller_counts_cannot_manufacture_clean_exit(self) -> None:
        document = baseline_document()
        document["audit"] = {
            name: 0 for name in strict.TRUSTED_AUDIT_COUNTS
        }
        result = strict.evaluate_strict_audit(
            document,
            passing_parity(),
        )
        self.assertEqual(78, result["exit_code"])
        self.assertIn(
            "AUDIT_BASELINE_MISMATCH:orphaned_stories",
            result["state_parity"]["failures"],
        )

    def test_each_changed_count_fails_provenance(self) -> None:
        for name in strict.TRUSTED_AUDIT_COUNTS:
            with self.subTest(name=name):
                document = baseline_document()
                document["audit"][name] += 1
                result = strict.evaluate_strict_audit(
                    document,
                    passing_parity(),
                )
                self.assertEqual(78, result["exit_code"])
                self.assertIn(
                    f"AUDIT_BASELINE_MISMATCH:{name}",
                    result["state_parity"]["failures"],
                )

    def test_missing_and_unknown_categories_fail_provenance(self) -> None:
        missing = baseline_document()
        del missing["audit"]["broken_tools"]
        missing_result = strict.evaluate_strict_audit(
            missing,
            passing_parity(),
        )
        self.assertEqual(78, missing_result["exit_code"])
        self.assertIn(
            "AUDIT_CATEGORY_MISSING:broken_tools",
            missing_result["state_parity"]["failures"],
        )

        unknown = baseline_document()
        unknown["audit"]["future_category"] = 0
        unknown_result = strict.evaluate_strict_audit(
            unknown,
            passing_parity(),
        )
        self.assertEqual(78, unknown_result["exit_code"])
        self.assertIn(
            "AUDIT_CATEGORY_UNKNOWN:future_category",
            unknown_result["state_parity"]["failures"],
        )

    def test_forged_revision_is_not_self_attested(self) -> None:
        document = baseline_document()
        document["source_revision"] = "0" * 40
        result = strict.evaluate_strict_audit(
            document,
            passing_parity(),
        )
        self.assertEqual(78, result["exit_code"])
        self.assertIn(
            "SOURCE_REVISION_MISMATCH",
            result["state_parity"]["failures"],
        )
        self.assertEqual(
            strict.TRUSTED_SOURCE_REVISION,
            result["source_revision"],
        )

    def test_snapshot_mismatch_returns_seventy_eight(self) -> None:
        document = baseline_document()
        document["source_snapshot_sha256"] = "0" * 64
        result = strict.evaluate_strict_audit(
            document,
            passing_parity(),
        )
        self.assertEqual(78, result["exit_code"])
        self.assertIn(
            "SOURCE_SNAPSHOT_SHA_MISMATCH",
            result["state_parity"]["failures"],
        )

    def test_failed_parity_cannot_be_downgraded(self) -> None:
        parity = passing_parity()
        parity["result"] = "FAIL"
        parity["failures"] = ["TARGET_VALUE_MISMATCH:story:0:title"]
        result = strict.evaluate_strict_audit(
            baseline_document(),
            parity,
        )
        self.assertEqual(78, result["exit_code"])
        self.assertEqual("FAIL", result["state_parity"]["result"])

    def test_pass_with_failures_is_not_contradictory_clean_output(self) -> None:
        parity = passing_parity()
        parity["failures"] = ["TARGET_VALUE_MISMATCH:story:0:title"]
        result = strict.evaluate_strict_audit(
            baseline_document(),
            parity,
        )
        self.assertEqual(78, result["exit_code"])
        self.assertEqual("FAIL", result["state_parity"]["result"])
        self.assertIn(
            "STATE_PARITY_FAILURES_PRESENT",
            result["state_parity"]["failures"],
        )

    def test_malformed_failures_or_created_changeset_fail_provenance(self) -> None:
        malformed = passing_parity()
        malformed["failures"] = "none"
        malformed_result = strict.evaluate_strict_audit(
            baseline_document(),
            malformed,
        )
        self.assertEqual(78, malformed_result["exit_code"])
        self.assertIn(
            "STATE_PARITY_FAILURES_INVALID",
            malformed_result["state_parity"]["failures"],
        )

        created = passing_parity()
        created["changeset_created"] = True
        created_result = strict.evaluate_strict_audit(
            baseline_document(),
            created,
        )
        self.assertEqual(78, created_result["exit_code"])
        self.assertIn(
            "STATE_PARITY_CHANGESET_CREATED",
            created_result["state_parity"]["failures"],
        )

    def test_mapped_count_mismatch_fails_provenance(self) -> None:
        parity = passing_parity()
        parity["mapped_counts"]["story"] = 36
        result = strict.evaluate_strict_audit(
            baseline_document(),
            parity,
        )
        self.assertEqual(78, result["exit_code"])
        self.assertIn(
            "STATE_PARITY_MAPPED_COUNTS_MISMATCH",
            result["state_parity"]["failures"],
        )

    def test_main_emits_compact_json_and_returns_audit_exit(self) -> None:
        exit_code, result, rendered = run_main(baseline_document())
        self.assertEqual(2, exit_code)
        self.assertNotIn("\n", rendered)
        self.assertEqual(2, result["exit_code"])

    def test_main_converts_any_adapter_exception_to_provenance_json(self) -> None:
        exit_code, result, _ = run_main(
            baseline_document(),
            parity_error=AttributeError("tables"),
        )
        self.assertEqual(78, exit_code)
        self.assertEqual(78, result["exit_code"])
        self.assertIn(
            "PROVENANCE_READ_FAILED:AttributeError",
            result["state_parity"]["failures"],
        )

    def test_invalid_cli_arguments_emit_json_exit_seventy_eight(self) -> None:
        process = subprocess.run(
            [sys.executable, str(SCRIPT)],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(78, process.returncode)
        self.assertEqual("", process.stderr)
        result = json.loads(process.stdout)
        self.assertEqual(78, result["exit_code"])
        self.assertIn(
            "PROVENANCE_READ_FAILED:ValueError",
            result["state_parity"]["failures"],
        )

    def test_malformed_audit_file_emits_json_exit_seventy_eight(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            audit_path = Path(directory) / "audit.json"
            audit_path.write_text("{", encoding="utf-8")
            process = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--source",
                    str(Path(directory) / "source.db"),
                    "--target",
                    str(Path(directory) / "target.db"),
                    "--fixture",
                    str(Path(directory) / "fixture.json"),
                    "--sidecar",
                    str(Path(directory) / "sidecar.json"),
                    "--audit",
                    str(audit_path),
                ],
                cwd=ROOT,
                check=False,
                capture_output=True,
                text=True,
            )
        self.assertEqual(78, process.returncode)
        self.assertEqual("", process.stderr)
        result = json.loads(process.stdout)
        self.assertEqual(78, result["exit_code"])
        self.assertIn(
            "PROVENANCE_READ_FAILED:JSONDecodeError",
            result["state_parity"]["failures"],
        )


if __name__ == "__main__":
    unittest.main()
