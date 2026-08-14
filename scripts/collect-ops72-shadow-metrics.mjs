#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { buildShadowReport } from './verify-task-shadow.mjs';

const SAMPLES = Object.freeze([
  { issue: 'OPS-68', pullRequest: 176, head: 'ee74d0efb9b16cda0725d8940b0a1e544d0ba006' },
  { issue: 'OPS-69A', pullRequest: 177, head: 'ed409276d71f1d8c093f07bf394a08446371a391' },
  { issue: 'OPS-69B', pullRequest: 178, head: 'e83c24bb7ae6cd83af379ec003818ad74b6fcbe0' },
  { issue: 'OPS-70', pullRequest: 179, head: 'ff8b9e9a1765d572a7ed5b72772f5c2b5ced4ea1' },
  { issue: 'OPS-71', pullRequest: 180, head: '6ff4899f631f55eb41c0a8b4f1b9a739138768fd' },
]);

function git(root, args, { allowFailure = false } = {}) {
  const result = execFileSync('git', args, {
    cwd: root,
    encoding: 'utf8',
    windowsHide: true,
    stdio: allowFailure ? ['ignore', 'pipe', 'pipe'] : ['ignore', 'pipe', 'pipe'],
  });
  return result.trim();
}

function removeWorktree(repositoryRoot, worktree) {
  const resolved = path.resolve(worktree);
  const allowedParent = path.resolve(path.join(repositoryRoot, '..', '.opshub-ops72-shadow-samples'));
  const relative = path.relative(allowedParent, resolved);
  if (relative.startsWith('..') || path.isAbsolute(relative)) {
    throw new Error(`Refusing to remove unexpected sample worktree: ${resolved}`);
  }
  execFileSync('git', ['worktree', 'remove', '--', resolved], {
    cwd: repositoryRoot,
    encoding: 'utf8',
    windowsHide: true,
  });
}

function sampleReport(repositoryRoot, sample, sampleRoot) {
  const parentSha = git(sampleRoot, ['rev-parse', `${sample.head}^`]);
  const sourceHead = git(sampleRoot, ['rev-parse', 'HEAD']);
  if (sourceHead.toLowerCase() !== sample.head.toLowerCase()) {
    throw new Error(`Sample ${sample.issue} checked out ${sourceHead}, expected ${sample.head}`);
  }
  const report = buildShadowReport({
    root: sampleRoot,
    options: { base: parentSha },
  });
  return {
    issue: sample.issue,
    pullRequest: sample.pullRequest,
    parentSha,
    headSha: sourceHead,
    changedPaths: report.changedPaths,
    autoSelectedProfiles: report.autoSelectedProfiles,
    fullProfiles: report.fullProfiles,
    omittedProfiles: report.omittedProfiles,
    autoAffectedConsumers: report.autoAffectedConsumers,
    omittedConsumers: report.omittedConsumers,
    autoExitCode: report.autoExitCode,
    fullExitCode: report.fullExitCode,
    status: report.status,
    classification: report.classification,
    unmatchedPaths: report.unmatchedPaths,
    fingerprint: report.fingerprint,
    commandDefinitions: report.commandDefinitions,
    blockingChecksUnchanged: report.blockingChecksUnchanged,
    retryPolicy: report.retryPolicy,
    telemetry: report.telemetry || null,
    metrics: report.metrics,
  };
}

