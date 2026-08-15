#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import {
  mkdirSync,
  mkdtempSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { verifyTask } from './verify-task.mjs';
import { buildShadowReport } from './verify-task-shadow.mjs';

const DEFAULT_OUTPUT = 'docs/migrations/ops-72-failure-injection-cohort.json';
const RAW_ROOT = 'tmp/ops-126-shadow';
const SCENARIO_DEFINITION_VERSION = 1;
const RETRY_POLICY = Object.freeze({
  maxInfrastructureRetries: 1,
  fingerprintStableRequired: true,
  productFailureRetries: 0,
});

// Controlled fixtures exercise the real verifier and retry/fingerprint code.
// Delay values are calibration inputs, never live CI measurements.
export const SCENARIOS = Object.freeze([
  {
    id: 'environment-dependency-retry',
    faultClass: 'environment/dependency-retry',
    changedPath: 'scripts/run-with-toolchain.mjs',
    commandId: 'toolchain-preflight',
    baseline: { delayMs: 1800, mode: 'retry-pass' },
    candidate: { delayMs: 900, mode: 'pass' },
  },
  {
    id: 'missing-command-tool',
    faultClass: 'environment/missing-command',
    changedPath: 'scripts/verification-profiles.mjs',
    commandId: 'runner-command',
    baseline: { delayMs: 1500, mode: 'retry-pass' },
    candidate: { delayMs: 700, mode: 'pass' },
  },
  {
    id: 'stale-proof',
    faultClass: 'stale-proof',
    changedPath: 'tests/verification/verify-task.test.mjs',
    commandId: 'fingerprint-recheck',
    baseline: { delayMs: 1600, mode: 'stale' },
    candidate: { delayMs: 800, mode: 'stale' },
  },
  {
    id: 'product-failure',
    faultClass: 'product-failure',
    changedPath: 'lib/feature/example.dart',
    commandId: 'product-test',
    baseline: { delayMs: 1300, mode: 'product-failure' },
    candidate: { delayMs: 550, mode: 'product-failure' },
  },
  {
    id: 'contract-unknown-path',
    faultClass: 'contract/unknown-path',
    changedPath: 'unknown/unowned.path',
    commandId: 'path-contract',
    baseline: { delayMs: 900, mode: 'contract-failure' },
    candidate: { delayMs: 300, mode: 'contract-failure' },
  },
]);

function fail(message) {
  const error = new Error(message);
  error.code = 2;
  throw error;
}

function stableJson(value) {
  if (Array.isArray(value)) return value.map(stableJson);
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((key) => [key, stableJson(value[key])]),
    );
  }
  return value;
}

export function sha256(value) {
  return createHash('sha256')
    .update(JSON.stringify(stableJson(value)))
    .digest('hex');
}

export function classificationForExitCode(exitCode) {
  if (exitCode === 2) return 'contract-failure';
  if (exitCode === 3) return 'product-failure';
  if (exitCode === 4) return 'stale-proof';
  if (exitCode === 5) return 'environment-failure';
  return 'shadow-observation';
}

function observedExitCode(command, fallbackExitCode) {
  if (command?.status === 'environment-failure') return 5;
  if (command?.status === 'product-failure' || command?.status === 'failed') return 3;
  return fallbackExitCode;
}

function git(root, argv) {
  return execFileSync('git', argv, {
    cwd: root,
    encoding: 'utf8',
    windowsHide: true,
  }).trim();
}

function writeFixtureFile(root, relativePath, content) {
  const target = path.resolve(root, relativePath);
  const relative = path.relative(root, target);
  if (
    relative === '..' ||
    relative.startsWith(`..${path.sep}`) ||
    path.isAbsolute(relative)
  ) {
    fail(`Fixture path escapes root: ${relativePath}`);
  }
  mkdirSync(path.dirname(target), { recursive: true });
  writeFileSync(target, content, 'utf8');
}

