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
  assert.deepEqual(report.autoSelectedProfiles, ['harness', 'docs']);
  assert.equal(report.fullProfiles.length, 8);
  assert.ok(report.omittedProfiles.includes('flutter'));
  assert.equal(report.blockingChecksUnchanged, true);
  assert.equal(report.metrics.requiresCanaryReview, true);
  assert.ok(report.fingerprint.before);
  assert.equal(report.fingerprint.before, report.fingerprint.after);
});

test('shadow report preserves fail-closed contract failures for unknown paths', (t) => {
  const root = fixture(t);
  writeFileSync(path.join(root, 'unknown.bin'), 'unknown\n');
  const report = buildShadowReport({ root, options: { base: 'HEAD' } });
  assert.equal(report.status, 'failed');
  assert.equal(report.classification, 'contract-failure');
  assert.equal(report.autoExitCode, 2);
  assert.ok(report.unmatchedPaths.includes('unknown.bin'));
});
