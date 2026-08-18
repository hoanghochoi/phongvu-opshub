#!/usr/bin/env node

/**
 * Validate the non-live OPS-78 migration/Home proof preflight.
 *
 * This contract deliberately accepts only evidence that is safe to consume
 * before a staging mutation. It does not run Prisma, Docker, Caddy, WebSocket
 * or k6 commands and it never authorizes traffic or production promotion.
 */

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const EVIDENCE_RELATIVE =
  "docs/migrations/ops-204-migration-home-preflight.json";
const SHA256 = /^[a-f0-9]{64}$/;
const SHA1 = /^[a-f0-9]{40}$/;
const SAFE_ID = /^[a-z0-9][a-z0-9._-]{0,63}$/;
const IMAGE_DIGEST = /^sha256:[a-f0-9]{64}$/;
const RELATIVE_PATH = /^(?!\/)(?!.*(?:^|\/)\.\.(?:\/|$))[A-Za-z0-9._/-]+$/;
const HOME_RANGES = Object.freeze([1, 7, 30, 90]);
const REQUIRED_SOURCE_PATHS = Object.freeze([
  "docs/decisions/0030-zero-downtime-staging-cutover-and-home-slo-proof.md",
  "deploy/staging/load-proof-runbook.md",
  "scripts/load/opshub-home-phase1-contract.mjs",
  "scripts/load/opshub-home-phase1-http-proof.js",
  "scripts/load/opshub-staging-home-profile.json",
  "deploy/staging/blue-green-topology.mjs",
  "docs/migrations/ops-201-blue-green-topology-evidence.json",
]);

function fail(message) {
  throw new Error(`OPS204_PREFLIGHT_INVALID:${message}`);
}

function requireCondition(condition, message) {
  if (!condition) fail(message);
}

function assertSha(value, label, pattern = SHA256) {
  requireCondition(typeof value === "string" && pattern.test(value), `${label} must be a lowercase digest`);
}

function assertSafeId(value, label) {
  requireCondition(typeof value === "string" && SAFE_ID.test(value), `${label} must be a safe identifier`);
}

function assertRelativePath(value, label) {
  requireCondition(typeof value === "string" && RELATIVE_PATH.test(value), `${label} must be a safe relative path`);
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

// Migration SQL is tracked text. Git may materialize it with CRLF on Windows
// or LF in CI/Linux; bind the evidence to the normalized repository bytes so
// the same proof does not flap across worktrees solely because of checkout EOL.
export function textSha256(bytes) {
  const normalized = Buffer.from(bytes.toString("utf8").replace(/\r\n/g, "\n").replace(/\r/g, "\n"));
  return sha256(normalized);
}

function canonicalJson(value) {
  return JSON.stringify(value);
}

function git(root, args) {
  try {
    return execFileSync("git", ["-C", root, ...args], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    }).trim();
  } catch (error) {
    fail(`git lookup failed: ${args.join(" ")}`);
  }
}

function resolveInsideRoot(root, relativePath, label) {
  assertRelativePath(relativePath, label);
  const absoluteRoot = path.resolve(root);
  const absolutePath = path.resolve(absoluteRoot, relativePath);
  const relative = path.relative(absoluteRoot, absolutePath);
  requireCondition(
    relative === "" || (!path.isAbsolute(relative) && !relative.startsWith("..")),
    `${label} escapes repository root`,
  );
  return absolutePath;
}

function validateReleaseIdentities(identities) {
  requireCondition(Array.isArray(identities) && identities.length === 3, "releaseIdentities must contain previous/active/candidate");
  const roles = new Set();
  const releaseIds = new Set();
  const commitShas = new Set();
  for (const identity of identities) {
    requireCondition(identity && typeof identity === "object" && !Array.isArray(identity), "release identity must be an object");
    requireCondition(["previous", "active", "candidate"].includes(identity.role), `unsupported release role: ${identity.role}`);
    requireCondition(!roles.has(identity.role), `duplicate release role: ${identity.role}`);
    roles.add(identity.role);
    assertSafeId(identity.releaseId, `${identity.role}.releaseId`);
    assertSha(identity.commitSha, `${identity.role}.commitSha`, SHA1);
    assertSha(identity.configDigest, `${identity.role}.configDigest`);
    assertSha(identity.artifactManifestSha256, `${identity.role}.artifactManifestSha256`);
    requireCondition(Array.isArray(identity.imageDigests) && identity.imageDigests.length > 0, `${identity.role}.imageDigests must be non-empty`);
    for (const digest of identity.imageDigests) {
      requireCondition(typeof digest === "string" && IMAGE_DIGEST.test(digest), `${identity.role}.imageDigests contains an invalid digest`);
    }
    requireCondition(!releaseIds.has(identity.releaseId), "release identities must be distinct");
    requireCondition(!commitShas.has(identity.commitSha), "release commit identities must be distinct");
    releaseIds.add(identity.releaseId);
    commitShas.add(identity.commitSha);
    requireCondition(identity.source === "offline-fixture", `${identity.role}.source must be offline-fixture for this slice`);
  }
  for (const role of ["previous", "active", "candidate"]) {
    requireCondition(roles.has(role), `missing ${role} release identity`);
  }
}

