#!/usr/bin/env node

import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const REVISION = /^[a-f0-9]{40}$/i;
const ISSUE = /^OPS-\d+$/;
const EXPECTED_RESIDUALS = new Set([
  "OPS-72",
  "OPS-190",
  "OPS-75",
  "OPS-78",
  "OPS-76",
  "OPS-77",
  "OPS-79",
]);

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

function assertIssue(value, label) {
  assert(ISSUE.test(String(value || "")), `${label} must be a Linear issue identifier`);
}

function assertNoLocalPathOrIdentity(value) {
  const serialized = JSON.stringify(value).replace(/https?:\/\//gi, "");
  assert(
    !/[A-Za-z]:[\\/]|(?:^|[\\/])Users(?:[\\/]|$)/i.test(serialized),
    "evidence contains an absolute local path or username",
  );
}

function assertExistingRepositoryPath(root, relativePath, label) {
  assert(
    typeof relativePath === "string" && !path.isAbsolute(relativePath),
    `${label} must be repository-relative`,
  );
  const absolute = path.resolve(root, relativePath);
  const relative = path.relative(root, absolute);
  assert(
    !path.isAbsolute(relative) && !relative.startsWith(".."),
    `${label} escapes repository root`,
  );
  assert(existsSync(absolute), `${label} does not exist: ${relativePath}`);
}

export function validateEvidence(evidence, root = process.cwd()) {
  assert(evidence?.formatVersion === 1, "formatVersion must be 1");
  assert(evidence.issue === "OPS-207", "issue must be OPS-207");
  assert(evidence.initiative === "OPS-64", "initiative must be OPS-64");
  assertRevision(evidence.sourceRevision, "sourceRevision");
  assertRevision(evidence.previousRevision, "previousRevision");
  assertRevision(evidence.originMain, "originMain");
  assert(evidence.promotionPerformed === false, "promotion must remain false");

  const ops206 = evidence.ops206;
  assert(ops206?.issue === "OPS-206", "ops206.issue must be OPS-206");
  assert(ops206.parentIssue === "OPS-78", "ops206.parentIssue must be OPS-78");
  assert(ops206.pullRequest === 331, "ops206.pullRequest must be 331");
  for (const field of ["implementationRevision", "mergeSha"]) {
    assertRevision(ops206[field], `ops206.${field}`);
  }
  assert(
    ops206.implementationRevision ===
      "0a0ed5d8dc9681475509f2cae8bda15d024c0d81",
    "ops206.implementationRevision is stale",
  );
  assert(
    ops206.mergeSha === "d036994da22327ebdcbcfd5e05928f67dbc03e94",
    "ops206.mergeSha is stale",
  );
  assert(ops206.stagingDeployRun === "32133397317", "ops206.stagingDeployRun is stale");
  for (const field of [
    "stagingDeployResult",
    "lifecycleFinish",
    "worktreeCleanup",
    "remoteBranchCleanup",
  ]) {
    assert(ops206[field] === "pass", `ops206.${field} must be pass`);
  }
  assertExistingRepositoryPath(root, ops206.evidence, "ops206.evidence");
  assert(ops206.productionPromotion === false, "ops206.productionPromotion must remain false");

  const verification = ops206.verification;
  assert(verification?.status === "passed", "ops206.verification.status must be passed");
  assert(verification?.stale === false, "ops206.verification.stale must be false");
  assertRevision(verification.base, "ops206.verification.base");
  assertRevision(verification.head, "ops206.verification.head");
  assert(
    verification.base === "0bf7648f7816a201ba6ac142b8354b5e4e7afd43",
    "ops206.verification.base is stale",
  );
  assert(
    verification.head === "d036994da22327ebdcbcfd5e05928f67dbc03e94",
    "ops206.verification.head is stale",
  );
  assert(
    Array.isArray(verification.profiles) &&
      verification.profiles.length === 4 &&
      ["harness", "docs", "verification-runner", "deployment"].every((profile) =>
        verification.profiles.includes(profile),
      ),
    "ops206.verification profiles are incomplete",
  );
  assert(verification.commandCount === 34, "ops206.verification command count is stale");
  assert(verification.pullRequestChecks === 4, "ops206.pullRequestChecks must be 4");
  assert(verification.stagingRun === "32133397317", "ops206.verification.stagingRun is stale");

  const focusedProof = ops206.focusedProof;
  assert(focusedProof?.toolchainTests === "106/106", "toolchain proof is incomplete");
  assert(
    focusedProof?.candidateHealthParityTests === "5/5",
    "candidate health/parity proof is incomplete",
  );
  assert(
    focusedProof?.blueGreenTopologyTests === "5/5",
    "blue/green topology proof is incomplete",
  );
  assert(focusedProof?.docsContract === "passed", "docs contract proof must pass");

  const residuals = evidence.residuals;
  assert(
    Array.isArray(residuals) && residuals.length === EXPECTED_RESIDUALS.size,
    "residual list is incomplete",
  );
  const seen = new Set();
  for (const residual of residuals) {
    assertIssue(residual?.issue, "residual.issue");
    assert(EXPECTED_RESIDUALS.has(residual.issue), `unexpected residual ${residual.issue}`);
    assert(!seen.has(residual.issue), `duplicate residual ${residual.issue}`);
    seen.add(residual.issue);
    assertIssue(residual.owner, `${residual.issue}.owner`);
    assertIssue(residual.targetRef, `${residual.issue}.targetRef`);
    for (const field of ["status", "promotionDecision", "evidence", "nextAction", "stopCondition"]) {
      assert(
        typeof residual[field] === "string" && residual[field].trim(),
        `${residual.issue}.${field} is required`,
      );
    }
    assertExistingRepositoryPath(root, residual.evidence, `${residual.issue}.evidence`);
  }
  assert(seen.size === EXPECTED_RESIDUALS.size, "some expected residuals are missing");

  const scope = evidence.scope;
  for (const field of [
    "runtimeChanged",
    "dependencyChanged",
    "archiveChanged",
    "harnessDbChanged",
    "stagingMutation",
    "productionPromotion",
  ]) {
    assert(scope?.[field] === false, `scope.${field} must remain false`);
  }
  assert(
    evidence.checklist?.completed === 80 && evidence.checklist?.total === 81,
    "checklist must remain 80/81",
  );
  assert(evidence.checklist?.phase10 === "open", "Phase 10 must remain open");
  assert(
    typeof evidence.nextAction === "string" &&
      evidence.nextAction.includes("candidate-start"),
    "next action must name candidate-start",
  );
  assert(
    typeof evidence.rollback === "string" && evidence.rollback.includes("squash revert"),
    "rollback must be recorded",
  );
  assertNoLocalPathOrIdentity(evidence);
  return {
    status: "passed",
    issue: evidence.issue,
    residualCount: residuals.length,
    sourceRevision: evidence.sourceRevision,
  };
}

export function main(argv = process.argv.slice(2), root = process.cwd()) {
  const inputIndex = argv.indexOf("--input");
  const input = inputIndex >= 0 ? argv[inputIndex + 1] : "docs/migrations/ops-207-master-plan-reconciliation.json";
  if (!input || input.startsWith("--")) fail("--input requires a path");
  const evidence = JSON.parse(readFileSync(path.resolve(root, input), "utf8"));
  const result = validateEvidence(evidence, root);
  console.log(`OPS207 MASTER PLAN PASS source=${result.sourceRevision} residuals=${result.residualCount}`);
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    process.exitCode = main();
  } catch (error) {
    console.error(`OPS207 MASTER PLAN FAIL: ${error.message}`);
    process.exitCode = Number.isInteger(error.code) ? error.code : 2;
  }
}
