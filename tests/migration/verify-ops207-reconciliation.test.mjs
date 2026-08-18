import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { validateEvidence } from "../../scripts/verify-ops207-reconciliation.mjs";

const fixture = JSON.parse(
  readFileSync("docs/migrations/ops-207-master-plan-reconciliation.json", "utf8"),
);

test("accepts exact OPS-206 merge/deploy proof and residual ownership", () => {
  assert.deepEqual(validateEvidence(fixture), {
    status: "passed",
    issue: "OPS-207",
    residualCount: 7,
    sourceRevision: "d036994da22327ebdcbcfd5e05928f67dbc03e94",
  });
});

test("rejects stale merge/deploy identity or a promoted checkpoint", () => {
  const invalid = structuredClone(fixture);
  invalid.ops206.mergeSha = "0".repeat(40);
  assert.throws(() => validateEvidence(invalid), /ops206\.mergeSha/);

  const promoted = structuredClone(fixture);
  promoted.promotionPerformed = true;
  assert.throws(() => validateEvidence(promoted), /promotion/);
});

test("rejects missing residual ownership or absolute path leakage", () => {
  const invalid = structuredClone(fixture);
  invalid.residuals[1].issue = "OPS-72";
  assert.throws(() => validateEvidence(invalid), /duplicate residual/);

  const leaked = structuredClone(fixture);
  leaked.residuals[0].nextAction = "C:\\Users\\someone\\private";
  assert.throws(() => validateEvidence(leaked), /absolute local path/);
});
