import assert from 'node:assert/strict';
import {
  existsSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  EXIT_CODES,
  parseArgs,
  runWithToolchain,
} from '../../scripts/run-with-toolchain.mjs';

function fixture(t) {
  const root = mkdtempSync(path.join(os.tmpdir(), 'opshub-run-toolchain-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  mkdirSync(path.join(root, 'backend-nest'), { recursive: true });
  mkdirSync(path.join(root, 'lib'), { recursive: true });
  return root;
}

function successfulPrepare() {
  return {
    exitCode: 0,
    result: {
      schemaVersion: 6,
      profile: 'flutter',
      fingerprint: 'prep-fingerprint',
      profiles: [],
    },
  };
}

test('runner parser separates gate options from the structured command', () => {
  assert.deepEqual(
    parseArgs([
      '--root',
      '..',
      '--cwd',
      'backend-nest',
      '--profile',
      'nestjs',
      '--json',
      'tmp/result.json',
      '--',
      'npm',
      'test',
      '--runInBand',
    ]),
    {
      root: '..',
      cwd: 'backend-nest',
      profile: 'nestjs',
      json: 'tmp/result.json',
      dryRun: false,
      force: false,
      preflightOnly: false,
      command: ['npm', 'test', '--runInBand'],
    },
  );
  assert.throws(
    () => parseArgs(['--preflight-only', '--', 'npm', 'test']),
    /preflight-only cannot be combined/,
  );
});

test('Flutter commands receive --no-pub and dry-run never executes the command', (t) => {
  const root = fixture(t);
  let executions = 0;
  const result = runWithToolchain({
    root,
    profile: 'flutter',
    cwd: 'lib',
    command: ['flutter', 'test', '--reporter', 'compact'],
    dryRun: true,
    prepare: successfulPrepare,
    runCommand: () => {
      executions += 1;
      return { status: 0 };
    },
  });

  assert.equal(result.exitCode, EXIT_CODES.PASS);
  assert.equal(result.result.status, 'planned');
  assert.equal(executions, 0);
  assert.match(result.result.command.executable, /^flutter(?:\.bat)?$/i);
  assert.deepEqual(result.result.command.argv, [
    'test',
    '--reporter',
    'compact',
    '--no-pub',
  ]);
});

test('Windows command wrappers are represented as executable plus argv', (t) => {
  const root = fixture(t);
  const result = runWithToolchain({
    root,
    profile: 'nestjs',
    command: ['npm', 'test'],
    dryRun: true,
    prepare: () => ({
      exitCode: EXIT_CODES.PASS,
      result: { profile: 'nestjs', fingerprint: 'prep' },
    }),
  });

  assert.equal(result.exitCode, EXIT_CODES.PASS);
  if (process.platform === 'win32') assert.equal(result.result.command.executable, 'npm.cmd');
  else assert.equal(result.result.command.executable, 'npm');
  assert.deepEqual(result.result.command.argv, ['test']);
});

test('preflight failure blocks the command and maps to environment exit code', (t) => {
  const root = fixture(t);
  let executions = 0;
  const result = runWithToolchain({
    root,
    profile: 'nestjs',
    command: ['npm', 'test'],
    prepare: () => ({
      exitCode: EXIT_CODES.ENVIRONMENT,
      result: { profile: 'nestjs', status: 'environment-failure' },
    }),
    runCommand: () => {
      executions += 1;
      return { status: 0 };
    },
  });

  assert.equal(result.exitCode, EXIT_CODES.ENVIRONMENT);
  assert.equal(result.result.status, 'environment-failure');
  assert.equal(executions, 0);
});

test('command failures distinguish product failure from environment failure', (t) => {
  const root = fixture(t);
  const product = runWithToolchain({
    root,
    profile: 'nestjs',
    command: ['npm', 'test'],
    prepare: successfulPrepare,
    runCommand: () => ({ status: 7 }),
  });
  assert.equal(product.exitCode, EXIT_CODES.PRODUCT_FAILURE);
  assert.equal(product.result.status, 'product-failure');

  const environment = runWithToolchain({
    root,
    profile: 'nestjs',
    command: ['npm', 'test'],
    prepare: successfulPrepare,
    runCommand: () => ({ error: new Error(`${root}\\backend-nest\\node_modules\\missing`) }),
  });
  assert.equal(environment.exitCode, EXIT_CODES.ENVIRONMENT);
  assert.equal(environment.result.status, 'environment-failure');
  assert.equal(environment.result.error.includes(root), false);
  assert.match(environment.result.error, /<worktree>|<path>/);
});

test('JSON result is sanitized and repository-relative', (t) => {
  const root = fixture(t);
  const outputPath = 'tmp/toolchain-result.json';
  const result = runWithToolchain({
    root,
    profile: 'nestjs',
    command: ['npm', 'test'],
    json: outputPath,
    prepare: successfulPrepare,
    runCommand: () => ({ status: 0 }),
  });
  assert.equal(result.exitCode, EXIT_CODES.PASS);
  const written = readFileSync(path.join(root, outputPath), 'utf8');
  assert.equal(written.includes(root), false);
  assert.equal(existsSync(path.join(root, outputPath)), true);
  const parsed = JSON.parse(written);
  assert.equal(parsed.schemaVersion, 1);
  assert.equal(parsed.root, '<worktree>');
});
