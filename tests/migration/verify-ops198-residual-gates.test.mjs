import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { validateEvidence } from "../../scripts/verify-ops198-residual-gates.mjs";

const fixture = JSON.parse(
  readFileSync("docs/migrations/ops-198-residual-gate-reconciliation.json", "utf8"),
);

test("accepts the complete residual ownership ledger", () => {
  assert.deepEqual(validateEvidence(fixture), {
    status: "passed",
    issue: "OPS-198",
    residualCount: 7,
  });
});

test("rejects duplicate or missing residual ownership", () => {
  const invalid = structuredClone(fixture);
  invalid.residuals[1].issue = "OPS-72";
  assert.throws(() => validateEvidence(invalid), /duplicate residual/);
});

test("rejects production promotion or absolute identity leakage", () => {
  const invalid = structuredClone(fixture);
  invalid.scope.productionPromotion = true;
  assert.throws(() => validateEvidence(invalid), /productionPromotion/);
  invalid.scope.productionPromotion = false;
  invalid.residuals[0].nextAction = "C:\\Users\\someone\\private";
  assert.throws(() => validateEvidence(invalid), /absolute local path/);
});
