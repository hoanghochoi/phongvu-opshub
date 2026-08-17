#!/usr/bin/env node

import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const DEFAULT_ARTIFACT = 'docs/migrations/ops-72-execution-canary-progress.json';
const SHA1_RE = /^[0-9a-f]{40}$/i;
const SHA256_RE = /^[0-9a-f]{64}$/i;
const URL_RE = /^https:\/\/github\.com\/[^/]+\/[^/]+\/actions\/runs\/\d+$/;
const PROFILE_RE = /^[a-z0-9-]+$/;

export class ExecutionCanaryProgressError extends Error {}

function assert(condition, message) {
  if (!condition) throw new ExecutionCanaryProgressError(message);
}

function assertSha(value, label, pattern = SHA1_RE) {
  assert(typeof value === 'string' && pattern.test(value), `${label} must be a valid digest`);
}

function validateObservation(observation, index, cohortId) {
  const label = `observations[${index}]`;
  assert(observation && typeof observation === 'object', `${label} must be an object`);
  assert(Number.isInteger(observation.pullRequest) && observation.pullRequest > 0, `${label}.pullRequest is invalid`);
  assert(Number.isInteger(observation.runId) && observation.runId > 0, `${label}.runId is invalid`);
  assert(typeof observation.runUrl === 'string' && URL_RE.test(observation.runUrl), `${label}.runUrl is invalid`);
  assertSha(observation.prHeadSha, `${label}.prHeadSha`);
  assertSha(observation.baseSha, `${label}.baseSha`);
  assertSha(observation.reportedHeadSha, `${label}.reportedHeadSha`);
  assertSha(observation.artifactSha256, `${label}.artifactSha256`, SHA256_RE);
  assert(observation.status === 'passed', `${label}.status must be passed`);
  assert(observation.classification === 'shadow-observation', `${label}.classification is invalid`);
  assert(observation.executionMode === 'execution-canary', `${label}.executionMode is invalid`);
  assert(observation.cohortId === cohortId, `${label}.cohortId does not match the ledger cohort`);
  assert(Array.isArray(observation.selectedProfiles) && observation.selectedProfiles.length > 0, `${label}.selectedProfiles is invalid`);
  assert(Array.isArray(observation.fullProfiles) && observation.fullProfiles.length > 0, `${label}.fullProfiles is invalid`);
  assert(observation.fullProfiles.every((profile) => typeof profile === 'string' && PROFILE_RE.test(profile)), `${label}.fullProfiles contains an invalid profile`);
  assert(observation.selectedProfiles.every((profile) => typeof profile === 'string' && PROFILE_RE.test(profile) && observation.fullProfiles.includes(profile)), `${label}.selectedProfiles is not additive`);
  assert(Number.isInteger(observation.changedPathCount) && observation.changedPathCount >= 0, `${label}.changedPathCount is invalid`);
  assert(observation.autoExitCode === 0 && observation.fullExitCode === 0, `${label} exit codes must be zero`);
  assert(observation.stale === false, `${label}.stale must be false`);
  assert(Array.isArray(observation.unmatchedPaths) && observation.unmatchedPaths.length === 0, `${label}.unmatchedPaths must be empty`);
  assert(Number.isInteger(observation.reruns) && observation.reruns === 0, `${label}.reruns must be zero`);
  assert(observation.humanIntervention === false, `${label}.humanIntervention must be false`);
}

export function validateProgress(document) {
  assert(document && typeof document === 'object', 'progress ledger must be an object');
  assert(document.formatVersion === 1, 'formatVersion must be 1');
  assert(document.issue === 'OPS-72', 'issue must be OPS-72');
  assert(document.targetBranch === 'staging', 'targetBranch must be staging');
  assert(document.requiredObservationCount === 5, 'requiredObservationCount must be 5');
  assert(typeof document.cohortId === 'string' && /^[A-Za-z0-9._-]+$/.test(document.cohortId), 'cohortId is invalid');
  const isComplete = document.collectedObservationCount === document.requiredObservationCount;
  assert(
    document.status === (isComplete ? 'complete' : 'collecting'),
    isComplete ? 'complete progress must use status complete' : 'partial progress must remain collecting',
  );
  assert(document.promotionEligible === false, 'execution-canary progress cannot be promotion eligible');
  assert(Array.isArray(document.observations), 'observations must be an array');
  assert(Number.isInteger(document.collectedObservationCount), 'collectedObservationCount is invalid');
  assert(document.collectedObservationCount === document.observations.length, 'collectedObservationCount does not match observations');
  assert(document.collectedObservationCount > 0 && document.collectedObservationCount <= document.requiredObservationCount, 'progress ledger count is invalid');

  const pullRequests = new Set();
  const runIds = new Set();
  document.observations.forEach((observation, index) => {
    validateObservation(observation, index, document.cohortId);
    assert(!pullRequests.has(observation.pullRequest), `duplicate pull request ${observation.pullRequest}`);
    assert(!runIds.has(observation.runId), `duplicate run ${observation.runId}`);
    pullRequests.add(observation.pullRequest);
    runIds.add(observation.runId);
  });

  assert(document.authority && document.authority.kind === 'progress-only', 'authority.kind must be progress-only');
  assert(document.authority.finalEvidencePath === 'docs/migrations/ops-72-live-shadow-evidence.json', 'final evidence path is invalid');
  assert(document.authority.syntheticEvidenceAccepted === false, 'synthetic evidence must be rejected');
  assert(document.authority.rawArtifactsCommitted === false, 'raw artifacts must not be committed');
  assert(!/[A-Za-z]:\\|\/Users\/|\/home\/|\\\\/.test(JSON.stringify(document)), 'progress ledger contains an absolute local path');
  return {
    status: document.status,
    issue: document.issue,
    cohortId: document.cohortId,
    collectedObservationCount: document.collectedObservationCount,
    requiredObservationCount: document.requiredObservationCount,
    promotionEligible: document.promotionEligible,
  };
}

function parseArgs(argv) {
  const options = { artifact: DEFAULT_ARTIFACT, json: null };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--artifact' || argument === '--json') {
      const value = argv[index + 1];
      if (!value || value.startsWith('--')) throw new ExecutionCanaryProgressError(`${argument} requires a value`);
      if (argument === '--artifact') options.artifact = value;
      if (argument === '--json') options.json = value;
      index += 1;
    } else if (argument === '--help' || argument === '-h') {
      options.help = true;
    } else {
      throw new ExecutionCanaryProgressError(`unknown argument: ${argument}`);
    }
  }
  return options;
}

export function main(argv = process.argv.slice(2), { root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..') } = {}) {
  try {
    const options = parseArgs(argv);
    if (options.help) {
      console.log('Usage: node scripts/verify-ops72-execution-canary-progress.mjs [--artifact <path>] [--json <path>]');
      return 0;
    }
    const artifact = JSON.parse(readFileSync(path.resolve(root, options.artifact), 'utf8'));
    const result = validateProgress(artifact);
    if (options.json) writeFileSync(path.resolve(root, options.json), `${JSON.stringify(result, null, 2)}\n`, 'utf8');
    console.log(`OPS-72 EXECUTION-CANARY PROGRESS PASS observations=${result.collectedObservationCount}/${result.requiredObservationCount} status=${result.status}`);
    return 0;
  } catch (error) {
    console.error(`OPS-72 execution-canary progress failed: ${error.message}`);
    return 2;
  }
}

const invoked = process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invoked) process.exitCode = main();
