import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { buildShadowReport } from '../../scripts/verify-task-shadow.mjs';

function git(cwd, args) {
  return execFileSync('git', args, { cwd, encoding: 'utf8', windowsHide: true }).trim();
}

function fixture(t) {
  const root = mkdtempSync(path.join(os.tmpdir(), 'opshub-shadow-'));
  t.after(() => {
    const resolved = realpathSync(root);
    const prefix = path.join(realpathSync(os.tmpdir()), 'opshub-shadow-');
    assert.ok(resolved.toLowerCase().startsWith(prefix.toLowerCase()));
    rmSync(resolved, { recursive: true, force: true });
  });
  git(root, ['init', '--quiet']);
  git(root, ['config', 'user.name', 'verify-task-shadow-test']);
  git(root, ['config', 'user.email', 'verify-task-shadow@example.invalid']);
  writeFileSync(path.join(root, 'README.md'), '# shadow\n');
  git(root, ['add', '--all']);
  git(root, ['commit', '--quiet', '-m', 'baseline']);
  return root;
}

test('shadow report compares auto profiles with the full ladder without running commands', (t) => {
  const root = fixture(t);
  mkdirSync(path.join(root, 'docs'), { recursive: true });
  mkdirSync(path.join(root, 'backend-nest'), { recursive: true });
  mkdirSync(path.join(root, 'backend-go'), { recursive: true });
  writeFileSync(path.join(root, 'docs', 'README.md'), '# change\n');
  const report = buildShadowReport({ root, options: { base: 'HEAD' } });
  assert.equal(report.status, 'passed');
  assert.equal(report.schemaVersion, 2);
  assert.deepEqual(report.autoSelectedProfiles, ['harness', 'docs']);
  assert.equal(report.fullProfiles.length, 8);
  assert.ok(report.omittedProfiles.includes('flutter'));
  assert.equal(report.blockingChecksUnchanged, true);
  assert.equal(report.metrics.requiresCanaryReview, true);
  assert.equal(report.metrics.reruns, 0);
  assert.equal(report.telemetry.schemaVersion, 2);
  assert.equal(report.telemetry.cohortId, 'ops72-shadow-v2');
  assert.ok(Date.parse(report.telemetry.queuedAtUtc));
  assert.ok(Date.parse(report.telemetry.startedAtUtc));
  assert.ok(Date.parse(report.telemetry.completedAtUtc));
  assert.ok(report.telemetry.executionDurationMs >= 0);
  assert.equal(report.telemetry.firstActionableFailure, null);
  assert.ok(report.fingerprint.before);
  assert.equal(report.fingerprint.before, report.fingerprint.after);
});

test('shadow report preserves fail-closed contract failures for unknown paths', (t) => {
  const root = fixture(t);
  writeFileSync(path.join(root, 'unknown.bin'), 'unknown\n');
  const report = buildShadowReport({ root, options: { base: 'HEAD' } });
  assert.equal(report.status, 'failed');
  assert.equal(report.schemaVersion, 2);
  assert.equal(report.classification, 'contract-failure');
  assert.equal(report.autoExitCode, 2);
  assert.ok(report.unmatchedPaths.includes('unknown.bin'));
  assert.equal(report.telemetry.firstActionableFailure.category, 'contract-failure');
});

test('shadow telemetry derives retries and first failure from the runner result', (t) => {
  const root = fixture(t);
  const report = buildShadowReport({
    root,
    options: { base: 'HEAD' },
    verifyTaskFn: ({ options }) => ({
      exitCode: options.full ? 0 : 5,
      result: {
        schemaVersion: 1,
        baseSha: 'a'.repeat(40),
        headSha: 'b'.repeat(40),
        selectedProfiles: ['harness'],
        affectedConsumers: ['fixture'],
        changedPaths: [],
        fingerprint: { before: 'c'.repeat(64), after: 'c'.repeat(64), stale: false },
        durationMs: 12,
        result: {
          status: options.full ? 'passed' : 'failed',
          retryPolicy: { maxInfrastructureRetries: 1 },
          commands: options.full
            ? [{ id: 'full-check', status: 'passed', attempt: 1 }]
            : [{ id: 'auto-check', status: 'environment-failure', attempt: 2 }],
        },
      },
    }),
  });

  assert.equal(report.status, 'failed');
  assert.equal(report.telemetry.retryCount, 1);
  assert.equal(report.telemetry.autoRetryCount, 1);
  assert.equal(report.telemetry.fullRetryCount, 0);
  assert.equal(report.telemetry.firstActionableFailure.category, 'environment-failure');
  assert.equal(report.telemetry.firstActionableFailure.commandId, 'auto-check');
  assert.equal(report.telemetry.firstObservedFailure.category, 'environment-failure');
  assert.equal(report.telemetry.firstObservedFailure.commandId, 'auto-check');
  assert.equal(report.metrics.reruns, 1);
});

test('shadow telemetry includes full-ladder retries and elapsed time when auto selection passes', (t) => {
  const root = fixture(t);
  const report = buildShadowReport({
    root,
    options: { base: 'HEAD' },
    verifyTaskFn: ({ options }) => ({
      exitCode: options.full ? 3 : 0,
      result: {
        schemaVersion: 1,
        baseSha: 'a'.repeat(40),
        headSha: 'b'.repeat(40),
        selectedProfiles: ['harness'],
        affectedConsumers: ['fixture'],
        changedPaths: [],
        fingerprint: { before: 'c'.repeat(64), after: 'c'.repeat(64), stale: false },
        durationMs: options.full ? 11 : 7,
        result: {
          status: options.full ? 'failed' : 'passed',
          retryPolicy: { maxInfrastructureRetries: 1 },
          commands: options.full
            ? [{ id: 'full-check', status: 'product-failure', attempt: 2 }]
            : [{ id: 'auto-check', status: 'passed', attempt: 1 }],
        },
      },
    }),
  });

  assert.equal(report.telemetry.retryCount, 1);
  assert.equal(report.telemetry.autoRetryCount, 0);
  assert.equal(report.telemetry.fullRetryCount, 1);
  assert.equal(report.telemetry.firstActionableFailure.commandId, 'full-check');
  assert.equal(report.telemetry.firstActionableFailure.elapsedMs, 18);
  assert.ok(Date.parse(report.telemetry.firstActionableFailure.observedAtUtc));
  assert.equal(report.telemetry.firstObservedFailure.category, 'product-failure');
  assert.equal(report.telemetry.firstObservedFailure.commandId, 'full-check');
});
