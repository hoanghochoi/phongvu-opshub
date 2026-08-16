#!/usr/bin/env node

import { createHash } from 'node:crypto';
import {
  mkdirSync,
  readFileSync,
  readdirSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

import { validateLiveEvidence } from './verify-ops72-live-shadow-evidence.mjs';

const SHA1_RE = /^[0-9a-f]{40}$/i;
const SHA256_RE = /^[0-9a-f]{64}$/i;
const COHORT_RE = /^[A-Za-z0-9._-]+$/;
const DEFAULT_RAW_ROOT = 'tmp/ops72-live-shadow';
const DEFAULT_OUTPUT = 'docs/migrations/ops-72-live-shadow-evidence.json';
const DEFAULT_BASELINE = DEFAULT_OUTPUT;
const MANIFEST_NAME = 'verify-task-shadow-manifest.json';
const REPORT_NAME = 'verify-task-shadow.json';
const REQUIRED_OBSERVATIONS = 5;

export class LiveEvidenceCollectionError extends Error {}

function fail(message) {
  throw new LiveEvidenceCollectionError(message);
}

function assert(condition, message) {
  if (!condition) fail(message);
}

function assertSha(value, label, pattern = SHA1_RE) {
  assert(typeof value === 'string' && pattern.test(value), `${label} must be a valid digest`);
}

function assertIso(value, label) {
  assert(typeof value === 'string' && !Number.isNaN(Date.parse(value)), `${label} must be an ISO timestamp`);
}

function assertRelative(value, label) {
  assert(typeof value === 'string' && value === REPORT_NAME, `${label} must be ${REPORT_NAME}`);
}

function digest(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function readJson(file, label) {
  try {
    return JSON.parse(readFileSync(file, 'utf8'));
  } catch (error) {
    fail(`${label} is not valid JSON: ${error.message}`);
  }
}

function safeChild(root, candidate, label) {
  const resolvedRoot = path.resolve(root);
  const resolved = path.resolve(candidate);
  const relative = path.relative(resolvedRoot, resolved);
  assert(relative !== '..' && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative), `${label} escapes raw root`);
  return resolved;
}

function walkManifests(root) {
  const manifests = [];
  function visit(directory) {
    for (const entry of readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      const target = path.join(directory, entry.name);
      if (entry.isDirectory()) {
        visit(target);
      } else if (entry.isFile() && entry.name === MANIFEST_NAME) {
        manifests.push(target);
      }
    }
  }
  visit(root);
  return manifests;
}

function validateRun(run, label) {
  assert(run && typeof run === 'object', `${label} is required`);
  assertIso(run.createdAt, `${label}.createdAt`);
  assertIso(run.startedAt, `${label}.startedAt`);
  assertIso(run.completedAt, `${label}.completedAt`);
  assert(Number.isInteger(run.githubDurationMs) && run.githubDurationMs >= 0, `${label}.githubDurationMs is invalid`);
}

function observationFromManifest(manifestPath, rawRoot) {
  const manifestDirectory = path.dirname(manifestPath);
  const runDirectory = path.basename(manifestDirectory);
  const manifest = readJson(manifestPath, manifestPath);
  const label = `manifest ${manifestPath}`;

  assert(manifest.formatVersion === 1, `${label}.formatVersion must be 1`);
  assert(manifest.issue === 'OPS-72', `${label}.issue must be OPS-72`);
  assert(manifest.targetBranch === 'staging', `${label}.targetBranch must be staging`);
  assert(COHORT_RE.test(manifest.cohortId || ''), `${label}.cohortId is invalid`);
  assert(Number.isInteger(manifest.pullRequest) && manifest.pullRequest > 0, `${label}.pullRequest is invalid`);
  assert(Number.isInteger(manifest.runId) && manifest.runId > 0, `${label}.runId is invalid`);
  assert(runDirectory === String(manifest.runId), `${label} must be stored under a directory named by runId`);
  assert(/^https:\/\/github\.com\/[^/]+\/[^/]+\/actions\/runs\/\d+$/.test(manifest.runUrl || ''), `${label}.runUrl is invalid`);
  assertSha(manifest.prHeadSha, `${label}.prHeadSha`);
  assertSha(manifest.baseSha, `${label}.baseSha`);
  assertRelative(manifest.reportFile, `${label}.reportFile`);
  assertSha(manifest.reportSha256, `${label}.reportSha256`, SHA256_RE);
  assertIso(manifest.generatedAtUtc, `${label}.generatedAtUtc`);
  validateRun(manifest.run, `${label}.run`);

  const reportPath = safeChild(rawRoot, path.join(manifestDirectory, manifest.reportFile), `${label}.reportFile`);
  const reportBytes = readFileSync(reportPath);
  const reportSha256 = digest(reportBytes);
  assert(reportSha256 === manifest.reportSha256.toLowerCase(), `${label}.reportSha256 does not match ${REPORT_NAME}`);
  const report = JSON.parse(reportBytes.toString('utf8'));

  assert(report.schemaVersion === 3 && report.mode === 'shadow', `${label} report must be schema-v3 shadow output`);
  assert(report.status === 'passed' && report.classification === 'shadow-observation', `${label} report is not an accepted pass`);
  assert(report.autoExitCode === 0 && report.fullExitCode === 0, `${label} report exit codes must be zero`);
  assert(report.blockingChecksUnchanged === true, `${label} blocking checks changed`);
  assert(report.fingerprint?.stale === false, `${label} report fingerprint is stale`);
  assert(Array.isArray(report.unmatchedPaths) && report.unmatchedPaths.length === 0, `${label} has unmatched paths`);
  assert(Array.isArray(report.autoSelectedProfiles) && Array.isArray(report.fullProfiles), `${label} profile data is missing`);
  assert(report.autoSelectedProfiles.every((id) => report.fullProfiles.includes(id)), `${label} auto profile is absent from full profile list`);
  assert(report.telemetry?.schemaVersion === 3, `${label} telemetry schema must be 3`);
  assert(report.telemetry.cohortId === manifest.cohortId, `${label} telemetry cohort does not match manifest`);
  assert(report.telemetry.executionMode === 'plan-only', `${label} execution mode must be plan-only`);
  assert(report.telemetry.measurementEligibility?.retryReduction === false, `${label} retry reduction must remain ineligible`);
  assert(report.telemetry.measurementEligibility?.timeToActionableFailure === false, `${label} TTAF must remain ineligible`);
  assert(report.telemetry.measurementEligibility?.reasonCode === 'plan-only-shadow', `${label} measurement eligibility reason is invalid`);
  assert(report.headSha === manifest.reportedHeadSha, `${label} reported head SHA does not match manifest`);
  assert(report.baseSha === manifest.baseSha, `${label} reported base SHA does not match manifest`);
  assert(Number(report.telemetry.retryCount || 0) === 0, `${label} contains a retry and is not comparable live evidence`);
  assert(Number(report.metrics?.reruns || 0) === 0, `${label} metrics contain a rerun and are not comparable live evidence`);
  assert(typeof report.headSha === 'string' && SHA1_RE.test(report.headSha), `${label} reported head SHA is invalid`);
  assertIso(report.telemetry.queuedAtUtc, `${label}.telemetry.queuedAtUtc`);
  assertIso(report.telemetry.startedAtUtc, `${label}.telemetry.startedAtUtc`);
  assertIso(report.telemetry.completedAtUtc, `${label}.telemetry.completedAtUtc`);

  return {
    pullRequest: manifest.pullRequest,
    runId: manifest.runId,
    runUrl: manifest.runUrl,
    prHeadSha: manifest.prHeadSha,
    baseSha: manifest.baseSha,
    reportedHeadSha: report.headSha,
    artifactSha256: reportSha256,
    rawArtifactFile: REPORT_NAME,
    status: report.status,
    classification: report.classification,
    selectedProfiles: report.autoSelectedProfiles,
    fullProfiles: report.fullProfiles,
    omittedProfiles: report.omittedProfiles || [],
    changedPathCount: Array.isArray(report.changedPaths) ? report.changedPaths.length : 0,
    autoExitCode: report.autoExitCode,
    fullExitCode: report.fullExitCode,
    blockingChecksUnchanged: report.blockingChecksUnchanged,
    stale: report.fingerprint.stale,
    unmatchedPaths: report.unmatchedPaths,
    reruns: report.metrics?.reruns || 0,
    humanIntervention: report.metrics?.humanIntervention || false,
    falsePositive: report.metrics?.falsePositive ?? null,
    falseNegative: report.metrics?.falseNegative ?? null,
    shadowDurationMs: Number(report.telemetry.executionDurationMs),
    executionMode: report.telemetry.executionMode,
    autoDurationMs: Number(report.telemetry.autoDurationMs),
    fullDurationMs: Number(report.telemetry.fullDurationMs),
    decisionDurationMs: Number(report.telemetry.decisionDurationMs),
    firstObservedFailure: report.telemetry.firstObservedFailure ?? null,
    measurementEligibility: report.telemetry.measurementEligibility,
    run: manifest.run,
    telemetry: report.telemetry,
  };
}

function median(values) {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0
    ? (sorted[middle - 1] + sorted[middle]) / 2
    : sorted[middle];
}

function reductionPercent(baseline, current) {
  if (!Number.isFinite(baseline) || baseline <= 0) return null;
  return Number((((baseline - current) / baseline) * 100).toFixed(2));
}

function loadBaseline(file) {
  const document = readJson(file, `baseline ${file}`);
  assert(document.issue === 'OPS-72', 'baseline issue must be OPS-72');
  assert(document.baseline && typeof document.baseline === 'object', 'baseline section is required');
  assert(Number.isInteger(document.baseline.shadowDurationMedianMs), 'baseline shadow duration median is required');
  assert(Number.isInteger(document.baseline.githubDurationMedianMs), 'baseline GitHub duration median is required');
  assert(Number.isInteger(document.baseline.reruns), 'baseline rerun count is required');
  assert(Array.isArray(document.excludedObservations) && document.excludedObservations.length === 1, 'baseline must retain one excluded observation');
  return document;
}

function buildInterpretation({ cohortId, shadowMedian, baselineShadowMedian, shadowReduction, rerunReduction, targetStatus }) {
  const timing = `The comparable shadow-duration median is ${shadowMedian}ms versus the pre-telemetry baseline median of ${baselineShadowMedian}ms, a ${shadowReduction ?? 'unmeasurable'}% reduction.`;
  const reruns = rerunReduction === null
    ? 'The baseline has zero environment retries, so the 30% rerun-reduction target is not measurable from this cohort.'
    : `The comparable rerun reduction is ${rerunReduction}%.`;
  return [
    `Five post-telemetry observations share cohort ${cohortId}, pass with stale=false, zero unmatched paths and zero retries.`,
    timing,
    reruns,
    'The cohort is plan-only shadow evidence; retry reduction and time-to-actionable-failure are explicitly ineligible until an execution canary is collected.',
    `Target status is ${targetStatus}; the affected matrix remains observational until both acceptance targets are measurable and met.`,
  ];
}

export function collectLiveEvidence({
  rawRoot = DEFAULT_RAW_ROOT,
  output = DEFAULT_OUTPUT,
  baseline = DEFAULT_BASELINE,
} = {}) {
  const resolvedRawRoot = path.resolve(rawRoot);
  assert(statSync(resolvedRawRoot).isDirectory(), `raw root is not a directory: ${resolvedRawRoot}`);
  const manifestPaths = walkManifests(resolvedRawRoot);
  assert(manifestPaths.length === REQUIRED_OBSERVATIONS, `expected exactly ${REQUIRED_OBSERVATIONS} manifests, found ${manifestPaths.length}`);

  const baselineDocument = loadBaseline(path.resolve(baseline));
  const observations = manifestPaths.map((file) => observationFromManifest(file, resolvedRawRoot));
  const cohortIds = new Set(observations.map((observation) => observation.telemetry.cohortId));
  assert(cohortIds.size === 1, 'all observations must use one comparable cohort');
  const cohortId = [...cohortIds][0];
  const pullRequests = new Set();
  const runIds = new Set();
  for (const observation of observations) {
    assert(!pullRequests.has(observation.pullRequest), `duplicate pull request ${observation.pullRequest}`);
    assert(!runIds.has(observation.runId), `duplicate run ${observation.runId}`);
    pullRequests.add(observation.pullRequest);
    runIds.add(observation.runId);
  }

  const shadowMedian = median(observations.map((observation) => observation.shadowDurationMs));
  const decisionDurationMedian = median(observations.map((observation) => observation.decisionDurationMs));
  const githubMedian = median(observations.map((observation) => observation.run.githubDurationMs));
  const baselineShadowMedian = baselineDocument.baseline.shadowDurationMedianMs;
  const baselineGithubMedian = baselineDocument.baseline.githubDurationMedianMs;
  const shadowReduction = reductionPercent(baselineShadowMedian, shadowMedian);
  const githubReduction = reductionPercent(baselineGithubMedian, githubMedian);
  const reruns = observations.reduce((sum, observation) => sum + observation.reruns, 0);
  const rerunReduction = baselineDocument.baseline.reruns > 0
    ? reductionPercent(baselineDocument.baseline.reruns, reruns)
    : null;
  const targetStatus = shadowReduction !== null && shadowReduction >= 25 && rerunReduction !== null && rerunReduction >= 30
    ? 'meets-target'
    : 'revise';

  const document = {
    formatVersion: 3,
    issue: 'OPS-72',
    targetBranch: 'staging',
    generatedAtUtc: new Date().toISOString(),
    requiredObservationCount: REQUIRED_OBSERVATIONS,
    cohortId,
    measurementEligibility: {
      executionMode: 'plan-only',
      retryReduction: false,
      timeToActionableFailure: false,
      reasonCode: 'plan-only-shadow',
    },
    observations,
    excludedObservations: baselineDocument.excludedObservations,
    baseline: baselineDocument.baseline,
    aggregate: {
      passCount: observations.length,
      contractFailureCount: 0,
      productFailureCount: 0,
      staleFailureCount: 0,
      environmentFailureCount: 0,
      reruns,
      acceptedStaleProofs: 0,
      productFailuresRetriedToGreen: 0,
      timeToActionableFailureMedianMs: null,
      baselineMedianTimeToActionableFailureMs: null,
      rerunReductionPercent: rerunReduction,
      timeToActionableFailureReductionPercent: null,
      decisionDurationMedianMs: decisionDurationMedian,
      baselineDecisionDurationMedianMs: null,
      decisionDurationReductionPercent: null,
      shadowDurationMedianMs: shadowMedian,
      baselineShadowDurationMedianMs: baselineShadowMedian,
      shadowDurationReductionPercent: shadowReduction,
      githubDurationMedianMs: githubMedian,
      baselineGithubDurationMedianMs: baselineGithubMedian,
      githubDurationReductionPercent: githubReduction,
      targetStatus,
      targetDecision: targetStatus === 'meets-target' ? 'promote-after-approval' : 'do-not-promote',
    },
    interpretation: buildInterpretation({
      cohortId,
      shadowMedian,
      baselineShadowMedian,
      shadowReduction,
      rerunReduction,
      targetStatus,
    }),
  };

  validateLiveEvidence(document, { rawRoot: resolvedRawRoot });
  const resolvedOutput = path.resolve(output);
  const outputRelative = path.relative(resolvedRawRoot, resolvedOutput);
  assert(outputRelative === '..' || (outputRelative.startsWith(`..${path.sep}`) && !path.isAbsolute(outputRelative)), 'output must be outside raw root');
  mkdirSync(path.dirname(resolvedOutput), { recursive: true });
  writeFileSync(resolvedOutput, `${JSON.stringify(document, null, 2)}\n`, 'utf8');
  return document;
}

function parseArgs(argv) {
  const options = { rawRoot: DEFAULT_RAW_ROOT, output: DEFAULT_OUTPUT, baseline: DEFAULT_BASELINE };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--raw-root' || argument === '--output' || argument === '--baseline') {
      const value = argv[index + 1];
      if (!value || value.startsWith('--')) fail(`${argument} requires a value`);
      const key = argument === '--raw-root' ? 'rawRoot' : argument.slice(2);
      options[key] = value;
      index += 1;
    } else if (argument === '--help' || argument === '-h') {
      options.help = true;
    } else {
      fail(`unknown argument: ${argument}`);
    }
  }
  return options;
}

export function main(argv = process.argv.slice(2)) {
  try {
    const options = parseArgs(argv);
    if (options.help) {
      console.log('Usage: node scripts/collect-ops72-live-shadow-evidence.mjs [--raw-root <path>] [--baseline <path>] [--output <path>]');
      return 0;
    }
    const document = collectLiveEvidence(options);
    console.log(JSON.stringify({
      observations: document.observations.length,
      cohortId: document.cohortId,
      targetStatus: document.aggregate.targetStatus,
      shadowDurationReductionPercent: document.aggregate.shadowDurationReductionPercent,
      rerunReductionPercent: document.aggregate.rerunReductionPercent,
    }, null, 2));
    return 0;
  } catch (error) {
    console.error(`OPS-72 live evidence collection failed: ${error.message}`);
    return 2;
  }
}

const invoked = process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invoked) process.exitCode = main();
