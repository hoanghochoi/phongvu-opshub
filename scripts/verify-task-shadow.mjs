#!/usr/bin/env node

import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { EXIT_CODES, parseArgs, verifyTask } from './verify-task.mjs';

const PLAN_ONLY_SCHEMA_VERSION = 3;
const EXECUTION_CANARY_SCHEMA_VERSION = 4;
const DEFAULT_COHORT_ID = 'ops72-shadow-v2';
const EXECUTION_CANARY_COHORT_ID = 'ops72-execution-canary-v1';
const PLAN_ONLY_MODE = 'plan-only';
const EXECUTION_CANARY_MODE = 'execution-canary';

function shadowOptions(options, { executionMode, full }) {
  return {
    base: options.base ?? null,
    profiles: options.profiles ?? [],
    full: Boolean(full),
    // The canary executes only the affected/auto-selected lane. The full
    // ladder remains a dry-run comparator so this workflow cannot replace or
    // weaken existing blocking checks.
    dryRun: Boolean(options.dryRun) || executionMode !== EXECUTION_CANARY_MODE || Boolean(full),
  };
}

function externalRerunCount(options = {}) {
  if (Number.isInteger(options.externalRerunCount) && options.externalRerunCount >= 0) {
    return options.externalRerunCount;
  }
  const raw = process.env.OPSHUB_SHADOW_EXTERNAL_RERUN_COUNT;
  const attemptRaw = process.env.OPSHUB_SHADOW_RUN_ATTEMPT;
  if (attemptRaw) {
    const attempt = Number.parseInt(attemptRaw, 10);
    if (Number.isInteger(attempt) && attempt >= 1) return attempt - 1;
  }
  if (!raw) return 0;
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isInteger(parsed) || parsed < 0) return 0;
  return parsed;
}

function classificationForExitCode(exitCode) {
  if (exitCode === EXIT_CODES.CONTRACT) return 'contract-failure';
  if (exitCode === EXIT_CODES.PRODUCT_FAILURE) return 'product-failure';
  if (exitCode === EXIT_CODES.STALE) return 'stale-proof';
  if (exitCode === EXIT_CODES.ENVIRONMENT) return 'environment-failure';
  return 'shadow-observation';
}

function observedExitCode(command, fallbackExitCode) {
  if (command?.status === 'environment-failure') return EXIT_CODES.ENVIRONMENT;
  if (command?.status === 'product-failure' || command?.status === 'failed') {
    return EXIT_CODES.PRODUCT_FAILURE;
  }
  return fallbackExitCode;
}

function queuedAt(nowMs) {
  const configured = process.env.OPSHUB_SHADOW_QUEUED_AT_UTC;
  const parsed = configured ? Date.parse(configured) : Number.NaN;
  if (!Number.isNaN(parsed)) {
    return {
      value: new Date(parsed).toISOString(),
      source: 'workflow-run-started-at',
    };
  }
  return {
    value: new Date(nowMs).toISOString(),
    source: 'local-invocation',
  };
}

function retryCount(run) {
  return (run?.result?.result?.commands || []).reduce(
    (total, command) => total + Math.max(0, Number(command.attempt || 1) - 1),
    0,
  );
}

function firstActionableFailure(run, startedMs, elapsedBeforeMs = 0) {
  if (!run || run.exitCode === EXIT_CODES.PASS) return null;
  const durationMs = Number.isFinite(run.result?.durationMs)
    ? Math.max(0, Math.round(run.result.durationMs))
    : 0;
  const elapsedMs = elapsedBeforeMs + durationMs;
  const command = (run.result?.result?.commands || []).find(
    (entry) => !['passed', 'planned'].includes(entry.status),
  );
  return {
    category: classificationForExitCode(run.exitCode),
    exitCode: run.exitCode,
    commandId: command?.id || null,
    observedAtUtc: new Date(startedMs + elapsedMs).toISOString(),
    elapsedMs,
  };
}

function firstObservedFailure(run, startedMs, elapsedBeforeMs = 0) {
  if (!run) return null;
  const commands = run.result?.result?.commands || [];
  let elapsedMs = elapsedBeforeMs;
  for (const command of commands) {
    elapsedMs += Math.max(0, Number(command.durationMs || 0));
    if (['passed', 'planned'].includes(command.status)) continue;
    const exitCode = observedExitCode(command, run.exitCode);
    return {
      category: classificationForExitCode(exitCode),
      exitCode,
      commandId: command.id || null,
      observedAtUtc: new Date(startedMs + elapsedMs).toISOString(),
      elapsedMs,
    };
  }
  if (run.exitCode === EXIT_CODES.PASS) return null;
  return {
    category: classificationForExitCode(run.exitCode),
    exitCode: run.exitCode,
    commandId: null,
    observedAtUtc: new Date(startedMs + elapsedMs).toISOString(),
    elapsedMs,
  };
}

