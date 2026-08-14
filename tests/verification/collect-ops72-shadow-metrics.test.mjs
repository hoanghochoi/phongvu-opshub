import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { collectShadowMetrics } from '../../scripts/collect-ops72-shadow-metrics.mjs';

function git(cwd, args) {
  return execFileSync('git', args, { cwd, encoding: 'utf8', windowsHide: true }).trim();
}

test('collector writes a five-sample report without promoting pending metrics', (t) => {
  const root = mkdtempSync(path.join(os.tmpdir(), 'opshub-shadow-collector-'));
  const worktree = path.join(root, 'repo');
  mkdirSync(worktree, { recursive: true });
  t.after(() => {
    const resolved = realpathSync(root);
    const prefix = path.join(realpathSync(os.tmpdir()), 'opshub-shadow-collector-');
    assert.ok(resolved.toLowerCase().startsWith(prefix.toLowerCase()));
    rmSync(resolved, { recursive: true, force: true });
  });
  git(worktree, ['init', '--quiet']);
  git(worktree, ['config', 'user.name', 'shadow-collector-test']);
  git(worktree, ['config', 'user.email', 'shadow-collector@example.invalid']);
  writeFileSync(path.join(worktree, 'README.md'), '# fixture\n');
  mkdirSync(path.join(worktree, 'docs'), { recursive: true });
  mkdirSync(path.join(worktree, 'backend-nest'), { recursive: true });
  mkdirSync(path.join(worktree, 'backend-go'), { recursive: true });
  writeFileSync(path.join(worktree, 'docs', 'README.md'), '# docs\n');
  writeFileSync(path.join(worktree, 'backend-nest', 'package.json'), '{"scripts":{"build":"node --version"}}\n');
  writeFileSync(path.join(worktree, 'backend-go', 'go.mod'), 'module fixture\n\ngo 1.23\n');
  git(worktree, ['add', '--all']);
  git(worktree, ['commit', '--quiet', '-m', 'fixture']);
  writeFileSync(path.join(worktree, 'docs', 'second.md'), '# second commit\n');
  git(worktree, ['add', '--all']);
  git(worktree, ['commit', '--quiet', '-m', 'second fixture']);
  const head = git(worktree, ['rev-parse', 'HEAD']);
  const output = path.join(worktree, 'docs', 'migrations', 'shadow.json');
  const report = collectShadowMetrics({
    root: worktree,
    output,
    samples: Array.from({ length: 5 }, (_, index) => ({
      issue: `OPS-${index + 1}`,
      pullRequest: index + 1,
      head,
    })),
  });
  assert.equal(report.schemaVersion, 2);
  assert.equal(report.sampleCount, 5);
  assert.equal(report.aggregate.targetStatus, 'pending-live-shadow-data');
  assert.ok(report.samples.every((sample) => sample.status === 'passed'));
  assert.ok(report.samples.every((sample) => sample.telemetry?.schemaVersion === 2));
  assert.deepEqual(report.aggregate.telemetryCohorts, ['ops72-shadow-v2']);
  assert.equal(report.aggregate.observationsWithTelemetry, 5);
});
