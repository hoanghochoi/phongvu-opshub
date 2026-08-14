#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const DEFAULT_ARTIFACT = 'docs/migrations/ops-72-live-shadow-evidence.json';
const SHA1_RE = /^[0-9a-f]{40}$/i;
const SHA256_RE = /^[0-9a-f]{64}$/i;

export class LiveEvidenceError extends Error {}

function assert(condition, message) {
  if (!condition) throw new LiveEvidenceError(message);
}

function assertSha(value, label, pattern = SHA1_RE) {
  assert(typeof value === 'string' && pattern.test(value), `${label} must be a valid digest`);
}

function assertIso(value, label) {
  assert(typeof value === 'string' && !Number.isNaN(Date.parse(value)), `${label} must be an ISO timestamp`);
}

function assertStringArray(value, label) {
  assert(Array.isArray(value) && value.every((item) => typeof item === 'string'), `${label} must be a string array`);
}

function validateTelemetry(telemetry, label) {
  assert(telemetry && typeof telemetry === 'object', `${label} must be an object`);
  assert(telemetry.schemaVersion === 2, `${label}.schemaVersion must be 2`);
  assert(typeof telemetry.cohortId === 'string' && /^[A-Za-z0-9._-]+$/.test(telemetry.cohortId), `${label}.cohortId is invalid`);
  assertIso(telemetry.queuedAtUtc, `${label}.queuedAtUtc`);
  assertIso(telemetry.startedAtUtc, `${label}.startedAtUtc`);
  assertIso(telemetry.completedAtUtc, `${label}.completedAtUtc`);
  for (const key of ['queueDurationMs', 'executionDurationMs', 'retryCount', 'autoRetryCount', 'fullRetryCount']) {
    assert(Number.isInteger(telemetry[key]) && telemetry[key] >= 0, `${label}.${key} is invalid`);
  }
  if (telemetry.firstActionableFailure !== null) {
    const failure = telemetry.firstActionableFailure;
    assert(failure && typeof failure === 'object', `${label}.firstActionableFailure is invalid`);
    assert(typeof failure.category === 'string' && failure.category.length > 0, `${label}.firstActionableFailure.category is invalid`);
    assert(Number.isInteger(failure.exitCode), `${label}.firstActionableFailure.exitCode is invalid`);
    assertIso(failure.observedAtUtc, `${label}.firstActionableFailure.observedAtUtc`);
    assert(Number.isInteger(failure.elapsedMs) && failure.elapsedMs >= 0, `${label}.firstActionableFailure.elapsedMs is invalid`);
  }
}

function validatePass(observation, index) {
  const label = `observations[${index}]`;
  assert(observation && typeof observation === 'object', `${label} must be an object`);
  assert(Number.isInteger(observation.pullRequest) && observation.pullRequest > 0, `${label}.pullRequest is invalid`);
  assert(Number.isInteger(observation.runId) && observation.runId > 0, `${label}.runId is invalid`);
  assertSha(observation.prHeadSha, `${label}.prHeadSha`);
  assertSha(observation.reportedHeadSha, `${label}.reportedHeadSha`);
  assertSha(observation.baseSha, `${label}.baseSha`);
  assertSha(observation.artifactSha256, `${label}.artifactSha256`, SHA256_RE);
  assert(observation.rawArtifactFile === 'verify-task-shadow.json', `${label}.rawArtifactFile is not allowed`);
  assert(observation.status === 'passed' && observation.classification === 'shadow-observation', `${label} is not a pass observation`);
  assert(Number.isInteger(observation.changedPathCount) && observation.changedPathCount >= 0, `${label}.changedPathCount is invalid`);
  assertStringArray(observation.selectedProfiles, `${label}.selectedProfiles`);
  assertStringArray(observation.fullProfiles, `${label}.fullProfiles`);
  assert(observation.selectedProfiles.every((id) => observation.fullProfiles.includes(id)), `${label} selected profile is absent from full profiles`);
  assert(observation.autoExitCode === 0 && observation.fullExitCode === 0, `${label} exit codes must be zero`);
  assert(observation.blockingChecksUnchanged === true, `${label}.blockingChecksUnchanged must be true`);
  assert(observation.stale === false, `${label}.stale must be false`);
  assert(Array.isArray(observation.unmatchedPaths) && observation.unmatchedPaths.length === 0, `${label}.unmatchedPaths must be empty`);
  assert(observation.reruns === 0, `${label}.reruns must be zero`);
  assert(observation.humanIntervention === false, `${label}.humanIntervention must be false`);
  assert(observation.falsePositive === null && observation.falseNegative === null, `${label} false-positive/negative values must be null`);
  assert(Number.isInteger(observation.shadowDurationMs) && observation.shadowDurationMs >= 0, `${label}.shadowDurationMs is invalid`);
  assert(observation.run && typeof observation.run === 'object', `${label}.run is required`);
  assertIso(observation.run.createdAt, `${label}.run.createdAt`);
  assertIso(observation.run.startedAt, `${label}.run.startedAt`);
  assertIso(observation.run.completedAt, `${label}.run.completedAt`);
  assert(Number.isInteger(observation.run.githubDurationMs) && observation.run.githubDurationMs >= 0, `${label}.run.githubDurationMs is invalid`);
  if (observation.telemetry !== undefined) validateTelemetry(observation.telemetry, `${label}.telemetry`);
}