function createFixture(scenario) {
  const root = mkdtempSync(path.join(os.tmpdir(), `opshub-ops126-${scenario.id}-`));
  git(root, ['init', '--quiet']);
  git(root, ['config', 'user.name', 'ops126-controlled-fixture']);
  git(root, ['config', 'user.email', 'ops126-controlled-fixture@example.invalid']);
  writeFixtureFile(root, 'README.md', '# controlled fixture\n');
  for (const directory of ['backend-nest', 'backend-go', 'deploy']) {
    mkdirSync(path.join(root, directory), { recursive: true });
  }
  git(root, ['add', '--all']);
  git(root, ['commit', '--quiet', '-m', 'controlled fixture baseline']);
  const baseSha = git(root, ['rev-parse', 'HEAD']).toLowerCase();
  writeFixtureFile(root, scenario.changedPath, `controlled ${scenario.id}\n`);
  git(root, ['add', '--all']);
  git(root, ['commit', '--quiet', '-m', `controlled ${scenario.id}`]);
  const headSha = git(root, ['rev-parse', 'HEAD']).toLowerCase();
  return { root, baseSha, headSha };
}

function restoreScenarioPath(root, scenario) {
  execFileSync('git', ['restore', '--worktree', '--', scenario.changedPath], {
    cwd: root,
    windowsHide: true,
  });
}

function controlledCommandRunner({ root, scenario, variant, state }) {
  const injection = scenario[variant];
  return (_commandRoot, command) => {
    state.calls += 1;
    const first = state.calls === 1;
    if (injection.mode === 'retry-pass' && first) {
      return {
        id: command.id,
        executable: command.executable,
        argv: command.argv,
        status: 'environment-failure',
        exitCode: 5,
        durationMs: injection.delayMs,
        error: 'controlled dependency materialization failure',
      };
    }
    if (injection.mode === 'stale' && first) {
      writeFixtureFile(root, scenario.changedPath, `stale mutation ${scenario.id}\n`);
      return {
        id: command.id,
        executable: command.executable,
        argv: command.argv,
        status: 'environment-failure',
        exitCode: 5,
        durationMs: injection.delayMs,
        error: 'controlled stale-proof mutation',
      };
    }
    if (injection.mode === 'product-failure' && first) {
      return {
        id: command.id,
        executable: command.executable,
        argv: command.argv,
        status: 'failed',
        exitCode: 3,
        durationMs: injection.delayMs,
        error: 'controlled product failure',
      };
    }
    return {
      id: command.id,
      executable: command.executable,
      argv: command.argv,
      status: 'passed',
      exitCode: 0,
      durationMs: first ? injection.delayMs : 0,
    };
  };
}

function runSummary(run, fallbackDelayMs) {
  const commands = run?.result?.result?.commands || [];
  const retryCount = commands.reduce(
    (total, command) => total + Math.max(0, Number(command.attempt || 1) - 1),
    0,
  );
  let elapsedMs = 0;
  let firstObservedFailureMs = null;
  let firstObservedFailure = null;
  for (const command of commands) {
    elapsedMs += Math.max(0, Number(command.durationMs || 0));
    if (
      firstObservedFailureMs === null &&
      !['passed', 'planned'].includes(command.status)
    ) {
      firstObservedFailureMs = elapsedMs;
      const exitCode = observedExitCode(command, run.exitCode);
      firstObservedFailure = {
        category: classificationForExitCode(exitCode),
        exitCode,
        commandId: command.id || null,
        elapsedMs,
      };
    }
  }
  if (firstObservedFailureMs === null && run.exitCode !== 0 && commands.length === 0) {
    firstObservedFailureMs = fallbackDelayMs;
    firstObservedFailure = {
      category: classificationForExitCode(run.exitCode),
      exitCode: run.exitCode,
      commandId: null,
      elapsedMs: fallbackDelayMs,
    };
  }
  return {
    durationMs: elapsedMs || fallbackDelayMs,
    decisionLatencyMs: elapsedMs || fallbackDelayMs,
    firstObservedFailureMs,
    firstObservedFailure,
    retryCount,
    exitCode: run.exitCode,
    classification: classificationForExitCode(run.exitCode),
    status: run.result?.result?.status || 'unknown',
    commandAttempts: commands.length,
    fingerprint: run.result?.fingerprint || null,
  };
}