function validateMigration(migration, repositoryRoot) {
  requireCondition(migration && typeof migration === "object" && !Array.isArray(migration), "migration must be an object");
  requireCondition(migration.mode === "expand-contract", "migration mode must be expand-contract");
  requireCondition(migration.executionPerformed === false, "migration execution is out of scope");
  requireCondition(migration.databaseDowngradeAllowed === false, "database downgrade must remain disabled");
  requireCondition(migration.inventoryRoot === "backend-nest/prisma/migrations", "migration inventory root is not repository-owned");
  requireCondition(Array.isArray(migration.inventory) && migration.inventory.length > 0, "migration inventory must be non-empty");
  assertSha(migration.inventorySha256, "migration.inventorySha256");
  requireCondition(
    sha256(canonicalJson(migration.inventory)) === migration.inventorySha256,
    "migration inventory digest does not match its contents",
  );
  const ids = new Set();
  for (const item of migration.inventory) {
    requireCondition(item && typeof item === "object" && !Array.isArray(item), "migration inventory item must be an object");
    assertSafeId(item.id, "migration.inventory.id");
    requireCondition(!ids.has(item.id), `duplicate migration inventory id: ${item.id}`);
    ids.add(item.id);
    requireCondition(["expand", "contract"].includes(item.phase), `unsupported migration phase: ${item.phase}`);
    requireCondition(item.destructive === false, `destructive migration is not compatible: ${item.id}`);
    requireCondition(item.oneWay === false, `one-way migration is not compatible: ${item.id}`);
    requireCondition(item.previousColorReadable === true, `previous color cannot read migration contract: ${item.id}`);
    requireCondition(item.candidateColorReadable === true, `candidate color cannot read migration contract: ${item.id}`);
    requireCondition(item.rollbackSafe === true, `migration is not rollback-safe: ${item.id}`);
    const migrationPath = resolveInsideRoot(repositoryRoot, item.path, "migration.inventory.path");
    const rollbackPath = resolveInsideRoot(repositoryRoot, item.rollbackPath, "migration.inventory.rollbackPath");
    requireCondition(item.path.startsWith(`${migration.inventoryRoot}/`), `migration path is outside the inventory root: ${item.id}`);
    requireCondition(item.rollbackPath.startsWith(`${migration.inventoryRoot}/`), `rollback path is outside the inventory root: ${item.id}`);
    requireCondition(existsSync(migrationPath), `migration SQL is missing: ${item.path}`);
    requireCondition(existsSync(rollbackPath), `migration rollback SQL is missing: ${item.rollbackPath}`);
    assertSha(item.sqlSha256, `${item.id}.sqlSha256`);
    assertSha(item.rollbackSha256, `${item.id}.rollbackSha256`);
    requireCondition(textSha256(readFileSync(migrationPath)) === item.sqlSha256, `migration SQL digest mismatch: ${item.id}`);
    requireCondition(textSha256(readFileSync(rollbackPath)) === item.rollbackSha256, `migration rollback digest mismatch: ${item.id}`);
    const sql = readFileSync(migrationPath, "utf8");
    requireCondition(!/\b(?:DROP\s+(?:TABLE|COLUMN|DATABASE|SCHEMA)|TRUNCATE\b)/i.test(sql), `destructive SQL is not compatible: ${item.id}`);
  }
  requireCondition(migration.contractPlan?.status === "deferred", "contract plan must remain deferred");
  requireCondition(migration.contractPlan?.requiresInactiveColor === true, "contract plan must wait for the inactive color");
  requireCondition(migration.contractPlan?.executionPerformed === false, "contract plan execution is out of scope");
}

function validateRollback(rollback, identities) {
  requireCondition(rollback && typeof rollback === "object" && !Array.isArray(rollback), "rollback must be an object");
  const previous = identities.find((identity) => identity.role === "previous");
  requireCondition(previous, "previous release identity is required for rollback");
  requireCondition(rollback.targetReleaseId === previous.releaseId, "rollback target must be the previous release");
  requireCondition(rollback.releasePointerRestorable === true, "release pointer must be restorable");
  requireCondition(rollback.oldArtifactsRetained === true, "old artifacts must remain retained during rollback window");
  requireCondition(rollback.databaseDowngradeAttempted === false, "rollback must not downgrade the database");
  requireCondition(Number.isInteger(rollback.observationWindowSeconds) && rollback.observationWindowSeconds > 0, "rollback observation window must be positive");
}