function validateExcluded(observation) {
  assert(observation && typeof observation === 'object', 'excluded observation must be an object');
  assert(Number.isInteger(observation.pullRequest) && observation.pullRequest > 0, 'excluded pullRequest is invalid');
  assert(Number.isInteger(observation.runId) && observation.runId > 0, 'excluded runId is invalid');
  assertSha(observation.prHeadSha, 'excluded prHeadSha');
  assertSha(observation.reportedHeadSha, 'excluded reportedHeadSha');
  assertSha(observation.baseSha, 'excluded baseSha');
  assertSha(observation.artifactSha256, 'excluded artifactSha256', SHA256_RE);
  assert(observation.rawArtifactFile === 'verify-task-shadow.json', 'excluded rawArtifactFile is not allowed');
  assert(observation.status === 'failed' && observation.classification === 'contract-failure', 'excluded observation must be a contract failure');
  assert(observation.reasonCode === 'unmatched-path-profile', 'excluded reasonCode is invalid');
  assert(Array.isArray(observation.unmatchedPaths) && observation.unmatchedPaths.length === 1, 'excluded unmatchedPaths must contain one entry');
  assert(observation.unmatchedPaths[0] === 'scripts/collect-ops72-shadow-metrics.mjs', 'excluded path does not identify the known collector gap');
  assert(typeof observation.rootCause === 'string' && observation.rootCause.length > 0, 'excluded rootCause is required');
}

