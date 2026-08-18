#!/usr/bin/env node

/**
 * Validate the repository-owned candidate health/Home parity preflight.
 *
 * This contract consumes sanitized, offline evidence only. It never starts a
 * candidate, calls Docker/Caddy/k6, changes traffic, runs migrations, or
 * authorizes a release. Live execution belongs to a later, operationally
 * approved OPS-78 slice.
 */

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
export const EVIDENCE_RELATIVE =
  "docs/migrations/ops-206-candidate-health-parity.json";

const SHA1 = /^[a-f0-9]{40}$/;
const SHA256 = /^[a-f0-9]{64}$/;
const IMAGE_DIGEST = /^sha256:[a-f0-9]{64}$/;
const SAFE_ID = /^[a-z0-9][a-z0-9._-]{0,63}$/;
const COLORS = new Set(["blue", "green"]);
export const HOME_RANGES = Object.freeze([1, 7, 30, 90]);
export const REQUIRED_SOURCE_PATHS = Object.freeze([
  "docs/decisions/0030-zero-downtime-staging-cutover-and-home-slo-proof.md",
  "deploy/staging/blue-green-topology.mjs",
  "deploy/home-server/Caddyfile.bluegreen.template",
  "scripts/load/opshub-home-phase1-contract.mjs",
  "scripts/load/opshub-home-phase1-http-proof.js",
  "scripts/load/opshub-staging-targets.mjs",
  "docs/migrations/ops-204-migration-home-preflight.json",
]);

function fail(message) {
  throw new Error(`OPS206_CANDIDATE_PREFLIGHT_INVALID:${message}`);
}

function requireCondition(condition, message) {
  if (!condition) fail(message);
}

function assertSha(value, label, pattern = SHA256) {
  requireCondition(
    typeof value === "string" && pattern.test(value),
    `${label} must be a lowercase digest`,
  );
}

function assertSafeId(value, label) {
  requireCondition(
    typeof value === "string" && SAFE_ID.test(value),
    `${label} must be a safe identifier`,
  );
}

function assertColor(value, label) {
  requireCondition(COLORS.has(value), `${label} must be blue or green`);
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

// Hash tracked text after normalizing checkout EOL so evidence is portable
// between Windows worktrees and LF-based CI checkouts.
export function textSha256(bytes) {
  const normalized = Buffer.from(bytes.toString("utf8").replace(/\r\n/g, "\n").replace(/\r/g, "\n"));
  return sha256(normalized);
}

function resolveInsideRoot(repositoryRoot, relativePath, label) {
  requireCondition(
    typeof relativePath === "string" &&
      relativePath.length > 0 &&
      !path.isAbsolute(relativePath) &&
      !relativePath.split(/[\\/]/).includes(".."),
    `${label} must be a repository-relative path`,
  );
  const absoluteRoot = path.resolve(repositoryRoot);
  const absolutePath = path.resolve(absoluteRoot, relativePath);
  const relative = path.relative(absoluteRoot, absolutePath);
  requireCondition(
    relative === "" ||
      (!path.isAbsolute(relative) && !relative.startsWith("..")),
    `${label} escapes repository root`,
  );
  return absolutePath;
}

function git(repositoryRoot, args) {
  try {
    return execFileSync("git", ["-C", repositoryRoot, ...args], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    }).trim();
  } catch (_) {
    fail(`git lookup failed: ${args.join(" ")}`);
  }
}

function assertSourceRevision(repositoryRoot, sourceRevision) {
  assertSha(sourceRevision, "sourceRevision", SHA1);
  git(repositoryRoot, ["cat-file", "-e", `${sourceRevision}^{commit}`]);
  const head = git(repositoryRoot, ["rev-parse", "HEAD"]);
  git(repositoryRoot, ["merge-base", "--is-ancestor", sourceRevision, head]);
  return head;
}

