import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { validateEvidence } from "../../scripts/verify-harness-updater-blocked.mjs";

const fixture = JSON.parse(
  readFileSync("docs/migrations/ops-189-updater-blocked-upstream.json", "utf8"),
);

test("accepts sanitized blocked-upstream evidence with no-write proof", () => {
  assert.deepEqual(validateEvidence(fixture), {
    status: "passed",
    issue: "OPS-189",
    disposition: "blocked-upstream",
  });
});

test("rejects a dry-run evidence record that claims pass", () => {
  const invalid = structuredClone(fixture);
  invalid.updateDryRun.status = "passed";
  assert.throws(() => validateEvidence(invalid), /blocked-upstream/);
});

test("rejects evidence that reports source mutation", () => {
  const invalid = structuredClone(fixture);
  invalid.currentProbe.sourceMutation = true;
  assert.throws(() => validateEvidence(invalid), /no source mutation/);
});

test("keeps a release lookup failure distinct from updater health", () => {
  const invalid = structuredClone(fixture);
  invalid.currentProbe.classification = "shadow-observation";
  assert.throws(() => validateEvidence(invalid), /network failure/);
});

test("rejects an evidence record that permits a local fork", () => {
  const invalid = structuredClone(fixture);
  invalid.adoptionPolicy.patchOrForkAllowed = true;
  assert.throws(() => validateEvidence(invalid), /patch\/fork/);
});