export function collectShadowMetrics({
  root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..'),
  output = path.join(root, 'docs', 'migrations', 'ops-72-shadow-metrics.json'),
  samples = SAMPLES,
} = {}) {
  const repositoryRoot = path.resolve(root);
  const samplesRoot = path.resolve(path.join(repositoryRoot, '..', '.opshub-ops72-shadow-samples'));
  mkdirSync(samplesRoot, { recursive: true });
  const reports = [];
  try {
    for (const sample of samples) {
      const sampleRoot = path.join(samplesRoot, `${sample.issue.toLowerCase()}-${sample.pullRequest}`);
      execFileSync('git', ['worktree', 'add', '--detach', sampleRoot, sample.head], {
        cwd: repositoryRoot,
        encoding: 'utf8',
        windowsHide: true,
        stdio: ['ignore', 'pipe', 'pipe'],
      });
      try {
        reports.push(sampleReport(repositoryRoot, sample, sampleRoot));
      } finally {
        removeWorktree(repositoryRoot, sampleRoot);
      }
    }
  } finally {
    try {
      execFileSync('git', ['worktree', 'prune'], {
        cwd: repositoryRoot,
        encoding: 'utf8',
        windowsHide: true,
      });
    } catch {
      // Preserve the primary sample failure; the lifecycle gate will catch a
      // registered worktree that could not be cleaned.
    }
  }

  const report = {
    schemaVersion: 2,
    mode: 'historical-five-pr-sample',
    generatedAtUtc: new Date().toISOString(),
    repositoryHead: git(repositoryRoot, ['rev-parse', 'HEAD']),
    requiredSampleCount: 5,
    sampleCount: reports.length,
    samples: reports,
    aggregate: {
      allAutoSelectedProfiles: [...new Set(reports.flatMap((item) => item.autoSelectedProfiles))].sort(),
      observedOmittedProfiles: [...new Set(reports.flatMap((item) => item.omittedProfiles))].sort(),
      contractFailures: reports.filter((item) => item.autoExitCode === 2 || item.fullExitCode === 2).length,
      productFailures: reports.filter((item) => item.autoExitCode === 3 || item.fullExitCode === 3).length,
      staleFailures: reports.filter((item) => item.autoExitCode === 4 || item.fullExitCode === 4).length,
      environmentFailures: reports.filter((item) => item.autoExitCode === 5 || item.fullExitCode === 5).length,
      falseNegativesAccepted: 0,
      falsePositivesAccepted: 0,
      retryReruns: reports.reduce((total, item) => total + Number(item.telemetry?.retryCount || 0), 0),
      telemetryCohorts: [...new Set(reports.map((item) => item.telemetry?.cohortId).filter(Boolean))].sort(),
      observationsWithTelemetry: reports.filter((item) => item.telemetry !== null).length,
      firstActionableFailureMedianMs: null,
      medianTimeToActionableFailureMs: null,
      baselineMedianTimeToActionableFailureMs: null,
      rerunReductionPercent: null,
      timeToActionableFailureReductionPercent: null,
      targetStatus: 'pending-live-shadow-data',
    },
    interpretation: [
      'Historical replay validates profile selection, fingerprint stability and schema-v2 telemetry shape on five merged PRs.',
      'The replay is not a substitute for five live PR shadow observations; no profile is promoted to blocking by this artifact.',
      'Time-to-actionable-failure and rerun target percentages remain pending because historical CI timestamps are not equivalent to the required baseline metrics; collect five live observations with one cohort before comparing them.',
    ],
  };
  const target = path.resolve(output);
  mkdirSync(path.dirname(target), { recursive: true });
  writeFileSync(target, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
  return report;
}

function main(argv = process.argv.slice(2)) {
  const root = process.cwd();
  const outputIndex = argv.indexOf('--output');
  const output = outputIndex >= 0 ? argv[outputIndex + 1] : undefined;
  if (outputIndex >= 0 && (!output || output.startsWith('--'))) {
    throw new Error('--output requires a path');
  }
  const report = collectShadowMetrics({ root, output: output ? path.resolve(root, output) : undefined });
  console.log(JSON.stringify({
    sampleCount: report.sampleCount,
    targetStatus: report.aggregate.targetStatus,
    profiles: report.aggregate.allAutoSelectedProfiles,
    omittedProfiles: report.aggregate.observedOmittedProfiles,
    samples: report.samples.map((sample) => ({
      issue: sample.issue,
      pullRequest: sample.pullRequest,
      headSha: sample.headSha,
      status: sample.status,
      autoSelectedProfiles: sample.autoSelectedProfiles,
      omittedProfiles: sample.omittedProfiles,
      fingerprint: sample.fingerprint,
    })),
  }, null, 2));
}

const invoked = process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invoked) {
  try {
    main();
  } catch (error) {
    console.error(`OPS-72 shadow metrics failed: ${error.message}`);
    process.exitCode = 1;
  }
}
