import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { validateEvidence } from "../../scripts/verify-ops75-final-release-proof.mjs";

const fixture = JSON.parse(
  readFileSync("docs/migrations/ops-75-final-release-proof.json", "utf8"),
);

test("accepts the final Phase 10 proof with explicit promotion boundary", () => {
  assert.deepEqual(validateEvidence(fixture), {
    status: "passed",
    issue: "OPS-75",
    phase10: "complete",
  });
});

test("rejects a production promotion claim", () => {
  const invalid = structuredClone(fixture);
  invalid.scope.productionPromotion = true;
  assert.throws(() => validateEvidence(invalid), /scope\.productionPromotion/);
});

test("rejects a fork or updater invocation", () => {
  const invalid = structuredClone(fixture);
  invalid.upstreamException.forkOrPatch = true;
  assert.throws(() => validateEvidence(invalid), /fork or patch/);
  invalid.upstreamException.forkOrPatch = false;
  invalid.upstreamException.updateInvocation = true;
  assert.throws(() => validateEvidence(invalid), /invoke updater/);
});