function durationMs(run) {
  return Number.isFinite(run?.result?.durationMs)
    ? Math.max(0, Math.round(run.result.durationMs))
    : 0;
}

function buildTelemetry({ queued, startedMs, completedMs, auto, full, executionMode, options }) {
  const autoRetryCount = retryCount(auto);
  const fullRetryCount = retryCount(full);
  const autoDurationMs = durationMs(auto);
  const fullDurationMs = durationMs(full);
  const commandRetryCount = autoRetryCount + fullRetryCount;
  const reruns = externalRerunCount(options);
  const isExecutionCanary = executionMode === EXECUTION_CANARY_MODE;
  const autoFailure = firstActionableFailure(auto, startedMs);
  const fullFailure = firstActionableFailure(full, startedMs, autoDurationMs);
  const autoObservedFailure = firstObservedFailure(auto, startedMs);
  const fullObservedFailure = firstObservedFailure(
    full,
    startedMs,
    autoDurationMs,
  );
  return {
    schemaVersion: isExecutionCanary
      ? EXECUTION_CANARY_SCHEMA_VERSION
      : PLAN_ONLY_SCHEMA_VERSION,
    cohortId: process.env.OPSHUB_SHADOW_COHORT_ID || (isExecutionCanary
      ? EXECUTION_CANARY_COHORT_ID
      : DEFAULT_COHORT_ID),
    queuedAtUtc: queued.value,
    startedAtUtc: new Date(startedMs).toISOString(),
    completedAtUtc: new Date(completedMs).toISOString(),
    queueDurationMs: Math.max(0, startedMs - Date.parse(queued.value)),
    executionDurationMs: Math.max(0, completedMs - startedMs),
    executionMode,
    autoDurationMs,
    fullDurationMs,
    // The selected-profile result is the first actionable decision. The full
    // ladder is an observational comparator and must not inflate decision
    // latency or be mistaken for the user's blocking path.
    decisionDurationMs: autoDurationMs,
    queueTimestampSource: queued.source,
    // retryCount is retained for schema-v3 compatibility. New canary
    // consumers must use the explicitly named fields below.
    retryCount: commandRetryCount,
    commandRetryCount,
    externalRerunCount: reruns,
    autoRetryCount,
    fullRetryCount,
    firstActionableFailure: autoFailure || fullFailure,
    autoFirstObservedFailure: autoObservedFailure,
    fullFirstObservedFailure: fullObservedFailure,
    firstObservedFailure: autoObservedFailure || fullObservedFailure,
    measurementEligibility: isExecutionCanary
      ? {
        retryReduction: true,
        timeToActionableFailure: true,
        reasonCode: 'execution-canary-auto-only',
      }
      : {
        retryReduction: false,
        timeToActionableFailure: false,
        reasonCode: 'plan-only-shadow',
      },
  };
}

