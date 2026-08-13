#!/usr/bin/env node

import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { EXIT_CODES, parseArgs, verifyTask } from './verify-task.mjs';

function shadowOptions(options) {
  return {
    base: options.base ?? null,
    profiles: options.profiles ?? [],
    full: Boolean(options.full),
    dryRun: true,
  };
}

export function buildShadowReport({
  root,
  options = {},
  verifyTaskFn = verifyTask,
} = {}) {
  const started = Date.now();
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

  return {
    schemaVersion: 1,
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
    durationMs: Date.now() - started,
    blockingChecksUnchanged: true,
    retryPolicy: autoResult.result?.retryPolicy || null,
    metrics: {
      firstActionableFailure: null,
      reruns: 0,
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
    const report = {
      schemaVersion: 1,
      mode: 'shadow',
      status: 'failed',
      classification: code === EXIT_CODES.CONTRACT ? 'contract-failure' : 'environment-failure',
      autoExitCode: code,
      fullExitCode: null,
      error: String(error?.message || error).slice(0, 500),
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
