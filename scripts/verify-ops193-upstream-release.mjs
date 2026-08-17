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
  assert(REVISION.test(String(value || "")), `${label} must be a 40-character Git revision`);
}

function assertDigest(value, label) {
  assert(SHA256.test(String(value || "")), `${label} must be a SHA-256 digest`);
}

function assertNoLocalPathOrIdentity(value) {
  const serialized = JSON.stringify(value).replace(/https?:\/\//gi, "");
  assert(
    !/[A-Za-z]:[\\/]|(?:^|[\\/])Users(?:[\\/]|$)/i.test(serialized),
    "evidence contains an absolute local path or username",
  );
}

export function validateEvidence(evidence) {
  assert(evidence?.formatVersion === 1, "formatVersion must be 1");
  assert(evidence.issue === "OPS-193", "issue must be OPS-193");
  assertRevision(evidence.sourceRevision, "sourceRevision");

  const upstream = evidence.upstream;
  assert(upstream?.latestTaggedCore === "harness-v0.1.10", "latest tagged core must be harness-v0.1.10");
  assert(Array.isArray(upstream.tagsChecked) && upstream.tagsChecked.length === 2, "exactly two upstream tags must be checked");
  for (const tag of upstream.tagsChecked) {
    assert(["harness-v0.1.9", "harness-v0.1.10"].includes(tag.tag), `unexpected upstream tag: ${tag.tag}`);
    assertRevision(tag.tagCommit, `${tag.tag}.tagCommit`);
    assertDigest(tag.gitMergeSourceSha256, `${tag.tag}.gitMergeSourceSha256`);
    assert(tag.mapsExit1ToConflict === true, `${tag.tag} must map exit 1 to conflict`);
    assert(tag.handlesConflictCountExitRange === false, `${tag.tag} must not claim the missing exit-range fix`);
  }
  assert(
    upstream.tagsChecked[0].gitMergeSourceSha256 === upstream.tagsChecked[1].gitMergeSourceSha256,
    "checked releases must retain the same merge adapter source digest",
  );

  assert(evidence.consumerPin?.releaseTag === "harness-v0.1.8", "consumer pin must remain harness-v0.1.8");
  assert(evidence.consumerPin?.installedVersion === "0.1.8", "installed version must remain 0.1.8");
  assertDigest(evidence.consumerPin?.binarySha256, "consumerPin.binarySha256");

  const probe = evidence.disposableProbe;
  assert(probe?.statusJson?.status === "passed", "status probe must pass");
  assert(probe.statusJson.exitCode === 0, "status probe exit code must be 0");
  assert(probe.doctorJson?.status === "passed", "doctor probe must pass");
  assert(probe.doctorJson.exitCode === 0 && probe.doctorJson.healthy === true, "doctor probe must be healthy");
  const update = probe.updateDryRun;
  assert(update?.status === "blocked-upstream", "update dry-run must remain blocked-upstream");
  assert(update.outerExitCode === 1, "update dry-run outer exit code must be 1");
  assert(update.candidateVersion === "0.1.10", "update candidate must be 0.1.10");
  assert(/git merge-file/i.test(update.failure), "update failure must identify git merge-file");
  assert(update.sourceMutation === false && update.trackedMutation === false, "probe must prove no source mutation");
  assertRevision(update.sourceRevisionBefore, "updateDryRun.sourceRevisionBefore");
  assertRevision(update.sourceRevisionAfter, "updateDryRun.sourceRevisionAfter");
  assert(update.sourceRevisionBefore === update.sourceRevisionAfter, "probe source revisions must match");

  assert(evidence.adoptionPolicy?.currentPin === "harness-v0.1.8", "adoption policy pin must remain v0.1.8");
  assert(evidence.adoptionPolicy.adoptionAllowed === false, "adoption must remain blocked");
  assert(evidence.adoptionPolicy.patchOrForkAllowed === false, "patch/fork must remain disallowed");
  assert(
    Array.isArray(evidence.adoptionPolicy.requiredBeforeAdoption) &&
      evidence.adoptionPolicy.requiredBeforeAdoption.length >= 3,
    "adoption prerequisites are incomplete",
  );
  assert(evidence.scope?.runtimeChanged === false, "runtime scope must remain unchanged");
  assert(evidence.scope?.productionPromotion === false, "production promotion must remain false");
  assertNoLocalPathOrIdentity(evidence);
  return { status: "passed", issue: evidence.issue, disposition: "blocked-upstream" };
}

export function main(argv = process.argv.slice(2), root = process.cwd()) {
  const inputIndex = argv.indexOf("--input");
  const input = inputIndex >= 0 ? argv[inputIndex + 1] : "docs/migrations/ops-193-upstream-release-recheck.json";
  if (!input || input.startsWith("--")) fail("--input requires a path");
  const evidence = JSON.parse(readFileSync(path.resolve(root, input), "utf8"));
  const result = validateEvidence(evidence);
  console.log(`OPS193 UPSTREAM PASS issue=${result.issue} disposition=${result.disposition}`);
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    process.exitCode = main();
  } catch (error) {
    console.error(`OPS193 UPSTREAM FAIL: ${error.message}`);
    process.exitCode = Number.isInteger(error.code) ? error.code : 2;
  }
}
