#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import {
  SCENARIOS,
  classificationForExitCode,
  sha256,
} from './collect-ops72-failure-injection.mjs';

const DEFAULT_INPUT = 'docs/migrations/ops-72-failure-injection-cohort.json';
const SHA_RE = /^[0-9a-f]{40}$/i;
const ABSOLUTE_PATH_RE = /(?:[A-Za-z]:[\\/]|(?:^|[\s"'])\/(?:Users|home|tmp|workspace|app)\/)/i;

export const EXIT_CODES = Object.freeze({ PASS: 0, CONTRACT: 2, ENVIRONMENT: 5 });

class ValidationError extends Error {
  constructor(message) {
    super(message);
    this.code = EXIT_CODES.CONTRACT;
  }
}

function fail(message) {
  throw new ValidationError(message);
}

function expectedScenario(id) {
  return SCENARIOS.find((scenario) => scenario.id === id) || null;
}

function assertSha(value, label) {
  if (!SHA_RE.test(String(value || '')) || /^0+$/.test(String(value))) {
    fail(`${label} phải là SHA commit hợp lệ.`);
  }
}

function assertRun(run, label) {
  if (!run || typeof run !== 'object') fail(`${label} thiếu observed run.`);
  for (const key of ['durationMs', 'decisionLatencyMs']) {
    if (!Number.isFinite(run[key]) || run[key] < 0) fail(`${label}.${key} không hợp lệ.`);
  }
  if (!Number.isInteger(run.retryCount) || run.retryCount < 0) {
    fail(`${label}.retryCount không hợp lệ.`);
  }
  if (![0, 2, 3, 4, 5].includes(run.exitCode)) {
    fail(`${label}.exitCode không thuộc failure ladder.`);
  }
  if (run.classification !== classificationForExitCode(run.exitCode)) {
    fail(`${label}.classification không khớp exit code.`);
  }
  if (!Number.isInteger(run.commandAttempts) || run.commandAttempts < 0) {
    fail(`${label}.commandAttempts không hợp lệ.`);
  }
}

function rawSha(root, relativeFile) {
  const target = path.resolve(root, relativeFile);
  const rootRelative = path.relative(root, target);
  if (
    rootRelative === '..' ||
    rootRelative.startsWith(`..${path.sep}`) ||
    path.isAbsolute(rootRelative)
  ) {
    fail(`Raw artifact path thoát root: ${relativeFile}`);
  }
  if (!existsSync(target)) return null;
  return createHash('sha256').update(readFileSync(target)).digest('hex');
}

function stableScenario(scenario) {
  const hashableRun = (run) => ({
    durationMs: run.durationMs,
    decisionLatencyMs: run.decisionLatencyMs,
    firstObservedFailureMs: run.firstObservedFailureMs,
    firstObservedFailure: run.firstObservedFailure,
    retryCount: run.retryCount,
    exitCode: run.exitCode,
    classification: run.classification,
    status: run.status,
    commandAttempts: run.commandAttempts,
    fingerprintStale: Boolean(run.fingerprint?.stale),
  });
  const hashableObserved = (observed) => ({
    baseline: {
      auto: hashableRun(observed.baseline.auto),
      full: hashableRun(observed.baseline.full),
      autoExitCode: observed.baseline.autoExitCode,
      fullExitCode: observed.baseline.fullExitCode,
      autoRetryCount: observed.baseline.autoRetryCount,
      fullRetryCount: observed.baseline.fullRetryCount,
    },
    candidate: {
      auto: hashableRun(observed.candidate.auto),
      full: hashableRun(observed.candidate.full),
      autoExitCode: observed.candidate.autoExitCode,
      fullExitCode: observed.candidate.fullExitCode,
      autoRetryCount: observed.candidate.autoRetryCount,
      fullRetryCount: observed.candidate.fullRetryCount,
    },
  });
  return {
    scenarioDefinitionVersion: 1,
    id: scenario.id,
    faultClass: scenario.faultClass,
    changedPath: scenario.fixture?.changedPaths?.[0] || null,
    commandId: scenario.injection?.commandId || null,
    baseline: scenario.injection?.baseline,
    candidate: scenario.injection?.candidate,
    observed: hashableObserved(scenario.observed),
    invariants: scenario.invariants,
  };
}

export function validateFailureInjectionCohort(document, { rawRoot = null } = {}) {
  if (!document || typeof document !== 'object') fail('Artifact không phải object.');
  if (document.formatVersion !== 1) fail('formatVersion phải là 1.');
  if (document.issue !== 'OPS-126') fail('Artifact không thuộc OPS-126.');
  if (document.mode !== 'controlled-failure-injection') fail('mode không hợp lệ.');
  assertSha(document.source?.repositoryRevision, 'source.repositoryRevision');
  if (document.source?.scenarioDefinitionVersion !== 1) {
    fail('scenarioDefinitionVersion không hợp lệ.');
  }
  if (document.source?.scenarioDefinitionSha256 !== sha256(SCENARIOS)) {
    fail('scenarioDefinitionSha256 không khớp source definition.');
  }
  if (document.aggregate?.metricBasis !== 'controlled-decision-latency') {
    fail('metricBasis phải nêu rõ controlled-decision-latency.');
  }
  if (document.aggregate?.targetStatus !== 'controlled-evidence-only') {
    fail('targetStatus phải là controlled-evidence-only.');
  }
  if (document.aggregate?.promotionDecision !== 'do-not-promote') {
    fail('promotionDecision phải là do-not-promote.');
  }
  if (!Array.isArray(document.scenarios) || document.scenarios.length !== 5) {
    fail('Artifact phải có đúng 5 scenarios.');
  }

  const seen = new Set();
  for (const scenario of document.scenarios) {
    if (seen.has(scenario.id)) fail(`Scenario trùng: ${scenario.id}`);
    seen.add(scenario.id);
    const expected = expectedScenario(scenario.id);
    if (!expected) fail(`Scenario không được khai báo: ${scenario.id}`);
    const changedPath = scenario.fixture?.changedPaths?.[0];
    if (changedPath !== expected.changedPath) {
      fail(`changedPath không khớp: ${scenario.id}`);
    }
    assertSha(scenario.fixture?.baseSha, `${scenario.id}.fixture.baseSha`);
    assertSha(scenario.fixture?.headSha, `${scenario.id}.fixture.headSha`);
    for (const variant of ['baseline', 'candidate']) {
      assertRun(scenario.observed?.[variant]?.auto, `${scenario.id}.${variant}.auto`);
      assertRun(scenario.observed?.[variant]?.full, `${scenario.id}.${variant}.full`);
      if (scenario.observed[variant].autoRetryCount !== scenario.observed[variant].auto.retryCount) {
        fail(`${scenario.id}.${variant} auto retry mismatch.`);
      }
      if (scenario.observed[variant].fullRetryCount !== scenario.observed[variant].full.retryCount) {
        fail(`${scenario.id}.${variant} full retry mismatch.`);
      }
    }
    if (scenario.injection?.baseline?.mode !== expected.baseline.mode) {
      fail(`baseline injection mode không khớp: ${scenario.id}`);
    }
    if (scenario.injection?.candidate?.mode !== expected.candidate.mode) {
      fail(`candidate injection mode không khớp: ${scenario.id}`);
    }
    if (scenario.observed.candidate.auto.retryCount > 1) {
      fail(`Candidate retry vượt quá một lần: ${scenario.id}`);
    }
    if (
      scenario.faultClass === 'stale-proof' &&
      (scenario.observed.candidate.auto.exitCode !== 4 ||
        scenario.invariants?.staleProofRejected !== true)
    ) {
      fail('Stale proof phải bị reject với exit code 4.');
    }
    if (
      scenario.faultClass === 'product-failure' &&
      (scenario.observed.candidate.auto.exitCode !== 3 ||
        scenario.observed.candidate.auto.retryCount !== 0 ||
        scenario.invariants?.productFailureDidNotRetryToGreen !== true)
    ) {
      fail('Product failure không được retry-to-green.');
    }
    if (
      scenario.faultClass === 'contract/unknown-path' &&
      (scenario.observed.candidate.auto.exitCode !== 2 ||
        scenario.observed.candidate.auto.commandAttempts !== 0)
    ) {
      fail('Unknown path phải fail contract trước command execution.');
    }
    for (const raw of scenario.rawArtifacts || []) {
      if (!/^tmp\/ops-126-shadow\//.test(raw.file)) {
        fail(`Raw artifact path không thuộc allowlist: ${raw.file}`);
      }
      if (rawRoot) {
        const actual = rawSha(rawRoot, raw.file);
        if (!actual || actual !== raw.sha256) {
          fail(`Raw artifact hash không khớp: ${raw.file}`);
        }
      }
    }
    if (scenario.scenarioHash !== sha256(stableScenario(scenario))) {
      fail(`Scenario hash không khớp: ${scenario.id}`);
    }
  }
  if (seen.size !== SCENARIOS.length) fail('Thiếu scenario trong artifact.');

  const baseline = document.scenarios.map((scenario) => scenario.observed.baseline.auto);
  const candidate = document.scenarios.map((scenario) => scenario.observed.candidate.auto);
  const sortedBaseline = baseline.map((run) => run.decisionLatencyMs).sort((a, b) => a - b);
  const sortedCandidate = candidate.map((run) => run.decisionLatencyMs).sort((a, b) => a - b);
  const baselineMedian = sortedBaseline[2];
  const candidateMedian = sortedCandidate[2];
  const baselineRetries = baseline.reduce((total, run) => total + run.retryCount, 0);
  const candidateRetries = candidate.reduce((total, run) => total + run.retryCount, 0);
  const reduction = Number((((baselineMedian - candidateMedian) / baselineMedian) * 100).toFixed(2));
  const rerunReduction = Number((((baselineRetries - candidateRetries) / baselineRetries) * 100).toFixed(2));
  const aggregate = document.aggregate;
  const expectedAggregate = {
    scenarioCount: 5,
    baselineMedianDecisionLatencyMs: baselineMedian,
    candidateMedianDecisionLatencyMs: candidateMedian,
    controlledDecisionLatencyReductionPercent: reduction,
    baselineRetryCount: baselineRetries,
    candidateRetryCount: candidateRetries,
    rerunReductionPercent: rerunReduction,
    staleProofRejections: candidate.filter((run) => run.exitCode === 4 && run.fingerprint?.stale).length,
    productFailureRetries: candidate.reduce((total, run) => total + (run.exitCode === 3 ? run.retryCount : 0), 0),
  };
  for (const [key, value] of Object.entries(expectedAggregate)) {
    if (aggregate[key] !== value) fail(`Aggregate không khớp: ${key}`);
  }
  if (ABSOLUTE_PATH_RE.test(JSON.stringify(document))) {
    fail('Artifact chứa absolute path không được sanitize.');
  }
  return {
    valid: true,
    cohortId: document.cohortId,
    scenarioCount: document.scenarios.length,
    targetStatus: aggregate.targetStatus,
    promotionDecision: aggregate.promotionDecision,
    controlledDecisionLatencyReductionPercent: reduction,
    rerunReductionPercent: rerunReduction,
  };
}

function parseArgs(argv) {
  const options = { input: DEFAULT_INPUT, rawRoot: null, help: false };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--input' || argument === '--raw-root') {
      const value = argv[index + 1];
      if (!value || value.startsWith('--')) fail(`${argument} cần một path.`);
      if (argument === '--input') options.input = value;
      else options.rawRoot = value;
      index += 1;
      continue;
    }
    if (argument === '--help' || argument === '-h') {
      options.help = true;
      continue;
    }
    fail(`Tham số không hỗ trợ: ${argument}`);
  }
  return options;
}

function main(argv = process.argv.slice(2), { root = process.cwd() } = {}) {
  const options = parseArgs(argv);
  if (options.help) {
    console.log(
      'Usage: node scripts/verify-ops72-failure-injection.mjs [--input <path>] [--raw-root <path>]',
    );
    return EXIT_CODES.PASS;
  }
  const document = JSON.parse(readFileSync(path.resolve(root, options.input), 'utf8'));
  const rawRoot = options.rawRoot ? path.resolve(root, options.rawRoot) : null;
  console.log(JSON.stringify(validateFailureInjectionCohort(document, { rawRoot }), null, 2));
  return EXIT_CODES.PASS;
}

const invoked =
  process.argv[1] &&
  pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invoked) {
  try {
    process.exitCode = main();
  } catch (error) {
    const code = Number.isInteger(error.code) ? error.code : EXIT_CODES.ENVIRONMENT;
    console.error(`OPS-126 failure-injection validation failed: ${error.message}`);
    process.exitCode = code;
  }
}
