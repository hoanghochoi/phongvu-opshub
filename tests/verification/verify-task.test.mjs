import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { appendFileSync, mkdirSync, mkdtempSync, realpathSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { collectChangedPaths, fingerprint, parseArgs, runCommand, verifyTask, EXIT_CODES } from '../../scripts/verify-task.mjs';

function git(cwd, args) {
  return execFileSync('git', args, { cwd, encoding: 'utf8', windowsHide: true }).trim();
}

function write(root, relative, content) {
  const target = path.join(root, relative);
  mkdirSync(path.dirname(target), { recursive: true });
  writeFileSync(target, content, 'utf8');
}

function repo(t) {
  const root = mkdtempSync(path.join(os.tmpdir(), 'opshub-verify-task-'));
  t.after(() => {
    const resolved = realpathSync(root);
    if (!resolved.toLowerCase().startsWith(path.join(realpathSync(os.tmpdir()), 'opshub-verify-task-').toLowerCase())) {
      throw new Error(`refusing to remove unexpected test directory: ${resolved}`);
    }
    rmSync(resolved, { recursive: true, force: true });
  });
  git(root, ['init', '--quiet']);
  git(root, ['config', 'user.name', 'verify-task-test']);
  git(root, ['config', 'user.email', 'verify-task@example.invalid']);
  write(root, 'README.md', '# test\n');
  write(root, 'lib/app.dart', 'void main() {}\n');
  git(root, ['add', '--all']);
  git(root, ['commit', '--quiet', '-m', 'baseline']);
  return root;
}

test('changed paths include base, staged, unstaged and untracked; rename is delete plus add', (t) => {
  const root = repo(t);
  const base = git(root, ['rev-parse', 'HEAD']);
  renameSync(path.join(root, 'lib/app.dart'), path.join(root, 'lib/home.dart'));
  appendFileSync(path.join(root, 'lib/home.dart'), '// committed\n');
  git(root, ['add', '--all']);
  git(root, ['commit', '--quiet', '-m', 'rename']);
  write(root, 'backend-go/realtime.go', 'package realtime\n');
  appendFileSync(path.join(root, 'lib/home.dart'), '// dirty\n');
  const paths = collectChangedPaths({ root, base });
  assert.deepEqual(paths, ['backend-go/realtime.go', 'lib/app.dart', 'lib/home.dart']);
});

test('explicit profile is additive and unknown paths fail closed', (t) => {
  const root = repo(t);
  write(root, 'backend-nest/src/app.ts', 'export {}\n');
  const selected = verifyTask({ root, options: { profiles: ['flutter'], dryRun: true } });
  assert.equal(selected.exitCode, EXIT_CODES.PASS);
  assert.deepEqual(selected.result.selectedProfiles, ['nestjs', 'flutter']);
  write(root, 'mystery.bin', 'unknown\n');
  const failed = verifyTask({ root, options: { dryRun: true } });
  assert.equal(failed.exitCode, EXIT_CODES.CONTRACT);
});

test('harness profile owns legacy adapter, schema and CLI retirement paths', (t) => {
  const root = repo(t);
  for (const relative of [
    'scripts/adapter/harness_local_authority_v1.py',
    'scripts/schema/001-init.sql',
    'scripts/build-harness-cli-release.sh',
    'tests/core/test-schema-replay-command-contract.sh',
  ]) {
    write(root, relative, 'retirement fixture\n');
  }
  const result = verifyTask({ root, options: { dryRun: true } });
  assert.equal(result.exitCode, EXIT_CODES.PASS);
  assert.ok(result.result.selectedProfiles.includes('harness'));
});

test('fingerprint changes when untracked content changes', (t) => {
  const root = repo(t);
  write(root, 'tests/verification/example.test.mjs', 'export {}\n');
  const first = fingerprint({ root });
  appendFileSync(path.join(root, 'tests/verification/example.test.mjs'), '// changed\n');
  assert.notEqual(first, fingerprint({ root }));
});

test('fingerprint preserves binary diff bytes for invalid UTF-8 changes', (t) => {
  const root = repo(t);
  mkdirSync(path.join(root, 'assets'), { recursive: true });
  writeFileSync(path.join(root, 'assets', 'blob.bin'), Buffer.from([0xc0, 0x80, 0xff]));
  git(root, ['add', '--all']);
  git(root, ['commit', '--quiet', '-m', 'binary baseline']);
  const first = fingerprint({ root });
  writeFileSync(path.join(root, 'assets', 'blob.bin'), Buffer.from([0xc1, 0x81, 0xfe]));
  const second = fingerprint({ root });
  assert.notEqual(first, second);
});

test('fingerprint preserves staged and base-aware binary diff bytes', (t) => {
  const root = repo(t);
  mkdirSync(path.join(root, 'assets'), { recursive: true });
  writeFileSync(path.join(root, 'assets', 'staged.bin'), Buffer.from([0x00, 0x80, 0xff]));
  git(root, ['add', '--all']);
  const stagedFirst = fingerprint({ root });
  writeFileSync(path.join(root, 'assets', 'staged.bin'), Buffer.from([0x01, 0x81, 0xfe]));
  git(root, ['add', '--all']);
  const stagedSecond = fingerprint({ root });
  assert.notEqual(stagedFirst, stagedSecond);

  git(root, ['commit', '--quiet', '-m', 'binary staged']);
  const base = git(root, ['rev-parse', 'HEAD']);
  writeFileSync(path.join(root, 'assets', 'staged.bin'), Buffer.from([0x02, 0x82, 0xfd]));
  git(root, ['add', '--all']);
  git(root, ['commit', '--quiet', '-m', 'binary base-aware']);
  const baseAwareFirst = fingerprint({ root, base });
  writeFileSync(path.join(root, 'assets', 'staged.bin'), Buffer.from([0x03, 0x83, 0xfc]));
  const baseAwareSecond = fingerprint({ root, base });
  assert.notEqual(baseAwareFirst, baseAwareSecond);
});

test('structured command runner invokes Windows cmd files through the supported shell path', (t) => {
  if (process.platform !== 'win32') {
    t.skip('Windows command invocation contract');
    return;
  }
  const root = repo(t);
  const commandPath = path.join(root, 'probe.cmd');
  writeFileSync(commandPath, '@echo off\r\nexit /b 0\r\n', 'utf8');
  const result = runCommand(root, {
    id: 'windows-cmd-probe',
    cwd: '.',
    executable: commandPath,
    argv: [],
  });
  assert.equal(result.status, 'passed');
  assert.equal(result.exitCode, 0);
});

test('command failure is classified as product failure and preserves structured definitions', (t) => {
  const root = repo(t);
  write(root, 'lib/home.dart', 'void main() { /* changed */ }\n');
  const result = verifyTask({
    root,
    options: { dryRun: false },
    runCommandFn: (_root, command) => ({
      id: command.id,
      executable: command.executable,
      argv: command.argv,
      command: `${command.executable} ${command.argv.join(' ')}`,
      cwd: root,
      status: 'failed',
      exitCode: 17,
      durationMs: 1,
    }),
  });
  assert.equal(result.exitCode, EXIT_CODES.PRODUCT_FAILURE);
  assert.ok(result.result.commandDefinitions.some((command) => command.id === 'flutter-analyze'));
  assert.equal(result.result.result.commands[0].exitCode, 17);
  assert.ok(result.result.commandDefinitions.every((command) => !path.isAbsolute(command.cwd)));
  assert.ok(result.result.result.commands.every((command) => !path.isAbsolute(command.cwd)));
  assert.ok(!JSON.stringify(result.result.toolVersions).includes('Program Files'));
});

test('changed state after the last command is stale even when the command passes', (t) => {
  const root = repo(t);
  write(root, 'lib/home.dart', 'void main() {}\n');
  let invoked = false;
  const result = verifyTask({
    root,
    options: { dryRun: false },
    runCommandFn: () => {
      if (!invoked) {
        invoked = true;
        appendFileSync(path.join(root, 'lib/home.dart'), '// changed during proof\n');
      }
      return { id: 'fake', executable: 'node', argv: [], command: 'node', cwd: root, status: 'passed', exitCode: 0, durationMs: 1 };
    },
  });
  assert.equal(result.exitCode, EXIT_CODES.STALE);
  assert.equal(result.result.fingerprint.stale, true);
});

test('environment failure is distinct from a product/test failure', (t) => {
  const root = repo(t);
  write(root, 'backend-go/realtime.go', 'package realtime\n');
  const result = verifyTask({
    root,
    options: { dryRun: false },
    runCommandFn: (_root, command) => ({
      id: command.id,
      executable: command.executable,
      argv: command.argv,
      command: `${command.executable} ${command.argv.join(' ')}`,
      cwd: root,
      status: 'environment-failure',
      exitCode: null,
      durationMs: 1,
      error: 'tool unavailable',
    }),
  });
  assert.equal(result.exitCode, EXIT_CODES.ENVIRONMENT);
  assert.equal(result.result.result.commands[0].status, 'environment-failure');
});

test('fingerprint includes structured command definitions', (t) => {
  const root = repo(t);
  write(root, 'scripts/verify-task.mjs', 'tracked runner fixture\n');
  const first = fingerprint({
    root,
    commandDefinitions: [{ id: 'check', cwd: '.', executable: 'node', argv: ['--version'] }],
  });
  const second = fingerprint({
    root,
    commandDefinitions: [{ id: 'check', cwd: '.', executable: 'node', argv: ['--check'] }],
  });
  assert.notEqual(first, second);
});

test('command errors are sanitized before structured output', (t) => {
  const root = repo(t);
  write(root, 'backend-go/realtime.go', 'package realtime\n');
  const result = verifyTask({
    root,
    options: { dryRun: false },
    runCommandFn: () => ({
      id: 'go-test',
      executable: 'go',
      argv: ['test', './...'],
      command: 'go test ./...',
      cwd: root,
      status: 'environment-failure',
      exitCode: null,
      durationMs: 1,
      error: `${root}\\private\\tool missing`,
    }),
  });
  assert.equal(result.exitCode, EXIT_CODES.ENVIRONMENT);
  assert.ok(!JSON.stringify(result.result.result).includes(root));
});

test('argument parser supports repeated profiles and full/dry-run/json', () => {
  assert.deepEqual(parseArgs(['--base', 'HEAD', '--profile', 'flutter', '--profile', 'nestjs', '--full', '--dry-run', '--json', 'out.json']), {
    base: 'HEAD', profiles: ['flutter', 'nestjs'], full: true, dryRun: true, json: 'out.json',
  });
  assert.throws(() => parseArgs(['--base']), /requires a value/);
});
