import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import test from "node:test";

import { validateEvidence } from "../../scripts/verify-ops204-preflight.mjs";

const fixture = JSON.parse(
  readFileSync("docs/migrations/ops-204-migration-home-preflight.json", "utf8"),
);

test("accepts the hash-bound offline migration/Home preflight", () => {
  assert.deepEqual(validateEvidence(fixture), {
    status: "passed",
    issue: "OPS-204",
    mode: "offline-preflight",
    sourceCount: 7,
    releaseCount: 3,
    migrationCount: 4,
    promotionEligible: false,
  });
});

test("rejects missing or ambiguous release identity", () => {
  const invalid = structuredClone(fixture);
  invalid.releaseIdentities[2].commitSha = "not-a-sha";
  assert.throws(() => validateEvidence(invalid), /candidate\.commitSha/);
});

test("rejects destructive or digest-drifted migration evidence", () => {
  const invalid = structuredClone(fixture);
  invalid.migration.inventory[0].destructive = true;
  assert.throws(() => validateEvidence(invalid), /inventory digest does not match/);

  const destructive = structuredClone(fixture);
  destructive.migration.inventory[0].destructive = true;
  destructive.migration.inventorySha256 = createHash("sha256")
    .update(JSON.stringify(destructive.migration.inventory))
    .digest("hex");
  assert.throws(() => validateEvidence(destructive), /destructive migration/);
});

test("rejects Home proof threshold drift and mutation claims", () => {
  const invalidHome = structuredClone(fixture);
  invalidHome.homeProof.latencyMs.p95 = 501;
  assert.throws(() => validateEvidence(invalidHome), /p95 threshold drifted/);

  const invalidMutation = structuredClone(fixture);
  invalidMutation.safety.trafficSwitchPerformed = true;
  assert.throws(() => validateEvidence(invalidMutation), /trafficSwitchPerformed/);
});

test("rejects stale source hashes and production promotion", () => {
  const invalidSource = structuredClone(fixture);
  invalidSource.sourceFiles[0].sha256 = "f".repeat(64);
  assert.throws(() => validateEvidence(invalidSource), /source file digest mismatch/);

  const invalidHomeBinding = structuredClone(fixture);
  invalidHomeBinding.homeProof.profileSha256 = "e".repeat(64);
  assert.throws(() => validateEvidence(invalidHomeBinding), /Home proof digest binding mismatch/);

  const invalidPromotion = structuredClone(fixture);
  invalidPromotion.safety.productionPromotion = true;
  assert.throws(() => validateEvidence(invalidPromotion), /productionPromotion/);
});

test("rejects a replayed base revision or semantically unsafe topology evidence", () => {
  const invalidBase = structuredClone(fixture);
  invalidBase.baseRevision = "1111111111111111111111111111111111111111";
  assert.throws(() => validateEvidence(invalidBase), /OPS-201 topology merge/);

  const invalidTopology = structuredClone(fixture);
  invalidTopology.sourceFiles = invalidTopology.sourceFiles.map((entry) =>
    entry.path === "docs/migrations/ops-201-blue-green-topology-evidence.json"
      ? { ...entry, sha256: "0".repeat(64) }
      : entry,
  );
  assert.throws(() => validateEvidence(invalidTopology), /source file digest mismatch/);
});