function runVariant(fixture, scenario, variant) {
  const calls = [];
  const report = buildShadowReport({
    root: fixture.root,
    options: { base: fixture.baseSha },
    verifyTaskFn: ({ root, options }) => {
      restoreScenarioPath(root, scenario);
      const state = { calls: 0 };
      const run = verifyTask({
        root,
        options: { ...options, dryRun: false },
        toolVersionFn: () => 'controlled-fixture',
        runCommandFn: controlledCommandRunner({
          root,
          scenario,
          variant,
          state,
        }),
      });
      calls.push({ full: Boolean(options.full), run });
      return run;
    },
  });
  const auto = calls.find((call) => !call.full)?.run;
  const full = calls.find((call) => call.full)?.run;
  if (!auto || !full || calls.length !== 2) {
    fail(`Scenario ${scenario.id} không tạo đủ auto/full report.`);
  }
  return {
    report,
    auto,
    full,
    autoSummary: runSummary(auto, scenario[variant].delayMs),
    fullSummary: runSummary(full, scenario[variant].delayMs),
  };
}

function rawArtifact(root, scenario, variant, value) {
  const relativeFile = `${RAW_ROOT}/${scenario.id}/${variant}.json`;
  const target = path.resolve(root, relativeFile);
  mkdirSync(path.dirname(target), { recursive: true });
  const bytes = Buffer.from(`${JSON.stringify(value, null, 2)}\n`, 'utf8');
  writeFileSync(target, bytes);
  return {
    file: relativeFile,
    sha256: createHash('sha256').update(bytes).digest('hex'),
  };
}

function median(values) {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0
    ? (sorted[middle - 1] + sorted[middle]) / 2
    : sorted[middle];
}

function reductionPercent(baseline, candidate) {
  if (!baseline) return null;
  return Number((((baseline - candidate) / baseline) * 100).toFixed(2));
}

function hashableRun(run) {
  return {
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
  };
}

function hashableObserved(observed) {
  return {
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
  };
}

function scenarioDocument(repositoryRoot, scenario) {
  const fixture = createFixture(scenario);
  try {
    const baseline = runVariant(fixture, scenario, 'baseline');
    const candidate = runVariant(fixture, scenario, 'candidate');
    const rawArtifacts = [
      rawArtifact(repositoryRoot, scenario, 'baseline', {
        report: baseline.report,
        auto: baseline.auto,
        full: baseline.full,
      }),
      rawArtifact(repositoryRoot, scenario, 'candidate', {
        report: candidate.report,
        auto: candidate.auto,
        full: candidate.full,
      }),
    ];
    const observed = {
      baseline: {
        auto: baseline.autoSummary,
        full: baseline.fullSummary,
        autoExitCode: baseline.report.autoExitCode,
        fullExitCode: baseline.report.fullExitCode,
        autoRetryCount: baseline.report.telemetry.autoRetryCount,
        fullRetryCount: baseline.report.telemetry.fullRetryCount,
      },
      candidate: {
        auto: candidate.autoSummary,
        full: candidate.fullSummary,
        autoExitCode: candidate.report.autoExitCode,
        fullExitCode: candidate.report.fullExitCode,
        autoRetryCount: candidate.report.telemetry.autoRetryCount,
        fullRetryCount: candidate.report.telemetry.fullRetryCount,
      },
    };
    const invariants = {
      productFailureDidNotRetryToGreen:
        scenario.faultClass === 'product-failure'
          ? observed.candidate.auto.exitCode === 3 &&
            observed.candidate.auto.retryCount === 0
          : true,
      staleProofRejected:
        scenario.faultClass === 'stale-proof' &&
        observed.candidate.auto.exitCode === 4 &&
        Boolean(observed.candidate.auto.fingerprint?.stale),
      candidateRetryCountBounded:
        observed.candidate.auto.retryCount <= RETRY_POLICY.maxInfrastructureRetries,
    };
    const stable = {
      scenarioDefinitionVersion: SCENARIO_DEFINITION_VERSION,
      id: scenario.id,
      faultClass: scenario.faultClass,
      changedPath: scenario.changedPath,
      commandId: scenario.commandId,
      baseline: scenario.baseline,
      candidate: scenario.candidate,
      observed: hashableObserved(observed),
      invariants,
    };
    return {
      id: scenario.id,
      faultClass: scenario.faultClass,
      fixture: {
        baseSha: fixture.baseSha,
        headSha: fixture.headSha,
        changedPaths: [scenario.changedPath],
      },
      injection: {
        commandId: scenario.commandId,
        baseline: scenario.baseline,
        candidate: scenario.candidate,
      },
      expected: {
        maxInfrastructureRetries: RETRY_POLICY.maxInfrastructureRetries,
        productFailureRetries: RETRY_POLICY.productFailureRetries,
      },
      observed,
      invariants,
      rawArtifacts,
      scenarioHash: sha256(stable),
    };
  } finally {
    rmSync(fixture.root, { recursive: true, force: true });
  }
}