export function validateLiveEvidence(document, { rawRoot = null } = {}) {
  assert(document && typeof document === 'object', 'live evidence must be an object');
  assert(document.formatVersion === 1, 'formatVersion must be 1');
  assert(document.issue === 'OPS-72', 'issue must be OPS-72');
  assert(document.targetBranch === 'staging', 'targetBranch must be staging');
  assert(document.requiredObservationCount === 5, 'requiredObservationCount must be 5');
  assert(Array.isArray(document.observations) && document.observations.length === 5, 'exactly five observations are required');
  assert(Array.isArray(document.excludedObservations) && document.excludedObservations.length === 1, 'exactly one excluded observation is required');

  const pullRequests = new Set();
  const runIds = new Set();
  document.observations.forEach((observation, index) => {
    validatePass(observation, index);
    assert(!pullRequests.has(observation.pullRequest), `duplicate pull request ${observation.pullRequest}`);
    assert(!runIds.has(observation.runId), `duplicate run ${observation.runId}`);
    pullRequests.add(observation.pullRequest);
    runIds.add(observation.runId);
    if (rawRoot) {
      const rawPath = path.resolve(rawRoot, String(observation.runId), observation.rawArtifactFile);
      const bytes = readFileSync(rawPath);
      const digest = createHash('sha256').update(bytes).digest('hex');
      assert(digest === observation.artifactSha256.toLowerCase(), `raw artifact hash mismatch for run ${observation.runId}`);
    }
  });
  const excluded = document.excludedObservations[0];
  validateExcluded(excluded);
  assert(!pullRequests.has(excluded.pullRequest), `excluded pull request ${excluded.pullRequest} is duplicated`);
  assert(!runIds.has(excluded.runId), `excluded run ${excluded.runId} is duplicated`);

  const aggregate = document.aggregate;
  assert(aggregate && typeof aggregate === 'object', 'aggregate is required');
  assert(aggregate.passCount === 5, 'aggregate.passCount must be 5');
  assert(aggregate.contractFailureCount === 0, 'aggregate.contractFailureCount must be zero for accepted observations');
  assert(aggregate.productFailureCount === 0 && aggregate.staleFailureCount === 0 && aggregate.environmentFailureCount === 0, 'aggregate failure counts must be zero');
  assert(aggregate.reruns === 0 && aggregate.acceptedStaleProofs === 0 && aggregate.productFailuresRetriedToGreen === 0, 'unsafe retry/stale metrics are not zero');
  assert(aggregate.targetStatus === 'pending-live-timing-baseline', 'targetStatus must remain pending-live-timing-baseline');
  assert(aggregate.timeToActionableFailureMedianMs === null, 'timing median must remain null without baseline');
  assert(aggregate.baselineMedianTimeToActionableFailureMs === null, 'baseline timing must remain null without baseline');
  assert(aggregate.rerunReductionPercent === null && aggregate.timeToActionableFailureReductionPercent === null, 'optimization percentages must remain null without baseline');
  assert(typeof document.generatedAtUtc === 'string', 'generatedAtUtc is required');
  assert(!/[A-Za-z]:\\|\/Users\/|\/home\/|\\\\/.test(JSON.stringify(document)), 'artifact contains an absolute local path');
  return { schemaVersion: 1, issue: document.issue, observations: 5, excludedObservations: 1, passCount: 5, targetStatus: aggregate.targetStatus, rawArtifactsChecked: Boolean(rawRoot) };
}

function parseArgs(argv) {
  const options = { artifact: DEFAULT_ARTIFACT, rawRoot: null, json: null };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--artifact' || argument === '--raw-root' || argument === '--json') {
      const value = argv[index + 1];
      if (!value || value.startsWith('--')) throw new LiveEvidenceError(`${argument} requires a value`);
      if (argument === '--artifact') options.artifact = value;
      if (argument === '--raw-root') options.rawRoot = value;
      if (argument === '--json') options.json = value;
      index += 1;
    } else if (argument === '--help' || argument === '-h') options.help = true;
    else throw new LiveEvidenceError(`unknown argument: ${argument}`);
  }
  return options;
}

export function main(argv = process.argv.slice(2), { root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..') } = {}) {
  try {
    const options = parseArgs(argv);
    if (options.help) {
      console.log('Usage: node scripts/verify-ops72-live-shadow-evidence.mjs [--artifact <path>] [--raw-root <path>] [--json <path>]');
      return 0;
    }
    const document = JSON.parse(readFileSync(path.resolve(root, options.artifact), 'utf8'));
    const result = validateLiveEvidence(document, { rawRoot: options.rawRoot ? path.resolve(root, options.rawRoot) : null });
    if (options.json) writeFileSync(path.resolve(root, options.json), `${JSON.stringify(result, null, 2)}\n`, 'utf8');
    console.log(`OPS-72 LIVE EVIDENCE PASS observations=${result.observations} target=${result.targetStatus}`);
    return 0;
  } catch (error) {
    console.error(`OPS-72 LIVE EVIDENCE FAILED: ${error.message}`);
    return 2;
  }
}

const invoked = process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invoked) process.exitCode = main();
