#!/usr/bin/env node

import { readFileSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const SHA256 = /^[a-f0-9]{64}$/i;
const REVISION = /^[a-f0-9]{40}$/i;

function fail(message) {
  const error = new Error(message);
  error.code = 2;
  throw error;
}

function assert(condition, message) {
  if (!condition) fail(message);
}

function assertRevision(value, label) {
  assert(
    REVISION.test(String(value || "")),
    `${label} must be a 40-character Git revision`,
  );
}

function assertNoLocalPathOrIdentity(value) {
  const serialized = JSON.stringify(value);
  assert(
    !/[A-Za-z]:[\\/]|(?:^|[\\/])Users(?:[\\/]|$)/i.test(serialized),
    "evidence contains an absolute local path or username",
  );
}

function validateProbe(probe, label) {
  assert(probe && typeof probe === "object", `${label} is required`);
  assert(probe.status === "passed", `${label}.status must be passed`);
  assert(probe.exitCode === 0, `${label}.exitCode must be 0`);
  assert(
    probe.sourceMutation === false,
    `${label} must prove no source mutation`,
  );
}

export function validateEvidence(evidence) {
  assert(evidence?.formatVersion === 1, "formatVersion must be 1");
  assert(evidence.issue === "OPS-189", "issue must be OPS-189");
  assertRevision(evidence.sourceRevision, "sourceRevision");
  assert(
    evidence.provenance?.releaseTag === "harness-v0.1.8",
    "releaseTag must remain harness-v0.1.8",
  );
  assert(
    evidence.provenance?.installedVersion === "0.1.8",
    "installedVersion must remain 0.1.8",
  );
  assert(
    SHA256.test(String(evidence.provenance?.binarySha256 || "")),
    "binarySha256 must be a SHA-256 digest",
  );

  validateProbe(evidence.readOnlyProbes?.statusJson, "statusJson");
  validateProbe(evidence.readOnlyProbes?.doctorJson, "doctorJson");
  assert(
    evidence.readOnlyProbes.doctorJson.healthy === true,
    "doctorJson must be healthy",
  );

  const update = evidence.updateDryRun;
  assert(
    update?.status === "blocked-upstream",
    "updateDryRun must be blocked-upstream",
  );
  assert(
    update.disposition === "blocked-upstream",
    "updateDryRun disposition must be blocked-upstream",
  );
  assert(update.outerExitCode === 1, "updateDryRun outerExitCode must be 1");
  assert(
    Number.isInteger(update.innerExitCode) &&
      update.innerExitCode >= 1 &&
      update.innerExitCode <= 127,
    "updateDryRun innerExitCode must be a Git conflict exit range",
  );
  assert(
    /git merge-file/i.test(update.failure),
    "updateDryRun failure must identify git merge-file",
  );
  assert(
    update.sourceMutation === false,
    "updateDryRun must prove no source mutation",
  );
  assertRevision(
    update.sourceRevisionBefore,
    "updateDryRun.sourceRevisionBefore",
  );
  assertRevision(
    update.sourceRevisionAfter,
    "updateDryRun.sourceRevisionAfter",
  );
  assert(
    update.sourceRevisionBefore === update.sourceRevisionAfter,
    "updateDryRun source revisions must match",
  );
  assert(
    update.requiresTaggedUpstreamFix === true,
    "updateDryRun must require a tagged upstream fix",
  );

  const current = evidence.currentProbe;
  assert(
    current?.status === "blocked-upstream",
    "currentProbe must remain fail-closed",
  );
  assert(
    current.disposition === "blocked-upstream",
    "currentProbe disposition must be blocked-upstream",
  );
  assert(
    current.classification === "environment-failure",
    "currentProbe must distinguish network failure from updater health",
  );
  assert(current.outerExitCode !== 0, "currentProbe must not be a pass");
  assert(
    current.sourceMutation === false,
    "currentProbe must prove no source mutation",
  );
  assertRevision(
    current.sourceRevisionBefore,
    "currentProbe.sourceRevisionBefore",
  );
  assertRevision(
    current.sourceRevisionAfter,
    "currentProbe.sourceRevisionAfter",
  );
  assert(
    current.sourceRevisionBefore === current.sourceRevisionAfter,
    "currentProbe source revisions must match",
  );

  assert(
    evidence.adoptionPolicy?.adoptionAllowed === false,
    "adoption must remain blocked",
  );
  assert(
    evidence.adoptionPolicy?.patchOrForkAllowed === false,
    "patch/fork must remain disallowed",
  );
  assert(
    Array.isArray(evidence.adoptionPolicy?.requiredBeforeAdoption) &&
      evidence.adoptionPolicy.requiredBeforeAdoption.length >= 3,
    "adoption prerequisites are incomplete",
  );
  assert(
    evidence.dependencyProof?.status === "deferred-fail-closed",
    "dependency proof must remain explicitly deferred",
  );
  assertNoLocalPathOrIdentity(evidence);
  return {
    status: "passed",
    issue: evidence.issue,
    disposition: "blocked-upstream",
  };
}

export function main(argv = process.argv.slice(2), root = process.cwd()) {
  const inputIndex = argv.indexOf("--input");
  const input =
    inputIndex >= 0
      ? argv[inputIndex + 1]
      : "docs/migrations/ops-189-updater-blocked-upstream.json";
  if (!input || input.startsWith("--")) fail("--input requires a path");
  const resolved = path.resolve(root, input);
  const evidence = JSON.parse(readFileSync(resolved, "utf8"));
  const result = validateEvidence(evidence);
  console.log(
    `UPSTREAM EVIDENCE PASS issue=${result.issue} disposition=${result.disposition}`,
  );
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    process.exitCode = main();
  } catch (error) {
    console.error(`UPSTREAM EVIDENCE FAIL: ${error.message}`);
    process.exitCode = Number.isInteger(error.code) ? error.code : 2;
  }
}