export function collectFailureInjectionCohort({
  root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..'),
  output = path.join(root, DEFAULT_OUTPUT),
  revision = null,
} = {}) {
  const repositoryRoot = path.resolve(root);
  const scenarios = SCENARIOS.map((scenario) =>
    scenarioDocument(repositoryRoot, scenario),
  );
  const baselineAuto = scenarios.map((scenario) => scenario.observed.baseline.auto);
  const candidateAuto = scenarios.map((scenario) => scenario.observed.candidate.auto);
  const baselineMedian = median(baselineAuto.map((run) => run.decisionLatencyMs));
  const candidateMedian = median(candidateAuto.map((run) => run.decisionLatencyMs));
  const baselineRetries = baselineAuto.reduce(
    (total, run) => total + run.retryCount,
    0,
  );
  const candidateRetries = candidateAuto.reduce(
    (total, run) => total + run.retryCount,
    0,
  );
  const document = {
    formatVersion: 1,
    issue: 'OPS-126',
    mode: 'controlled-failure-injection',
    cohortId: 'ops126-controlled-v1',
    generatedAtUtc: new Date().toISOString(),
    source: {
      repositoryRevision: revision || git(repositoryRoot, ['rev-parse', 'HEAD']).toLowerCase(),
      scenarioDefinitionVersion: SCENARIO_DEFINITION_VERSION,
      scenarioDefinitionSha256: sha256(SCENARIOS),
    },
    scenarios,
    aggregate: {
      scenarioCount: scenarios.length,
      baselineMedianDecisionLatencyMs: baselineMedian,
      candidateMedianDecisionLatencyMs: candidateMedian,
      controlledDecisionLatencyReductionPercent: reductionPercent(
        baselineMedian,
        candidateMedian,
      ),
      baselineRetryCount: baselineRetries,
      candidateRetryCount: candidateRetries,
      rerunReductionPercent: reductionPercent(baselineRetries, candidateRetries),
      staleProofRejections: candidateAuto.filter(
        (run) => run.exitCode === 4 && Boolean(run.fingerprint?.stale),
      ).length,
      productFailureRetries: candidateAuto.reduce(
        (total, run) => total + (run.exitCode === 3 ? run.retryCount : 0),
        0,
      ),
      metricBasis: 'controlled-decision-latency',
      targetStatus: 'controlled-evidence-only',
      promotionDecision: 'do-not-promote',
    },
    interpretation: [
      'This artifact uses the real verifyTask and buildShadowReport seams with controlled command results.',
      'Delay values and candidate behavior are calibration fixtures, not representative live CI observations.',
      'The aggregate must not be used to promote the affected matrix or claim Phase 7B targets.',
    ],
  };
  const target = path.resolve(output);
  mkdirSync(path.dirname(target), { recursive: true });
  writeFileSync(target, `${JSON.stringify(document, null, 2)}\n`, 'utf8');
  return document;
}

function parseArgs(argv) {
  const options = { output: DEFAULT_OUTPUT, help: false };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--output') {
      const value = argv[index + 1];
      if (!value || value.startsWith('--')) fail('--output cần một path.');
      options.output = value;
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
      'Usage: node scripts/collect-ops72-failure-injection.mjs [--output <path>]',
    );
    return 0;
  }
  const document = collectFailureInjectionCohort({
    root,
    output: path.resolve(root, options.output),
  });
  console.log(
    JSON.stringify(
      {
        issue: document.issue,
        cohortId: document.cohortId,
        scenarioCount: document.aggregate.scenarioCount,
        targetStatus: document.aggregate.targetStatus,
        promotionDecision: document.aggregate.promotionDecision,
        controlledDecisionLatencyReductionPercent:
          document.aggregate.controlledDecisionLatencyReductionPercent,
        rerunReductionPercent: document.aggregate.rerunReductionPercent,
      },
      null,
      2,
    ),
  );
  return 0;
}

const invoked =
  process.argv[1] &&
  pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invoked) {
  try {
    process.exitCode = main();
  } catch (error) {
    console.error(`OPS-126 failure-injection collection failed: ${error.message}`);
    process.exitCode = Number.isInteger(error.code) ? error.code : 5;
  }
}
