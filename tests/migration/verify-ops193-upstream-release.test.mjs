import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { validateEvidence } from "../../scripts/verify-ops193-upstream-release.mjs";

const fixture = JSON.parse(
  readFileSync("docs/migrations/ops-193-upstream-release-recheck.json", "utf8"),
);

test("accepts the sanitized release recheck and blocked-upstream proof", () => {
  assert.deepEqual(validateEvidence(fixture), {
    status: "passed",
    issue: "OPS-193",
    disposition: "blocked-upstream",
  });
});

test("rejects a release that claims the exit-range fix", () => {
  const invalid = structuredClone(fixture);
  invalid.upstream.tagsChecked[1].handlesConflictCountExitRange = true;
  assert.throws(() => validateEvidence(invalid), /missing exit-range fix/);
});

test("rejects a probe that claims a clean update", () => {
  const invalid = structuredClone(fixture);
  invalid.disposableProbe.updateDryRun.status = "passed";
  assert.throws(() => validateEvidence(invalid), /blocked-upstream/);
});

test("rejects adoption or production promotion", () => {
  const invalid = structuredClone(fixture);
  invalid.adoptionPolicy.adoptionAllowed = true;
  assert.throws(() => validateEvidence(invalid), /adoption/);
  invalid.adoptionPolicy.adoptionAllowed = false;
  invalid.scope.productionPromotion = true;
  assert.throws(() => validateEvidence(invalid), /production promotion/);
});
