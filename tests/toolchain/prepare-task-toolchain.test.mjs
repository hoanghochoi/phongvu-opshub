import assert from 'node:assert/strict';
import {
  appendFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
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
  prepareTaskToolchain,
} from '../../scripts/prepare-task-toolchain.mjs';

function fixture(t) {
  const root = mkdtempSync(path.join(os.tmpdir(), 'opshub-toolchain-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  mkdirSync(path.join(root, 'backend-nest', 'prisma'), { recursive: true });
  writeFileSync(
    path.join(root, 'backend-nest', 'package.json'),
    '{"name":"fixture"}\n',
  );
  writeFileSync(
    path.join(root, 'backend-nest', 'package-lock.json'),
    '{"lockfileVersion":3}\n',
  );
  writeFileSync(
    path.join(root, 'backend-nest', 'prisma', 'schema.prisma'),
    'datasource db { provider = "postgresql" }\n',
  );
  writeFileSync(
    path.join(root, 'backend-nest', 'prisma.config.ts'),
    'export default {};\n',
  );
  return root;
}

function successfulStepFactory(calls) {
  return (root, step) => {
    calls.push(step.id);
    if (step.id === 'nestjs-prisma-generate') {
      mkdirSync(path.join(root, 'backend-nest', 'node_modules', '.bin'), {
        recursive: true,
      });
      mkdirSync(
        path.join(root, 'backend-nest', 'node_modules', '@prisma', 'client'),
        { recursive: true },
      );
      mkdirSync(
        path.join(root, 'backend-nest', 'node_modules', '.prisma', 'client'),
        { recursive: true },
      );
      writeFileSync(
        path.join(
          root,
          'backend-nest',
          'node_modules',
          '.bin',
          process.platform === 'win32' ? 'nest.cmd' : 'nest',
        ),
        '',
      );
      writeFileSync(
        path.join(
          root,
          'backend-nest',
          'node_modules',
          '@prisma',
          'client',
          'package.json',
        ),
        '{}\n',
      );
    }
    return {
      id: step.id,
      status: 'passed',
      exitCode: 0,
      executable: step.executable,
      argv: step.argv,
    };
  };
}

test('parser defaults to nestjs and accepts dry-run/force/json', () => {
  assert.deepEqual(
    parseArgs(['--dry-run', '--force', '--json', 'tmp/result.json']),
    {
      profile: 'nestjs',
      dryRun: true,
      force: true,
      json: 'tmp/result.json',
      help: false,
    },
  );
  assert.equal(parseArgs([]).profile, 'nestjs');
});

test('first prepare hydrates Nest/Prisma and second prepare is cached', (t) => {
  const root = fixture(t);
  const calls = [];
  const runStepFn = successfulStepFactory(calls);

  const first = prepareTaskToolchain({ root, runStepFn });
  assert.equal(first.exitCode, EXIT_CODES.PASS);
  assert.equal(first.result.status, 'prepared');
  assert.deepEqual(calls, ['nestjs-npm-ci', 'nestjs-prisma-generate']);
  assert.equal(
    existsSync(path.join(root, 'tmp', 'opshub-toolchain-state.json')),
    true,
  );

  const second = prepareTaskToolchain({
    root,
    runStepFn: () => {
      throw new Error('cached prepare must not execute commands');
    },
  });
  assert.equal(second.exitCode, EXIT_CODES.PASS);
  assert.equal(second.result.status, 'cached');
});

test('lockfile changes invalidate the cached hydration fingerprint', (t) => {
  const root = fixture(t);
  const calls = [];
  const runStepFn = successfulStepFactory(calls);
  prepareTaskToolchain({ root, runStepFn });
  appendFileSync(
    path.join(root, 'backend-nest', 'package-lock.json'),
    '{"changed":true}\n',
  );

  const result = prepareTaskToolchain({ root, runStepFn });
  assert.equal(result.exitCode, EXIT_CODES.PASS);
  assert.equal(result.result.status, 'prepared');
  assert.deepEqual(calls, [
    'nestjs-npm-ci',
    'nestjs-prisma-generate',
    'nestjs-npm-ci',
    'nestjs-prisma-generate',
  ]);
});

test('dry-run reports missing hydration without mutating state', (t) => {
  const root = fixture(t);
  const result = prepareTaskToolchain({ root, dryRun: true });
  assert.equal(result.exitCode, EXIT_CODES.PASS);
  assert.equal(result.result.status, 'planned');
  assert.equal(result.result.steps.length, 2);
  assert.equal(
    existsSync(path.join(root, 'tmp', 'opshub-toolchain-state.json')),
    false,
  );
});

test('command failure is classified as environment failure and does not write success state', (t) => {
  const root = fixture(t);
  const result = prepareTaskToolchain({
    root,
    runStepFn: (currentRoot, step) => ({
      id: step.id,
      status: 'environment-failure',
      exitCode: null,
      executable: step.executable,
      argv: step.argv,
      error: `missing ${currentRoot}`,
    }),
  });
  assert.equal(result.exitCode, EXIT_CODES.ENVIRONMENT);
  assert.equal(result.result.status, 'environment-failure');
  assert.equal(
    existsSync(path.join(root, 'tmp', 'opshub-toolchain-state.json')),
    false,
  );
});

test('missing manifest is a contract failure', (t) => {
  const root = fixture(t);
  rmSync(path.join(root, 'backend-nest', 'prisma.config.ts'));
  assert.throws(
    () => prepareTaskToolchain({ root }),
    (error) => error.code === EXIT_CODES.CONTRACT,
  );
});

test('state file stays sanitized and repository-relative', (t) => {
  const root = fixture(t);
  const result = prepareTaskToolchain({
    root,
    runStepFn: successfulStepFactory([]),
  });
  assert.equal(result.exitCode, EXIT_CODES.PASS);
  const state = readFileSync(
    path.join(root, 'tmp', 'opshub-toolchain-state.json'),
    'utf8',
  );
  assert.equal(state.includes(root), false);
  assert.equal(state.includes('node_modules'), false);
});
