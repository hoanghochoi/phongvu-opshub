#!/usr/bin/env node

import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

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

function assertNoLocalIdentity(value) {
  const serialized = JSON.stringify(value).replace(/https?:\/\//gi, "");
  assert(
    !/[A-Za-z]:[\\/]|(?:^|[\\/])Users(?:[\\/]|$)/i.test(serialized),
    "evidence contains an absolute local path or username",
  );
}

export function validateEvidence(evidence, root = process.cwd()) {
  assert(evidence?.formatVersion === 1, "formatVersion must be 1");
  assert(evidence.issue === "OPS-75", "issue must be OPS-75");
  assert(evidence.initiative === "OPS-64", "initiative must be OPS-64");
  assertRevision(evidence.sourceRevision, "sourceRevision");
  assertRevision(evidence.previousRevision, "previousRevision");

  const checkpoint = evidence.checkpoint;
  assertRevision(checkpoint?.originStaging, "checkpoint.originStaging");
  assertRevision(checkpoint?.originMain, "checkpoint.originMain");
  assert(checkpoint.originStaging === evidence.sourceRevision, "source and staging checkpoint differ");
  assert(checkpoint.worktreeCleanAtStart === true, "worktree must be clean at start");
  assert(checkpoint.productionPromotion === false, "production promotion must remain false");

  const staging = evidence.staging;
  assertRevision(staging?.mergeSha, "staging.mergeSha");
  assert(staging.mergeSha === evidence.sourceRevision, "staging merge SHA must be the current checkpoint");
  assert(/^\d+$/.test(String(staging.deployRun || "")), "staging.deployRun must be a workflow run id");
  assert(staging.deployConclusion === "success", "staging deploy must pass");
  assert(staging.exactShaVerified === true, "staging SHA must be verified");
  const requiredChecks = [
    "release guard",
    "affected verification shadow",
    "OPS-72 execution canary",
    "Android build",
    "Windows build/sign/upload",
    "web/backend deploy",
    "direct-origin routes",
    "health/version metadata",
    "final staging checkpoint",
  ];
  for (const check of requiredChecks) assert(staging.checks?.includes(check), `missing staging check: ${check}`);

  assert(evidence.phase10?.status === "complete", "Phase 10 must be complete");
  assert(evidence.phase10?.promotionEligible === true, "Phase 10 must be promotion eligible");
  assert(evidence.phase10?.productionPromotion === false, "Phase 10 proof cannot claim production promotion");

  const verification = evidence.verification;
  assert(verification?.runner === "node scripts/verify-task.mjs", "verification runner is invalid");
  assertRevision(verification.base, "verification.base");
  assertRevision(verification.head, "verification.head");
  assert(Array.isArray(verification.profiles) && verification.profiles.length === 8, "verification profiles are incomplete");
  assert(verification.status === "passed", "verification must pass");
  assert(verification.stale === false, "verification must not be stale");
  assert(verification.commandCount === 41, "verification command count is invalid");
  assert(/^[a-f0-9]{64}$/i.test(String(verification.fingerprint || "")), "verification fingerprint is invalid");
  assert(typeof verification.evidenceSource === "string" && verification.evidenceSource.trim(), "verification evidence source is required");

  const upstream = evidence.upstreamException;
  assert(upstream?.decision === "defer-and-do-not-pursue-in-this-initiative", "upstream decision is invalid");
  assert(upstream?.releasePin === "harness-v0.1.8", "release pin must remain harness-v0.1.8");
  assert(upstream?.updateInvocation === false, "release workflow must not invoke updater");
  assert(upstream?.forkOrPatch === false, "fork or patch must remain disabled");
  assert(typeof upstream.reason === "string" && upstream.reason.trim(), "upstream exception reason is required");

  for (const field of ["runtimeChanged", "dependencyChanged", "archiveChanged", "harnessDbChanged", "productionPromotion"]) {
    assert(evidence.scope?.[field] === false, `scope.${field} must remain false`);
  }
  assert(typeof evidence.rollback === "string" && evidence.rollback.includes("squash revert"), "rollback is missing");
  assert(existsSync(path.resolve(root, "docs/plans/active/OPS-64-upstream-harness-repository-cleanup.md")), "master plan is missing");
  assertNoLocalIdentity(evidence);
  return { status: "passed", issue: evidence.issue, phase10: evidence.phase10.status };
}

export function main(argv = process.argv.slice(2), root = process.cwd()) {
  const inputIndex = argv.indexOf("--input");
  const input = inputIndex >= 0 ? argv[inputIndex + 1] : "docs/migrations/ops-75-final-release-proof.json";
  if (!input || input.startsWith("--")) fail("--input requires a path");
  const evidence = JSON.parse(readFileSync(path.resolve(root, input), "utf8"));
  const result = validateEvidence(evidence, root);
  console.log(`OPS75 FINAL RELEASE PROOF PASS issue=${result.issue} phase10=${result.phase10}`);
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    process.exitCode = main();
  } catch (error) {
    console.error(`OPS75 FINAL RELEASE PROOF FAIL: ${error.message}`);
    process.exitCode = Number.isInteger(error.code) ? error.code : 2;
  }
}
