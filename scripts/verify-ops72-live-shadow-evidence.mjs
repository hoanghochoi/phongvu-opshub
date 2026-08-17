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

function validateFailure(failure, label) {
  if (failure === null || failure === undefined) return;
  assert(failure && typeof failure === 'object', `${label} is invalid`);
  assert(typeof failure.category === 'string' && failure.category.length > 0, `${label}.category is invalid`);
  assert(Number.isInteger(failure.exitCode), `${label}.exitCode is invalid`);
  assertIso(failure.observedAtUtc, `${label}.observedAtUtc`);
  assert(Number.isInteger(failure.elapsedMs) && failure.elapsedMs >= 0, `${label}.elapsedMs is invalid`);
}

function validateTelemetry(telemetry, label) {
  assert(telemetry && typeof telemetry === 'object', `${label} must be an object`);
  assert([2, 3, 4].includes(telemetry.schemaVersion), `${label}.schemaVersion must be 2 or 3 (or 4 for execution canary)`);
  assert(typeof telemetry.cohortId === 'string' && /^[A-Za-z0-9._-]+$/.test(telemetry.cohortId), `${label}.cohortId is invalid`);
  assertIso(telemetry.queuedAtUtc, `${label}.queuedAtUtc`);
  assertIso(telemetry.startedAtUtc, `${label}.startedAtUtc`);
  assertIso(telemetry.completedAtUtc, `${label}.completedAtUtc`);
  for (const key of ['queueDurationMs', 'executionDurationMs', 'retryCount', 'autoRetryCount', 'fullRetryCount']) {
    assert(Number.isInteger(telemetry[key]) && telemetry[key] >= 0, `${label}.${key} is invalid`);
  }
  validateFailure(telemetry.firstActionableFailure, `${label}.firstActionableFailure`);
  validateFailure(telemetry.firstObservedFailure, `${label}.firstObservedFailure`);
  if (telemetry.schemaVersion === 3 || telemetry.schemaVersion === 4) {
    const executionCanary = telemetry.schemaVersion === 4;
    assert(
      telemetry.executionMode === (executionCanary ? 'execution-canary' : 'plan-only'),
      `${label}.executionMode is invalid for schema ${telemetry.schemaVersion}`,
    );
    for (const key of ['autoDurationMs', 'fullDurationMs', 'decisionDurationMs']) {
      assert(Number.isInteger(telemetry[key]) && telemetry[key] >= 0, `${label}.${key} is invalid`);
    }
    assert(telemetry.decisionDurationMs <= telemetry.executionDurationMs, `${label}.decisionDurationMs cannot exceed executionDurationMs`);
    const eligibility = telemetry.measurementEligibility;
    assert(eligibility && typeof eligibility === 'object', `${label}.measurementEligibility is required`);
    assert(
      eligibility.retryReduction === executionCanary,
      executionCanary
        ? `${label}.retryReduction eligibility is invalid`
        : `${label}.retryReduction must remain ineligible for plan-only evidence`,
    );
    assert(
      eligibility.timeToActionableFailure === executionCanary,
      executionCanary
        ? `${label}.timeToActionableFailure eligibility is invalid`
        : `${label}.timeToActionableFailure must remain ineligible for plan-only evidence`,
    );
    assert(
      eligibility.reasonCode === (executionCanary ? 'execution-canary-auto-only' : 'plan-only-shadow'),
      `${label}.measurementEligibility.reasonCode is invalid`,
    );
    if (executionCanary) {
      for (const key of ['commandRetryCount', 'externalRerunCount']) {
        assert(Number.isInteger(telemetry[key]) && telemetry[key] >= 0, `${label}.${key} is invalid`);
      }
    }
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
  assert([1, 2, 3, 4].includes(document.formatVersion), 'formatVersion must be 1, 2, 3 or 4');
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
  assert(aggregate.acceptedStaleProofs === 0 && aggregate.productFailuresRetriedToGreen === 0, 'unsafe retry/stale metrics are not zero');
  if (document.formatVersion !== 4) {
    assert(aggregate.reruns === 0, 'plan-only evidence cannot contain workflow reruns');
  }
  if (document.formatVersion === 1) {
    assert(aggregate.targetStatus === 'pending-live-timing-baseline', 'legacy targetStatus must remain pending-live-timing-baseline');
    assert(aggregate.timeToActionableFailureMedianMs === null, 'legacy timing median must remain null without baseline');
    assert(aggregate.baselineMedianTimeToActionableFailureMs === null, 'legacy baseline timing must remain null without baseline');
    assert(aggregate.rerunReductionPercent === null && aggregate.timeToActionableFailureReductionPercent === null, 'legacy optimization percentages must remain null without baseline');
  } else {
    assert(typeof document.cohortId === 'string' && /^[A-Za-z0-9._-]+$/.test(document.cohortId), 'cohortId is invalid');
    assert(document.observations.every((observation) => observation.telemetry?.cohortId === document.cohortId), 'observations must use one comparable cohort');
    assert(['pending-live-timing-baseline', 'revise', 'meets-target'].includes(aggregate.targetStatus), 'v2 targetStatus is invalid');
    assert(Number.isInteger(aggregate.shadowDurationMedianMs) && aggregate.shadowDurationMedianMs >= 0, 'shadowDurationMedianMs is invalid');
    assert(Number.isInteger(aggregate.baselineShadowDurationMedianMs) && aggregate.baselineShadowDurationMedianMs >= 0, 'baselineShadowDurationMedianMs is invalid');
    if (document.formatVersion === 4) {
      assert(aggregate.shadowDurationReductionPercent === null || Number.isFinite(aggregate.shadowDurationReductionPercent), 'v4 shadowDurationReductionPercent is invalid');
      assert(aggregate.targetStatus === 'pending-live-timing-baseline', 'v4 target status must remain pending until a canary baseline exists');
    } else {
      assert(Number.isFinite(aggregate.shadowDurationReductionPercent), 'shadowDurationReductionPercent is invalid');
      assert(aggregate.targetStatus !== 'meets-target' || aggregate.shadowDurationReductionPercent >= 25, 'meets-target requires the 25% timing target');
      assert(aggregate.targetStatus !== 'revise' || aggregate.shadowDurationReductionPercent < 25 || aggregate.rerunReductionPercent === null, 'revise status must retain an unmet or unmeasurable target');
    }
    if (document.formatVersion !== 4) {
      assert(aggregate.timeToActionableFailureMedianMs === null, 'no failure sample may claim a first-actionable-failure median');
      assert(aggregate.baselineMedianTimeToActionableFailureMs === null, 'no failure sample may claim a baseline first-actionable-failure median');
    } else {
      assert(
        aggregate.timeToActionableFailureMedianMs === null
          || (Number.isInteger(aggregate.timeToActionableFailureMedianMs) && aggregate.timeToActionableFailureMedianMs >= 0),
        'execution-canary first-actionable-failure median is invalid',
      );
      assert(
        aggregate.baselineMedianTimeToActionableFailureMs === null
          || (Number.isInteger(aggregate.baselineMedianTimeToActionableFailureMs) && aggregate.baselineMedianTimeToActionableFailureMs >= 0),
        'execution-canary baseline first-actionable-failure median is invalid',
      );
    }
    if (document.formatVersion === 3) {
      assert(document.observations.every((observation) => observation.telemetry?.schemaVersion === 3), 'v3 observations must use telemetry schema 3');
      assert(document.observations.every((observation) => observation.telemetry?.executionMode === 'plan-only'), 'v3 observations must remain plan-only');
      assert(document.measurementEligibility?.retryReduction === false, 'v3 retry reduction must be ineligible');
      assert(document.measurementEligibility?.timeToActionableFailure === false, 'v3 TTAF must be ineligible');
      assert(document.measurementEligibility?.reasonCode === 'plan-only-shadow', 'v3 measurement eligibility reason is invalid');
      assert(Number.isInteger(aggregate.decisionDurationMedianMs) && aggregate.decisionDurationMedianMs >= 0, 'decisionDurationMedianMs is invalid');
      assert(aggregate.decisionDurationReductionPercent === null, 'plan-only decision reduction must remain unmeasurable');
    }
    if (document.formatVersion === 4) {
      assert(document.observations.every((observation) => observation.telemetry?.schemaVersion === 4), 'v4 observations must use telemetry schema 4');
      assert(document.observations.every((observation) => observation.telemetry?.executionMode === 'execution-canary'), 'v4 observations must use execution-canary mode');
      assert(document.measurementEligibility?.executionMode === 'execution-canary', 'v4 execution mode is invalid');
      assert(document.measurementEligibility?.retryReduction === true, 'v4 retry reduction must be eligible');
      assert(document.measurementEligibility?.timeToActionableFailure === true, 'v4 TTAF must be eligible');
      assert(document.measurementEligibility?.reasonCode === 'execution-canary-auto-only', 'v4 measurement eligibility reason is invalid');
      assert(Number.isInteger(aggregate.commandRetries) && aggregate.commandRetries >= 0, 'v4 commandRetries is invalid');
      assert(Number.isInteger(aggregate.externalReruns) && aggregate.externalReruns >= 0, 'v4 externalReruns is invalid');
      assert(aggregate.reruns === aggregate.externalReruns, 'v4 reruns must represent external workflow reruns');
      assert(aggregate.decisionDurationReductionPercent === null, 'v4 decision reduction requires an execution-canary baseline');
    }
  }
  assert(typeof document.generatedAtUtc === 'string', 'generatedAtUtc is required');
  assert(!/[A-Za-z]:\\|\/Users\/|\/home\/|\\\\/.test(JSON.stringify(document)), 'artifact contains an absolute local path');
  return { schemaVersion: document.formatVersion, issue: document.issue, observations: 5, excludedObservations: 1, passCount: 5, targetStatus: aggregate.targetStatus, rawArtifactsChecked: Boolean(rawRoot) };
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
