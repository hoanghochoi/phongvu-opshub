#!/usr/bin/env node

import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const REVISION = /^[a-f0-9]{40}$/i;
const ISSUE = /^OPS-\d+$/;
const EXPECTED = new Set(["OPS-72", "OPS-190", "OPS-75", "OPS-78", "OPS-76", "OPS-77", "OPS-79"]);

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

export function validateEvidence(evidence, root = process.cwd()) {
  assert(evidence?.formatVersion === 1, "formatVersion must be 1");
  assert(evidence.issue === "OPS-198", "issue must be OPS-198");
  assertRevision(evidence.sourceRevision, "sourceRevision");
  assert(evidence.initiative === "OPS-64", "initiative must be OPS-64");

  const checkpoint = evidence.checkpoint;
  assertRevision(checkpoint?.originStaging, "checkpoint.originStaging");
  assertRevision(checkpoint?.originMain, "checkpoint.originMain");
  assert(checkpoint.promotionPerformed === false, "promotion must remain false");
  assert(checkpoint.worktreeCleanAtStart === true, "worktree start must be clean");

  const residuals = evidence.residuals;
  assert(Array.isArray(residuals) && residuals.length === EXPECTED.size, "residual list is incomplete");
  const seen = new Set();
  for (const residual of residuals) {
    assertIssue(residual?.issue, "residual.issue");
    assert(EXPECTED.has(residual.issue), `unexpected residual ${residual.issue}`);
    assert(!seen.has(residual.issue), `duplicate residual ${residual.issue}`);
    seen.add(residual.issue);
    assertIssue(residual.owner, `${residual.issue}.owner`);
    assertIssue(residual.targetRef, `${residual.issue}.targetRef`);
    for (const field of ["status", "promotionDecision", "evidence", "nextAction", "stopCondition"]) {
      assert(typeof residual[field] === "string" && residual[field].trim(), `${residual.issue}.${field} is required`);
    }
    const evidencePath = path.resolve(root, residual.evidence);
    assert(existsSync(evidencePath), `${residual.issue}.evidence does not exist: ${residual.evidence}`);
  }
  assert(seen.size === EXPECTED.size, "some expected residuals are missing");

  const scope = evidence.scope;
  for (const field of ["runtimeChanged", "dependencyChanged", "archiveChanged", "harnessDbChanged", "productionPromotion"]) {
    assert(scope?.[field] === false, `scope.${field} must remain false`);
  }
  assert(typeof evidence.rollback === "string" && evidence.rollback.includes("squash revert"), "rollback must be recorded");
  assertNoLocalPathOrIdentity(evidence);
  return { status: "passed", issue: evidence.issue, residualCount: residuals.length };
}

export function main(argv = process.argv.slice(2), root = process.cwd()) {
  const inputIndex = argv.indexOf("--input");
  const input = inputIndex >= 0 ? argv[inputIndex + 1] : "docs/migrations/ops-198-residual-gate-reconciliation.json";
  if (!input || input.startsWith("--")) fail("--input requires a path");
  const evidence = JSON.parse(readFileSync(path.resolve(root, input), "utf8"));
  const result = validateEvidence(evidence, root);
  console.log(`OPS198 RESIDUAL GATES PASS issue=${result.issue} residuals=${result.residualCount}`);
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    process.exitCode = main();
  } catch (error) {
    console.error(`OPS198 RESIDUAL GATES FAIL: ${error.message}`);
    process.exitCode = Number.isInteger(error.code) ? error.code : 2;
  }
}
