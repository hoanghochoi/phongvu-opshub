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
  assert(REVISION.test(String(value || "")), `${label} must be a 40-character Git revision`);
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
  assert(typeof relativePath === "string" && !path.isAbsolute(relativePath), `${label} must be repository-relative`);
  const absolute = path.resolve(root, relativePath);
  const relative = path.relative(root, absolute);
  assert(!path.isAbsolute(relative) && !relative.startsWith(".."), `${label} escapes repository root`);
  assert(existsSync(absolute), `${label} does not exist: ${relativePath}`);
}

export function validateEvidence(evidence, root = process.cwd()) {
  assert(evidence?.formatVersion === 1, "formatVersion must be 1");
  assert(evidence.issue === "OPS-205", "issue must be OPS-205");
  assert(evidence.initiative === "OPS-64", "initiative must be OPS-64");
  assertRevision(evidence.sourceRevision, "sourceRevision");
  assertRevision(evidence.previousRevision, "previousRevision");
  assertRevision(evidence.originMain, "originMain");
  assert(evidence.promotionPerformed === false, "promotion must remain false");

  const ops204 = evidence.ops204;
  assert(ops204?.issue === "OPS-204", "ops204.issue must be OPS-204");
  assert(ops204.pullRequest === 329, "ops204.pullRequest must be 329");
  for (const field of ["implementationRevision", "mergeSha"]) {
    assertRevision(ops204[field], `ops204.${field}`);
  }
  assert(ops204.implementationRevision === "a2585f3b1477e72268af1eba93a7f4cbd31fe5ff", "ops204.implementationRevision is stale");
  assert(ops204.mergeSha === "516e246ad10694286094a73c436b76c59b1f0011", "ops204.mergeSha is stale");
  assert(ops204.stagingDeployRun === "32127936496", "ops204.stagingDeployRun is stale");
  for (const field of ["stagingDeployResult", "lifecycleFinish", "worktreeCleanup", "remoteBranchCleanup"]) {
    assert(ops204[field] === "pass", `ops204.${field} must be pass`);
  }
  assertExistingRepositoryPath(root, ops204.evidence, "ops204.evidence");
  assert(ops204.productionPromotion === false, "ops204.productionPromotion must remain false");

  const verification = ops204.verification;
  assert(verification?.status === "passed", "ops204.verification.status must be passed");
  assert(verification?.stale === false, "ops204.verification.stale must be false");
  assert(Array.isArray(verification.profiles) && verification.profiles.includes("harness"), "verification profiles are incomplete");
  assert(verification.commandCount === 26, "verification command count is stale");
  assert(verification.pullRequestChecks === 4, "pull request check count is stale");

  const residuals = evidence.residuals;
  assert(Array.isArray(residuals) && residuals.length === EXPECTED_RESIDUALS.size, "residual list is incomplete");
  const seen = new Set();
  for (const residual of residuals) {
    assertIssue(residual?.issue, "residual.issue");
    assert(EXPECTED_RESIDUALS.has(residual.issue), `unexpected residual ${residual.issue}`);
    assert(!seen.has(residual.issue), `duplicate residual ${residual.issue}`);
    seen.add(residual.issue);
    assertIssue(residual.owner, `${residual.issue}.owner`);
    assertIssue(residual.targetRef, `${residual.issue}.targetRef`);
    for (const field of ["status", "promotionDecision", "evidence", "nextAction", "stopCondition"]) {
      assert(typeof residual[field] === "string" && residual[field].trim(), `${residual.issue}.${field} is required`);
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
  assert(evidence.checklist?.completed === 80 && evidence.checklist?.total === 81, "checklist must remain 80/81");
  assert(evidence.checklist?.phase10 === "open", "Phase 10 must remain open");
  assert(typeof evidence.nextAction === "string" && evidence.nextAction.includes("candidate health/parity"), "next action must name candidate health/parity");
  assert(typeof evidence.rollback === "string" && evidence.rollback.includes("squash revert"), "rollback must be recorded");
  assertNoLocalPathOrIdentity(evidence);
  return { status: "passed", issue: evidence.issue, residualCount: residuals.length, sourceRevision: evidence.sourceRevision };
}

export function main(argv = process.argv.slice(2), root = process.cwd()) {
  const inputIndex = argv.indexOf("--input");
  const input = inputIndex >= 0 ? argv[inputIndex + 1] : "docs/migrations/ops-205-master-plan-reconciliation.json";
  if (!input || input.startsWith("--")) fail("--input requires a path");
  const evidence = JSON.parse(readFileSync(path.resolve(root, input), "utf8"));
  const result = validateEvidence(evidence, root);
  console.log(`OPS205 MASTER PLAN PASS source=${result.sourceRevision} residuals=${result.residualCount}`);
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    process.exitCode = main();
  } catch (error) {
    console.error(`OPS205 MASTER PLAN FAIL: ${error.message}`);
    process.exitCode = Number.isInteger(error.code) ? error.code : 2;
  }
}
