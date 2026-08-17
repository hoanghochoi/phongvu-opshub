#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DEFAULT_ARTIFACT = 'docs/migrations/ops-72-final-decision.json';
const SHA1_RE = /^[0-9a-f]{40}$/i;
const SHA256_RE = /^[0-9a-f]{64}$/i;
const EXPECTED_EVIDENCE = new Map([
  [
    'docs/migrations/ops-72-live-shadow-progress-v2.json',
    '8c498ba47ee3a39655a748348f4bd7d38eef1875d9e4866fc54b2751fe1c5eda',
  ],
  [
    'docs/migrations/ops-72-execution-canary-progress.json',
    'ac32aaed8fc16ed7e7421c695e1fbd94d0a17383f8297dc4337b396d09400fe5',
  ],
]);

export class Ops72FinalDecisionError extends Error {}

function assert(condition, message) {
  if (!condition) throw new Ops72FinalDecisionError(message);
}

function readJson(root, relativePath) {
  return JSON.parse(readFileSync(path.resolve(root, relativePath), 'utf8'));
}

function sha256(root, relativePath) {
  return createHash('sha256')
    .update(readFileSync(path.resolve(root, relativePath)))
    .digest('hex');
}

export function validateDecision(document, { root = ROOT } = {}) {
  assert(document && typeof document === 'object', 'decision must be an object');
  assert(document.formatVersion === 1, 'formatVersion must be 1');
  assert(document.issue === 'OPS-190', 'issue must be OPS-190');
  assert(document.subjectIssue === 'OPS-72', 'subjectIssue must be OPS-72');
  assert(SHA1_RE.test(String(document.sourceRevision || '')), 'sourceRevision is invalid');
  assert(document.decision === 'revise', 'decision must remain revise');
  assert(document.promotionDecision === 'do-not-promote', 'promotionDecision must remain do-not-promote');
  assert(document.matrixMode === 'observational', 'matrixMode must remain observational');
  assert(document.observed && typeof document.observed === 'object', 'observed summary is missing');
  assert(document.observed.requiredObservations === 5 && document.observed.completedObservations === 5, 'observed count must be 5/5');
  assert(document.observed.timingTargetPercent === 25, 'observed timing target must be 25%');
  assert(document.observed.timingReductionPercent === 8.77, 'observed timing reduction must be 8.77%');
  assert(document.observed.timingTargetMet === false, 'timing target must remain unmet');
  assert(document.observed.rerunTargetPercent === 30, 'observed rerun target must be 30%');
  assert(document.observed.rerunReductionPercent === null && document.observed.rerunComparable === false, 'rerun reduction must remain unmeasurable');
  assert(document.observed.firstActionableFailureSampleCount === 0, 'first-actionable-failure sample must remain empty');
  assert(document.observed.promotionEligible === false, 'observed promotion eligibility must remain false');
  assert(Array.isArray(document.evidence) && document.evidence.length === EXPECTED_EVIDENCE.size, 'evidence must contain exactly two records');

  const seen = new Set();
  for (const [index, record] of document.evidence.entries()) {
    assert(record && typeof record === 'object', `evidence[${index}] must be an object`);
    assert(EXPECTED_EVIDENCE.has(record.path), `evidence[${index}].path is not an approved source`);
    assert(!seen.has(record.path), `duplicate evidence path: ${record.path}`);
    seen.add(record.path);
    assert(SHA256_RE.test(String(record.sha256 || '')), `evidence[${index}].sha256 is invalid`);
    const actual = sha256(root, record.path);
    assert(actual === record.sha256.toLowerCase(), `evidence hash mismatch: ${record.path}`);
    assert(actual === EXPECTED_EVIDENCE.get(record.path), `evidence source changed: ${record.path}`);
    assert(typeof record.purpose === 'string' && record.purpose.length > 0, `evidence[${index}].purpose is missing`);
  }
  assert(seen.size === EXPECTED_EVIDENCE.size, 'evidence set is incomplete');

  const v2 = readJson(root, 'docs/migrations/ops-72-live-shadow-progress-v2.json');
  assert(v2.issue === 'OPS-72', 'v2 evidence issue is invalid');
  assert(v2.aggregate?.status === 'revise', 'v2 evidence must remain revise');
  assert(v2.aggregate?.promotionDecision === 'do-not-promote', 'v2 evidence must remain do-not-promote');
  assert(v2.aggregate?.rawReportsCommitted === false, 'v2 raw reports must remain uncommitted');
  assert(v2.observations?.length === 5, 'v2 evidence must contain five observations');
  assert(v2.aggregate?.timingPercentages?.targetPercent === 25, 'v2 timing target must remain 25%');
  assert(v2.aggregate?.timingPercentages?.shadowDurationReductionPercent === 8.77, 'v2 timing reduction must remain 8.77%');
  assert(v2.aggregate?.rerunReductionPercent === null, 'v2 rerun reduction must remain unmeasurable');

  const canary = readJson(root, 'docs/migrations/ops-72-execution-canary-progress.json');
  assert(canary.issue === 'OPS-72', 'execution-canary issue is invalid');
  assert(canary.status === 'complete', 'execution-canary collection must be complete');
  assert(canary.collectedObservationCount === 5 && canary.requiredObservationCount === 5, 'execution-canary count must be 5/5');
  assert(canary.promotionEligible === false, 'execution-canary progress cannot be promotion eligible');
  assert(canary.observations.every((observation) => observation.stale === false), 'execution-canary evidence contains stale proof');
  assert(canary.observations.every((observation) => observation.unmatchedPaths.length === 0), 'execution-canary evidence contains unmatched paths');
  assert(canary.observations.every((observation) => observation.reruns === 0), 'execution-canary evidence contains reruns');
  assert(!/[A-Za-z]:[\\/]|\\\\|\/Users\/|\/home\//.test(JSON.stringify(document)), 'decision contains an absolute local path');

  return {
    status: 'passed',
    issue: document.issue,
    subjectIssue: document.subjectIssue,
    decision: document.decision,
    promotionDecision: document.promotionDecision,
    matrixMode: document.matrixMode,
    observations: canary.collectedObservationCount,
    timingReductionPercent: v2.aggregate.timingPercentages.shadowDurationReductionPercent,
    timingTargetPercent: v2.aggregate.timingPercentages.targetPercent,
  };
}

function parseArgs(argv) {
  const options = { artifact: DEFAULT_ARTIFACT, json: null };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--artifact' || argument === '--json') {
      const value = argv[index + 1];
      if (!value || value.startsWith('--')) throw new Ops72FinalDecisionError(`${argument} requires a value`);
      if (argument === '--artifact') options.artifact = value;
      if (argument === '--json') options.json = value;
      index += 1;
    } else if (argument === '--help' || argument === '-h') {
      options.help = true;
    } else {
      throw new Ops72FinalDecisionError(`unknown argument: ${argument}`);
    }
  }
  return options;
}

export function main(argv = process.argv.slice(2), { root = ROOT } = {}) {
  try {
    const options = parseArgs(argv);
    if (options.help) {
      console.log('Usage: node scripts/verify-ops72-final-decision.mjs [--artifact <path>] [--json <path>]');
      return 0;
    }
    const result = validateDecision(readJson(root, options.artifact), { root });
    if (options.json) writeFileSync(path.resolve(root, options.json), `${JSON.stringify(result, null, 2)}\n`, 'utf8');
    console.log(`OPS-72 FINAL DECISION PASS decision=${result.decision} promotion=${result.promotionDecision} observations=${result.observations}`);
    return 0;
  } catch (error) {
    console.error(`OPS-72 final decision failed: ${error.message}`);
    return 2;
  }
}

const invoked = process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invoked) process.exitCode = main();