export function buildShadowReport({
  root,
  options = {},
  verifyTaskFn = verifyTask,
} = {}) {
  const started = Date.now();
  const queued = queuedAt(started);
  const executionMode = options.executionMode || PLAN_ONLY_MODE;
  if (![PLAN_ONLY_MODE, EXECUTION_CANARY_MODE].includes(executionMode)) {
    throw new Error(`Unsupported shadow execution mode: ${executionMode}`);
  }
  const auto = verifyTaskFn({
    root,
    options: shadowOptions(options, { executionMode, full: false }),
  });
  const full = verifyTaskFn({
    root,
    options: {
      ...shadowOptions(options, { executionMode, full: true }),
      profiles: [],
      full: true,
    },
  });
  const autoResult = auto.result || {};
  const fullResult = full.result || {};
  const autoProfiles = autoResult.selectedProfiles || [];
  const fullProfiles = fullResult.selectedProfiles || [];
  const autoConsumers = autoResult.affectedConsumers || [];
  const fullConsumers = fullResult.affectedConsumers || [];
  const omittedProfiles = fullProfiles.filter((id) => !autoProfiles.includes(id));
  const omittedConsumers = fullConsumers.filter((consumer) => !autoConsumers.includes(consumer));
  const exitCode = auto.exitCode !== EXIT_CODES.PASS
    ? auto.exitCode
    : full.exitCode !== EXIT_CODES.PASS
      ? full.exitCode
      : EXIT_CODES.PASS;
  const completed = Date.now();
  const telemetry = buildTelemetry({
    queued,
    startedMs: started,
    completedMs: completed,
    auto,
    full,
    executionMode,
    options,
  });
  const schemaVersion = executionMode === EXECUTION_CANARY_MODE
    ? EXECUTION_CANARY_SCHEMA_VERSION
    : PLAN_ONLY_SCHEMA_VERSION;

  return {
    schemaVersion,
    mode: 'shadow',
    executionMode,
    baseSha: autoResult.baseSha ?? null,
    headSha: autoResult.headSha ?? null,
    changedPaths: autoResult.changedPaths || fullResult.changedPaths || [],
    autoSelectedProfiles: autoProfiles,
    autoAffectedConsumers: autoConsumers,
    fullProfiles,
    fullAffectedConsumers: fullConsumers,
    omittedProfiles,
    omittedConsumers,
    unmatchedPaths: autoResult.result?.error?.startsWith('No verification profile owns changed path(s):')
      ? autoResult.result.error.split('\n').slice(1)
      : [],
    autoExitCode: auto.exitCode,
    fullExitCode: full.exitCode,
    status: exitCode === EXIT_CODES.PASS ? 'passed' : 'failed',
    classification: exitCode === EXIT_CODES.PASS
      ? 'shadow-observation'
      : exitCode === EXIT_CODES.CONTRACT
        ? 'contract-failure'
        : exitCode === EXIT_CODES.PRODUCT_FAILURE
          ? 'product-failure'
          : exitCode === EXIT_CODES.STALE
            ? 'stale-proof'
            : 'environment-failure',
    fingerprint: autoResult.fingerprint || { before: null, after: null, stale: false },
    commandDefinitions: autoResult.commandDefinitions || [],
    durationMs: completed - started,
    blockingChecksUnchanged: true,
    retryPolicy: autoResult.result?.retryPolicy || null,
    telemetry,
    metrics: {
      firstActionableFailure: telemetry.firstActionableFailure,
      firstObservedFailure: telemetry.firstObservedFailure,
      // Existing plan-only artifacts retain the historical internal-retry
      // field. Execution-canary artifacts expose workflow reruns separately.
      reruns: executionMode === EXECUTION_CANARY_MODE
        ? telemetry.externalRerunCount
        : telemetry.retryCount,
      humanIntervention: false,
      falsePositive: null,
      falseNegative: null,
      requiresCanaryReview: true,
      measurementEligibility: telemetry.measurementEligibility,
    },
  };
}

function help() {
  return [
    'Usage: node scripts/verify-task-shadow.mjs --base <git-ref> [--execution-canary] [--json <path>]',
    '',
    'Runs the additive changed-path profile selection in dry-run shadow mode and',
    'compares it with the full profile ladder. --execution-canary executes only',
    'the auto-selected lane; it never replaces or weakens blocking checks.',
  ].join('\n');
}

function parseShadowArgs(argv) {
  const executionCanary = argv.includes('--execution-canary');
  const filtered = argv.filter((argument) => argument !== '--execution-canary');
  return {
    ...parseArgs(filtered),
    executionMode: executionCanary ? EXECUTION_CANARY_MODE : PLAN_ONLY_MODE,
  };
}

export function main(argv = process.argv.slice(2), { root = process.cwd() } = {}) {
  const started = Date.now();
  const queued = queuedAt(started);
  let options;
  try {
    options = parseShadowArgs(argv);
    if (options.help) {
      console.log(help());
      return EXIT_CODES.PASS;
    }
    const report = buildShadowReport({ root, options });
    if (options.json) {
      const target = path.resolve(root, options.json);
      mkdirSync(path.dirname(target), { recursive: true });
      writeFileSync(target, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
    }
    console.log(JSON.stringify(report, null, 2));
    return report.status === 'passed' ? EXIT_CODES.PASS : report.autoExitCode || report.fullExitCode;
  } catch (error) {
    const code = Number.isInteger(error?.code) ? error.code : EXIT_CODES.ENVIRONMENT;
    const completed = Date.now();
    const report = {
      schemaVersion: PLAN_ONLY_SCHEMA_VERSION,
      mode: 'shadow',
      executionMode: PLAN_ONLY_MODE,
      status: 'failed',
      classification: code === EXIT_CODES.CONTRACT ? 'contract-failure' : 'environment-failure',
      autoExitCode: code,
      fullExitCode: null,
      error: String(error?.message || error).slice(0, 500),
      telemetry: buildTelemetry({
        queued,
        startedMs: started,
        completedMs: completed,
        auto: { exitCode: code, result: {} },
        full: null,
        executionMode: PLAN_ONLY_MODE,
        options: {},
      }),
    };
    if (options?.json) {
      const target = path.resolve(root, options.json);
      mkdirSync(path.dirname(target), { recursive: true });
      writeFileSync(target, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
    }
    console.error(JSON.stringify(report, null, 2));
    return code;
  }
}

const invoked = process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invoked) process.exitCode = main();