function assertSanitizedEvidence(evidence) {
  const serialized = JSON.stringify(evidence);
  const headerKey = ["authorization", "Header"].join("");
  requireCondition(
    !/[A-Za-z]:[\\/]|(?:^|[\\/])Users(?:[\\/]|$)/i.test(serialized),
    "evidence contains an absolute local path or username",
  );
  requireCondition(
    !/\b(?:Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+/i.test(serialized),
    "evidence contains an authorization credential",
  );
  requireCondition(
    !new RegExp(`\\b(?:password|secret|${headerKey})\\s*[:=]`, "i").test(serialized),
    "evidence contains a secret-bearing field",
  );
}

function validateReleaseIdentities(identities) {
  requireCondition(
    Array.isArray(identities) && identities.length === 2,
    "releaseIdentities must contain active and candidate",
  );
  const roles = new Set();
  const colors = new Set();
  const releases = new Set();
  const commits = new Set();
  for (const identity of identities) {
    requireCondition(
      identity && typeof identity === "object" && !Array.isArray(identity),
      "release identity must be an object",
    );
    requireCondition(
      ["active", "candidate"].includes(identity.role),
      `unsupported release role: ${identity.role}`,
    );
    requireCondition(!roles.has(identity.role), `duplicate release role: ${identity.role}`);
    roles.add(identity.role);
    assertColor(identity.color, `${identity.role}.color`);
    requireCondition(!colors.has(identity.color), "active and candidate colors must differ");
    colors.add(identity.color);
    assertSafeId(identity.releaseId, `${identity.role}.releaseId`);
    assertSha(identity.commitSha, `${identity.role}.commitSha`, SHA1);
    assertSha(identity.configDigest, `${identity.role}.configDigest`);
    requireCondition(IMAGE_DIGEST.test(identity.imageDigest), `${identity.role}.imageDigest is invalid`);
    assertSha(identity.artifactManifestSha256, `${identity.role}.artifactManifestSha256`);
    requireCondition(identity.source === "offline-fixture", `${identity.role}.source must be offline-fixture`);
    requireCondition(!releases.has(identity.releaseId), "release identities must be distinct");
    requireCondition(!commits.has(identity.commitSha), "release commit identities must be distinct");
    releases.add(identity.releaseId);
    commits.add(identity.commitSha);
  }
  for (const role of ["active", "candidate"]) {
    requireCondition(roles.has(role), `missing ${role} release identity`);
  }
}

function validateStatusGate(gate, label, expectedColor = null) {
  requireCondition(gate && typeof gate === "object" && !Array.isArray(gate), `${label} must be an object`);
  requireCondition(gate.status === "passed", `${label} must be passed`);
  requireCondition(gate.source === "offline-fixture", `${label}.source must be offline-fixture`);
  requireCondition(typeof gate.observedAtUtc === "string" && gate.observedAtUtc.endsWith("Z"), `${label}.observedAtUtc is required`);
  if (expectedColor) {
    assertColor(gate.color, `${label}.color`);
    requireCondition(gate.color === expectedColor, `${label}.color does not match release identity`);
  }
}

function validateHealthGate(gate, label, expectedColor) {
  validateStatusGate(gate, label, expectedColor);
  requireCondition(gate.httpStatus === 200, `${label}.httpStatus must be 200`);
  requireCondition(gate.service === "backend-nest", `${label}.service must be backend-nest`);
  requireCondition(gate.bodyStatus === "ok", `${label}.bodyStatus must be ok`);
}

function validateAuthGate(gate, candidateColor) {
  validateStatusGate(gate, "authenticatedGate", candidateColor);
  requireCondition(gate.bootstrapStatus === 200, "authenticatedGate.bootstrapStatus must be 200");
  requireCondition(gate.meStatus === 200, "authenticatedGate.meStatus must be 200");
  requireCondition(gate.credentialMaterial === "omitted", "authenticatedGate.credentialMaterial must be omitted");
}

function validateHomeParityGate(gate) {
  validateStatusGate(gate, "homeParityGate");
  requireCondition(Array.isArray(gate.ranges), "homeParityGate.ranges must be an array");
  requireCondition(gate.ranges.length === HOME_RANGES.length, "homeParityGate must cover 1/7/30/90-day ranges");
  const seen = new Set();
  for (const range of gate.ranges) {
    requireCondition(Number.isInteger(range?.days) && HOME_RANGES.includes(range.days), "homeParityGate range is invalid");
    requireCondition(!seen.has(range.days), `duplicate Home parity range: ${range.days}`);
    seen.add(range.days);
    requireCondition(range.legacyStatus === 200, `Home legacy ${range.days}d status must be 200`);
    requireCondition(range.dailyStatus === 200, `Home daily ${range.days}d status must be 200`);
    requireCondition(range.contractValid === true, `Home ${range.days}d contract must pass`);
    requireCondition(range.aggregateParity === true, `Home ${range.days}d aggregate parity must pass`);
  }
  requireCondition(seen.size === HOME_RANGES.length, "homeParityGate has missing ranges");
}

function validateAppVersionGate(gate, identities) {
  validateStatusGate(gate, "appVersionGate");
  for (const role of ["active", "candidate"]) {
    const observed = gate[role];
    const identity = identities.find((item) => item.role === role);
    requireCondition(observed && typeof observed === "object", `appVersionGate.${role} is required`);
    assertSafeId(observed.releaseId, `appVersionGate.${role}.releaseId`);
    assertSafeId(observed.buildId, `appVersionGate.${role}.buildId`);
    requireCondition(observed.releaseId === identity.releaseId, `appVersionGate.${role}.releaseId mismatch`);
    requireCondition(observed.buildId === identity.releaseId, `appVersionGate.${role}.buildId mismatch`);
  }
}

function validateSourceFiles(sourceFiles, repositoryRoot) {
  requireCondition(Array.isArray(sourceFiles), "sourceFiles must be an array");
  const entries = new Map();
  for (const entry of sourceFiles) {
    requireCondition(entry && typeof entry === "object" && !Array.isArray(entry), "source file entry must be an object");
    const absolute = resolveInsideRoot(repositoryRoot, entry.path, "sourceFiles.path");
    assertSha(entry.sha256, `sourceFiles.${entry.path}.sha256`);
    requireCondition(!entries.has(entry.path), `duplicate source file: ${entry.path}`);
    requireCondition(existsSync(absolute), `source file is missing: ${entry.path}`);
    requireCondition(textSha256(readFileSync(absolute)) === entry.sha256, `source file digest mismatch: ${entry.path}`);
    entries.set(entry.path, entry.sha256);
  }
  for (const required of REQUIRED_SOURCE_PATHS) {
    requireCondition(entries.has(required), `required source file is not hash-bound: ${required}`);
  }
  requireCondition(entries.size === REQUIRED_SOURCE_PATHS.length, "sourceFiles contains an unexpected path");
}

function validateSafety(safety) {
  requireCondition(safety && typeof safety === "object" && !Array.isArray(safety), "safety must be an object");
  for (const field of [
    "candidateStartPerformed",
    "trafficSwitchAllowed",
    "trafficSwitchPerformed",
    "caddyReloadPerformed",
    "migrationPerformed",
    "websocketDrainObserved",
    "loadRunPerformed",
    "productionPromotion",
    "databaseTouched",
  ]) {
    requireCondition(safety[field] === false, `${field} must remain false`);
  }
  requireCondition(safety.promotionEligible === false, "promotionEligible must remain false");
}

export function validateEvidence(evidence, { repositoryRoot = ROOT } = {}) {
  requireCondition(evidence && typeof evidence === "object" && !Array.isArray(evidence), "evidence must be an object");
  requireCondition(evidence.formatVersion === 1, "formatVersion must be 1");
  requireCondition(evidence.issue === "OPS-206", "issue must be OPS-206");
  requireCondition(evidence.parentIssue === "OPS-78", "parentIssue must be OPS-78");
  requireCondition(evidence.mode === "offline-preflight", "mode must be offline-preflight");
  requireCondition(evidence.status === "passed", "status must be passed");
  assertSourceRevision(repositoryRoot, evidence.sourceRevision);
  validateReleaseIdentities(evidence.releaseIdentities);
  const active = evidence.releaseIdentities.find((item) => item.role === "active");
  const candidate = evidence.releaseIdentities.find((item) => item.role === "candidate");
  validateHealthGate(evidence.gates?.activeColorHealth, "activeColorHealth", active.color);
  validateHealthGate(evidence.gates?.candidateHealth, "candidateHealth", candidate.color);
  validateStatusGate(evidence.gates?.directOriginHealth, "directOriginHealth", candidate.color);
  requireCondition(evidence.gates.directOriginHealth.httpStatus === 200, "directOriginHealth.httpStatus must be 200");
  validateAuthGate(evidence.gates?.authenticated, candidate.color);
  validateHomeParityGate(evidence.gates?.homeParity);
  validateAppVersionGate(evidence.gates?.appVersionIdentity, evidence.releaseIdentities);
  validateSafety(evidence.safety);
  validateSourceFiles(evidence.sourceFiles, repositoryRoot);
  assertSanitizedEvidence(evidence);
  requireCondition(typeof evidence.nextAction === "string" && evidence.nextAction.includes("OPS-78"), "nextAction must name OPS-78");
  return {
    status: "passed",
    issue: "OPS-206",
    mode: "offline-preflight",
    sourceRevision: evidence.sourceRevision,
    releaseCount: evidence.releaseIdentities.length,
    homeRanges: HOME_RANGES.length,
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
      console.log("Usage: node deploy/staging/candidate-health-parity.mjs [--root <repo>] [--input <evidence>] [--json]");
      process.exit(0);
    }
    const root = path.resolve(options.root);
    const inputPath = path.isAbsolute(options.input)
      ? options.input
      : resolveInsideRoot(root, options.input, "input");
    const evidence = JSON.parse(await readFile(inputPath, "utf8"));
    const result = validateEvidence(evidence, { repositoryRoot: root });
    if (options.json) console.log(JSON.stringify(result));
    else console.log(`OPS-206 CANDIDATE PREFLIGHT PASS source=${result.sourceRevision} releases=${result.releaseCount} homeRanges=${result.homeRanges} promotionEligible=false`);
    process.exitCode = 0;
  } catch (error) {
    console.error(error.message);
    process.exitCode = 2;
  }
}
