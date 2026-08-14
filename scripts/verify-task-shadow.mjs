#!/usr/bin/env node

import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { EXIT_CODES, parseArgs, verifyTask } from './verify-task.mjs';

const SHADOW_SCHEMA_VERSION = 2;
const DEFAULT_COHORT_ID = 'ops72-shadow-v2';

function shadowOptions(options) {
  return {
    base: options.base ?? null,
    profiles: options.profiles ?? [],
    full: Boolean(options.full),
    dryRun: true,
  };
}

function classificationForExitCode(exitCode) {
  if (exitCode === EXIT_CODES.CONTRACT) return 'contract-failure';
  if (exitCode === EXIT_CODES.PRODUCT_FAILURE) return 'product-failure';
  if (exitCode === EXIT_CODES.STALE) return 'stale-proof';
  if (exitCode === EXIT_CODES.ENVIRONMENT) return 'environment-failure';
  return 'shadow-observation';
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

function durationMs(run) {
  return Number.isFinite(run?.result?.durationMs)
    ? Math.max(0, Math.round(run.result.durationMs))
    : 0;
}

function buildTelemetry({ queued, startedMs, completedMs, auto, full }) {
  const autoRetryCount = retryCount(auto);
  const fullRetryCount = retryCount(full);
  const autoFailure = firstActionableFailure(auto, startedMs);
  const fullFailure = firstActionableFailure(full, startedMs, durationMs(auto));
  return {
    schemaVersion: SHADOW_SCHEMA_VERSION,
    cohortId: process.env.OPSHUB_SHADOW_COHORT_ID || DEFAULT_COHORT_ID,
    queuedAtUtc: queued.value,
    startedAtUtc: new Date(startedMs).toISOString(),
    completedAtUtc: new Date(completedMs).toISOString(),
    queueDurationMs: Math.max(0, startedMs - Date.parse(queued.value)),
    executionDurationMs: Math.max(0, completedMs - startedMs),
    queueTimestampSource: queued.source,
    retryCount: autoRetryCount + fullRetryCount,
    autoRetryCount,
    fullRetryCount,
    firstActionableFailure: autoFailure || fullFailure,
  };
}

export function buildShadowReport({
  root,
  options = {},
  verifyTaskFn = verifyTask,
} = {}) {
  const started = Date.now();
  const queued = queuedAt(started);
  const auto = verifyTaskFn({ root, options: shadowOptions(options) });
  const full = verifyTaskFn({
    root,
    options: { ...shadowOptions(options), profiles: [], full: true },
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
  });

  return {
    schemaVersion: SHADOW_SCHEMA_VERSION,
    mode: 'shadow',
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
      reruns: telemetry.retryCount,
      humanIntervention: false,
      falsePositive: null,
      falseNegative: null,
      requiresCanaryReview: true,
    },
  };
}

function help() {
  return [
    'Usage: node scripts/verify-task-shadow.mjs --base <git-ref> [--json <path>]',
    '',
    'Runs the additive changed-path profile selection in dry-run shadow mode and',
    'compares it with the full profile ladder. Existing blocking checks are not',
    'replaced or weakened.',
  ].join('\n');
}

export function main(argv = process.argv.slice(2), { root = process.cwd() } = {}) {
  const started = Date.now();
  const queued = queuedAt(started);
  let options;
  try {
    options = parseArgs(argv);
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
      schemaVersion: SHADOW_SCHEMA_VERSION,
      mode: 'shadow',
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