function validateHomeProof(homeProof) {
  requireCondition(homeProof && typeof homeProof === "object" && !Array.isArray(homeProof), "homeProof must be an object");
  assertSha(homeProof.contractSha256, "homeProof.contractSha256");
  assertSha(homeProof.httpProofSha256, "homeProof.httpProofSha256");
  assertSha(homeProof.profileSha256, "homeProof.profileSha256");
  assertSha(homeProof.runbookSha256, "homeProof.runbookSha256");
  requireCondition(homeProof.routeDays?.join(",") === HOME_RANGES.join(","), "Home proof must cover 1/7/30/90-day ranges");
  requireCondition(homeProof.pairedVariants === true, "Home proof must compare legacy and daily-series variants");
  requireCondition(homeProof.syntheticUsers === 60, "Home staging proof must use 60 synthetic users");
  requireCondition(homeProof.httpVus === 250, "Home HTTP proof VUs must remain 250");
  requireCondition(homeProof.httpRequests === 2000, "Home HTTP proof requests must remain 2,000");
  requireCondition(homeProof.targetRps === 100, "Home staging target RPS must remain 100");
  requireCondition(homeProof.targetSockets === 60, "Home staging target sockets must remain 60");
  requireCondition(homeProof.latencyMs?.p50 === 250, "Home p50 threshold drifted");
  requireCondition(homeProof.latencyMs?.p95 === 500, "Home p95 threshold drifted");
  requireCondition(homeProof.latencyMs?.p99 === 1000, "Home p99 threshold drifted");
  requireCondition(homeProof.latencyMs?.max === 3000, "Home max latency threshold drifted");
  requireCondition(homeProof.unexpected429 === 0, "unexpected 429 must fail the proof");
  requireCondition(homeProof.transportOr5xx === 0, "transport/5xx errors must fail the proof");
  requireCondition(homeProof.cleanup === "verify-empty", "Home proof must require verify-empty cleanup");
  requireCondition(homeProof.runPerformed === false, "load execution is out of scope for this slice");
}

function validateSafety(safety) {
  requireCondition(safety && typeof safety === "object" && !Array.isArray(safety), "safety must be an object");
  for (const field of [
    "stagingMutationPerformed",
    "trafficSwitchPerformed",
    "migrationPerformed",
    "loadRunPerformed",
    "productionPromotion",
    "databaseTouched",
    "caddyReloadPerformed",
    "websocketDrainObserved",
  ]) {
    requireCondition(safety[field] === false, `${field} must remain false in the offline preflight`);
  }
  requireCondition(safety.trafficSwitchAllowed === false, "traffic switch must remain disallowed");
  requireCondition(safety.promotionEligible === false, "offline preflight cannot authorize promotion");
  requireCondition(safety.topologyOwner === "OPS-201", "OPS-201 must remain the topology owner");
}

function validateSourceFiles(sourceFiles, repositoryRoot) {
  requireCondition(Array.isArray(sourceFiles), "sourceFiles must be an array");
  const entries = new Map();
  for (const entry of sourceFiles) {
    requireCondition(entry && typeof entry === "object" && !Array.isArray(entry), "source file entry must be an object");
    assertRelativePath(entry.path, "sourceFiles.path");
    assertSha(entry.sha256, `sourceFiles.${entry.path}.sha256`);
    requireCondition(!entries.has(entry.path), `duplicate source file: ${entry.path}`);
    entries.set(entry.path, entry.sha256);
    const absolute = resolveInsideRoot(repositoryRoot, entry.path, "sourceFiles.path");
    requireCondition(existsSync(absolute), `source file is missing: ${entry.path}`);
    const actual = sha256(readFileSync(absolute));
    requireCondition(actual === entry.sha256, `source file digest mismatch: ${entry.path}`);
  }
  for (const required of REQUIRED_SOURCE_PATHS) {
    requireCondition(entries.has(required), `required source file is not hash-bound: ${required}`);
  }
  requireCondition(entries.size === REQUIRED_SOURCE_PATHS.length, "sourceFiles contains an unexpected path");
  return entries;
}

