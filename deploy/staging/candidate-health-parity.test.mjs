import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { textSha256, validateEvidence } from "./candidate-health-parity.mjs";

const fixture = JSON.parse(
  readFileSync("docs/migrations/ops-206-candidate-health-parity.json", "utf8"),
);

test("accepts the hash-bound offline candidate health/Home parity preflight", () => {
  assert.deepEqual(validateEvidence(fixture), {
    status: "passed",
    issue: "OPS-206",
    mode: "offline-preflight",
    sourceRevision: "0bf7648f7816a201ba6ac142b8354b5e4e7afd43",
    releaseCount: 2,
    homeRanges: 4,
    promotionEligible: false,
  });
});

test("normalizes tracked source EOL before hashing", () => {
  const source = readFileSync("docs/migrations/ops-204-migration-home-preflight.json");
  const crlf = Buffer.from(
    source.toString("utf8").replace(/\r\n/g, "\n").replace(/\n/g, "\r\n"),
  );
  const expected = fixture.sourceFiles.find(
    (entry) => entry.path === "docs/migrations/ops-204-migration-home-preflight.json",
  ).sha256;
  assert.equal(textSha256(source), expected);
  assert.equal(textSha256(crlf), expected);
});

test("rejects release identity drift and same-color candidates", () => {
  const invalidDigest = structuredClone(fixture);
  invalidDigest.releaseIdentities[1].imageDigest = "sha256:not-a-digest";
  assert.throws(() => validateEvidence(invalidDigest), /candidate\.imageDigest/);

  const invalidColor = structuredClone(fixture);
  invalidColor.releaseIdentities[1].color = "blue";
  assert.throws(() => validateEvidence(invalidColor), /colors must differ/);
});

test("rejects missing Home range or failed authenticated gate", () => {
  const invalidRange = structuredClone(fixture);
  invalidRange.gates.homeParity.ranges = invalidRange.gates.homeParity.ranges.filter(
    (range) => range.days !== 30,
  );
  assert.throws(() => validateEvidence(invalidRange), /must cover 1\/7\/30\/90/);

  const invalidAuth = structuredClone(fixture);
  invalidAuth.gates.authenticated.meStatus = 401;
  assert.throws(() => validateEvidence(invalidAuth), /meStatus must be 200/);
});

test("rejects stale source hashes, source revisions and mutation claims", () => {
  const invalidSource = structuredClone(fixture);
  invalidSource.sourceFiles[0].sha256 = "f".repeat(64);
  assert.throws(() => validateEvidence(invalidSource), /source file digest mismatch/);

  const invalidRevision = structuredClone(fixture);
  invalidRevision.sourceRevision = "1".repeat(40);
  assert.throws(() => validateEvidence(invalidRevision), /git lookup failed/);

  const invalidMutation = structuredClone(fixture);
  invalidMutation.safety.trafficSwitchPerformed = true;
  assert.throws(() => validateEvidence(invalidMutation), /trafficSwitchPerformed/);
});

test("rejects credentials and promotion claims", () => {
  const leaked = structuredClone(fixture);
  leaked.gates.authenticated[["authorization", "Header"].join("")] = [
    "Bearer",
    "fixture-token",
  ].join(" ");
  assert.throws(() => validateEvidence(leaked), /authorization credential/);

  const promoted = structuredClone(fixture);
  promoted.safety.promotionEligible = true;
  assert.throws(() => validateEvidence(promoted), /promotionEligible/);
});