function validateTopologyEvidence(repositoryRoot, sourceDigests, baseRevision) {
  const topologyPath = "docs/migrations/ops-201-blue-green-topology-evidence.json";
  const absolute = resolveInsideRoot(repositoryRoot, topologyPath, "topology evidence path");
  const topology = JSON.parse(readFileSync(absolute, "utf8"));
  requireCondition(sourceDigests.get(topologyPath) === sha256(readFileSync(absolute)), "topology evidence digest is stale");
  requireCondition(topology.issue === "OPS-201", "topology evidence issue must be OPS-201");
  requireCondition(topology.scope === "opt-in no-traffic-mutation blue-green topology harness", "unexpected topology evidence scope");
  requireCondition(topology.safety?.trafficSwitchAllowed === false, "topology evidence allows traffic switching");
  requireCondition(topology.safety?.trafficSwitchPerformed === false, "topology evidence reports traffic switching");
  requireCondition(topology.safety?.migrationAllowed === false, "topology evidence allows migration");
  requireCondition(topology.safety?.migrationPerformed === false, "topology evidence reports migration");
  requireCondition(topology.topology?.defaultSinglePlanePreserved === true, "topology evidence does not preserve the default plane");
  assertSha(topology.mergeCommit, "topology.mergeCommit", SHA1);
  try {
    git(repositoryRoot, ["cat-file", "-e", `${baseRevision}^{commit}`]);
    git(repositoryRoot, ["cat-file", "-e", `${topology.mergeCommit}^{commit}`]);
    git(repositoryRoot, ["merge-base", "--is-ancestor", topology.mergeCommit, baseRevision]);
  } catch (_) {
    fail("OPS-201 topology merge is not an ancestor of the preflight base revision");
  }
}

export function validateEvidence(evidence, { repositoryRoot = ROOT } = {}) {
  requireCondition(evidence && typeof evidence === "object" && !Array.isArray(evidence), "evidence must be an object");
  requireCondition(evidence.formatVersion === 1, "formatVersion must be 1");
  requireCondition(evidence.issue === "OPS-204", "issue must be OPS-204");
  requireCondition(evidence.parentIssue === "OPS-78", "parentIssue must be OPS-78");
  requireCondition(evidence.mode === "offline-preflight", "mode must be offline-preflight");
  requireCondition(evidence.status === "passed", "status must be passed");
  assertSha(evidence.baseRevision, "baseRevision", SHA1);
  validateReleaseIdentities(evidence.releaseIdentities);
  validateMigration(evidence.migration, repositoryRoot);
  validateRollback(evidence.rollback, evidence.releaseIdentities);
  validateHomeProof(evidence.homeProof);
  validateSafety(evidence.safety);
  const sourceDigests = validateSourceFiles(evidence.sourceFiles, repositoryRoot);
  validateTopologyEvidence(repositoryRoot, sourceDigests, evidence.baseRevision);
  const homeSourceBindings = [
    ["scripts/load/opshub-home-phase1-contract.mjs", evidence.homeProof.contractSha256],
    ["scripts/load/opshub-home-phase1-http-proof.js", evidence.homeProof.httpProofSha256],
    ["scripts/load/opshub-staging-home-profile.json", evidence.homeProof.profileSha256],
    ["deploy/staging/load-proof-runbook.md", evidence.homeProof.runbookSha256],
  ];
  for (const [sourcePath, digest] of homeSourceBindings) {
    requireCondition(sourceDigests.get(sourcePath) === digest, `Home proof digest binding mismatch: ${sourcePath}`);
  }
  return {
    status: "passed",
    issue: "OPS-204",
    mode: "offline-preflight",
    sourceCount: evidence.sourceFiles.length,
    releaseCount: evidence.releaseIdentities.length,
    migrationCount: evidence.migration.inventory.length,
    promotionEligible: false,
  };
}

function parseArgs(argv) {
  const options = { root: ROOT, input: EVIDENCE_RELATIVE, json: false };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--root" || token === "--input") {
      const value = argv[++index];
      if (!value || value.startsWith("--")) fail(`${token} requires a value`);
      options[token.slice(2)] = value;
    } else if (token === "--json") {
      options.json = true;
    } else if (token === "--help" || token === "-h") {
      options.help = true;
    } else {
      fail(`unknown argument: ${token}`);
    }
  }
  return options;
}

const invokedAsScript =
  process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);

if (invokedAsScript) {
  try {
    const options = parseArgs(process.argv.slice(2));
    if (options.help) {
      console.log("Usage: node scripts/verify-ops204-preflight.mjs [--root <repo>] [--input <evidence>] [--json]");
      process.exit(0);
    }
    const root = path.resolve(options.root);
    const inputPath = path.isAbsolute(options.input)
      ? options.input
      : resolveInsideRoot(root, options.input, "input");
    const evidence = JSON.parse(await readFile(inputPath, "utf8"));
    const result = validateEvidence(evidence, { repositoryRoot: root });
    if (options.json) {
      console.log(JSON.stringify(result));
    } else {
      console.log(`OPS-204 PREFLIGHT PASS sources=${result.sourceCount} releases=${result.releaseCount} migrations=${result.migrationCount} promotionEligible=false`);
    }
    process.exitCode = 0;
  } catch (error) {
    console.error(error.message);
    process.exitCode = 2;
  }
}
