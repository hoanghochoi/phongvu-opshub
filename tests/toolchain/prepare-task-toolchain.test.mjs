import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
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

function git(cwd, args) {
  return execFileSync('git', args, {
    cwd,
    encoding: 'utf8',
    windowsHide: true,
  }).trim();
}

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

function flutterFixture(t) {
  const root = mkdtempSync(path.join(os.tmpdir(), 'opshub-flutter-toolchain-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  git(root, ['init', '--quiet']);
  git(root, ['config', 'user.name', 'flutter-toolchain-test']);
  git(root, ['config', 'user.email', 'flutter-toolchain@example.invalid']);
  writeFileSync(path.join(root, 'pubspec.yaml'), 'name: fixture\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n');
  writeFileSync(path.join(root, 'pubspec.lock'), 'packages: {}\n');
  writeFileSync(path.join(root, '.metadata'), 'version:\n  revision: fixture\n');
  writeFileSync(path.join(root, 'README.md'), '# fixture\n');
  writeFileSync(path.join(root, '.gitignore'), '.dart_tool/\ntmp/\n');
  mkdirSync(path.join(root, 'lib', 'l10n'), { recursive: true });
  writeFileSync(
    path.join(root, 'lib', 'l10n', 'app_localizations.dart'),
    '// checked-in generated baseline\n',
  );
  git(root, ['add', '--all']);
  git(root, ['commit', '--quiet', '-m', 'fixture']);
  return root;
}

function allFixture(t) {
  const root = flutterFixture(t);
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
  git(root, ['add', '--all']);
  git(root, ['commit', '--quiet', '-m', 'all-toolchain fixture']);
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
      writeFileSync(
        path.join(root, 'backend-nest', 'node_modules', '.package-lock.json'),
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

test('parser defaults to all and accepts narrow toolchain profiles', () => {
  assert.deepEqual(
    parseArgs(['--dry-run', '--force', '--json', 'tmp/result.json']),
    {
      profile: 'all',
      dryRun: true,
      force: true,
      json: 'tmp/result.json',
      help: false,
    },
  );
  assert.equal(parseArgs([]).profile, 'all');
  assert.equal(parseArgs(['--profile', 'flutter']).profile, 'flutter');
  assert.equal(parseArgs(['--profile', 'all']).profile, 'all');
  assert.throws(() => parseArgs(['--profile', 'unknown']), /Profile không hỗ trợ/);
});

test('default prepare hydrates Nest and Flutter in one deterministic sequence', (t) => {
  const root = allFixture(t);
  const calls = [];
  const result = prepareTaskToolchain({
    root,
    runStepFn: (currentRoot, step) => {
      calls.push(step.id);
      if (step.id === 'nestjs-prisma-generate') {
        mkdirSync(path.join(currentRoot, 'backend-nest', 'node_modules', '.bin'), {
          recursive: true,
        });
        mkdirSync(
          path.join(currentRoot, 'backend-nest', 'node_modules', '@prisma', 'client'),
          { recursive: true },
        );
        mkdirSync(
          path.join(currentRoot, 'backend-nest', 'node_modules', '.prisma', 'client'),
          { recursive: true },
        );
        writeFileSync(
          path.join(
            currentRoot,
            'backend-nest',
            'node_modules',
            '.bin',
            process.platform === 'win32' ? 'nest.cmd' : 'nest',
          ),
          '',
        );
        writeFileSync(
          path.join(
            currentRoot,
            'backend-nest',
            'node_modules',
            '@prisma',
            'client',
            'package.json',
          ),
          '{}\n',
        );
        writeFileSync(
          path.join(currentRoot, 'backend-nest', 'node_modules', '.package-lock.json'),
          '{}\n',
        );
      }
      if (step.id === 'flutter-pub-get') {
        mkdirSync(path.join(currentRoot, '.dart_tool'), { recursive: true });
        writeFileSync(
          path.join(currentRoot, '.dart_tool', 'package_config.json'),
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
    },
  });
  assert.equal(result.exitCode, EXIT_CODES.PASS);
  assert.equal(result.result.status, 'prepared');
  assert.deepEqual(calls, [
    'nestjs-npm-ci',
    'nestjs-prisma-generate',
    'flutter-pub-get',
  ]);
  assert.equal(result.result.profiles.length, 2);
});

test('first prepare hydrates Nest/Prisma and second prepare is cached', (t) => {
  const root = fixture(t);
  const calls = [];
  const runStepFn = successfulStepFactory(calls);

  const first = prepareTaskToolchain({ root, profile: 'nestjs', runStepFn });
  assert.equal(first.exitCode, EXIT_CODES.PASS);
  assert.equal(first.result.status, 'prepared');
  assert.deepEqual(calls, ['nestjs-npm-ci', 'nestjs-prisma-generate']);
  assert.equal(
    existsSync(path.join(root, 'tmp', 'opshub-toolchain-state.json')),
    true,
  );

  const second = prepareTaskToolchain({
    root,
    profile: 'nestjs',
    runStepFn: () => {
      throw new Error('cached prepare must not execute commands');
    },
  });
  assert.equal(second.exitCode, EXIT_CODES.PASS);
  assert.equal(second.result.status, 'cached');
});

test('partial Nest dependency loss invalidates the cached readiness', (t) => {
  const root = fixture(t);
  const calls = [];
  const runStepFn = successfulStepFactory(calls);
  prepareTaskToolchain({ root, profile: 'nestjs', runStepFn });
  rmSync(path.join(root, 'backend-nest', 'node_modules', '.prisma', 'client'), {
    recursive: true,
    force: true,
  });

  const result = prepareTaskToolchain({ root, profile: 'nestjs', runStepFn });
  assert.equal(result.exitCode, EXIT_CODES.PASS);
  assert.equal(result.result.status, 'prepared');
  assert.deepEqual(calls, [
    'nestjs-npm-ci',
    'nestjs-prisma-generate',
    'nestjs-npm-ci',
    'nestjs-prisma-generate',
  ]);
});

test('transient Prisma module-load failure retries once with a stable fingerprint', (t) => {
  const root = fixture(t);
  const calls = [];
  const success = successfulStepFactory([]);
  let prismaAttempts = 0;
  const result = prepareTaskToolchain({
    root,
    profile: 'nestjs',
    runStepFn: (currentRoot, step) => {
      calls.push(step.id);
      if (step.id === 'nestjs-prisma-generate' && prismaAttempts++ === 0) {
        return {
          id: step.id,
          status: 'environment-failure',
          exitCode: 1,
          executable: step.executable,
          argv: step.argv,
          error: "Error: Cannot find module '@prisma/studio-core/data/bff'",
        };
      }
      return success(currentRoot, step);
    },
  });

  assert.equal(result.exitCode, EXIT_CODES.PASS);
  assert.equal(result.result.status, 'prepared');
  assert.deepEqual(calls, [
    'nestjs-npm-ci',
    'nestjs-prisma-generate',
    'nestjs-npm-ci',
    'nestjs-prisma-generate',
  ]);
  assert.deepEqual(result.result.retries, [
    {
      step: 'nestjs-prisma-generate',
      fromAttempt: 1,
      toAttempt: 2,
      reason: 'transient-prisma-module-load',
    },
  ]);
});

test('Prisma retry stops when the toolchain manifest changes mid-attempt', (t) => {
  const root = fixture(t);
  let failed = false;
  const result = prepareTaskToolchain({
    root,
    profile: 'nestjs',
    runStepFn: (_currentRoot, step) => {
      if (step.id === 'nestjs-prisma-generate' && !failed) {
        failed = true;
        appendFileSync(
          path.join(root, 'backend-nest', 'package-lock.json'),
          '{"changed-during-retry":true}\n',
        );
        return {
          id: step.id,
          status: 'environment-failure',
          exitCode: 1,
          executable: step.executable,
          argv: step.argv,
          error: "Error: Cannot find module '@prisma/studio-core/data/bff'",
        };
      }
      return {
        id: step.id,
        status: 'passed',
        exitCode: 0,
        executable: step.executable,
        argv: step.argv,
      };
    },
  });
  assert.equal(result.exitCode, EXIT_CODES.ENVIRONMENT);
  assert.equal(result.result.status, 'environment-failure');
  assert.match(result.result.error, /manifest changed|stale/i);
  assert.equal(
    existsSync(path.join(root, 'tmp', 'opshub-toolchain-state.json')),
    false,
  );
});

test('lockfile changes invalidate the cached hydration fingerprint', (t) => {
  const root = fixture(t);
  const calls = [];
  const runStepFn = successfulStepFactory(calls);
  prepareTaskToolchain({ root, profile: 'nestjs', runStepFn });
  appendFileSync(
    path.join(root, 'backend-nest', 'package-lock.json'),
    '{"changed":true}\n',
  );

  const result = prepareTaskToolchain({ root, profile: 'nestjs', runStepFn });
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
  const result = prepareTaskToolchain({ root, profile: 'nestjs', dryRun: true });
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
    profile: 'nestjs',
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
    () => prepareTaskToolchain({ root, profile: 'nestjs' }),
    (error) => error.code === EXIT_CODES.CONTRACT,
  );
});

test('state file stays sanitized and repository-relative', (t) => {
  const root = fixture(t);
  const result = prepareTaskToolchain({
    root,
    profile: 'nestjs',
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

test('Flutter preflight hydrates package config and restores generated tracked files', (t) => {
  const root = flutterFixture(t);
  const calls = [];
  const result = prepareTaskToolchain({
    root,
    profile: 'flutter',
    runStepFn: (currentRoot, step) => {
      calls.push(step.id);
      mkdirSync(path.join(currentRoot, '.dart_tool'), { recursive: true });
      writeFileSync(
        path.join(currentRoot, '.dart_tool', 'package_config.json'),
        '{}\n',
      );
      mkdirSync(path.join(currentRoot, 'lib', 'l10n'), { recursive: true });
      writeFileSync(
        path.join(currentRoot, 'lib', 'l10n', 'app_localizations.dart'),
        '// generated\n',
      );
      return {
        id: step.id,
        status: 'passed',
        exitCode: 0,
        executable: step.executable,
        argv: step.argv,
      };
    },
  });
  assert.equal(result.exitCode, EXIT_CODES.PASS);
  assert.equal(result.result.status, 'prepared');
  assert.deepEqual(calls, ['flutter-pub-get']);
  assert.ok(result.result.worktree.restoredPaths.includes('lib/l10n/app_localizations.dart'));
  assert.equal(git(root, ['status', '--porcelain=v1', '--untracked-files=all']), '');

  const cached = prepareTaskToolchain({
    root,
    profile: 'flutter',
    runStepFn: () => {
      throw new Error('cached Flutter preflight must not execute commands');
    },
  });
  assert.equal(cached.exitCode, EXIT_CODES.PASS);
  assert.equal(cached.result.status, 'cached');

  appendFileSync(path.join(root, '.metadata'), 'channel: stable\n');
  const refreshed = prepareTaskToolchain({
    root,
    profile: 'flutter',
    runStepFn: (currentRoot, step) => {
      mkdirSync(path.join(currentRoot, '.dart_tool'), { recursive: true });
      writeFileSync(
        path.join(currentRoot, '.dart_tool', 'package_config.json'),
        '{}\n',
      );
      return {
        id: step.id,
        status: 'passed',
        exitCode: 0,
        executable: step.executable,
        argv: step.argv,
      };
    },
  });
  assert.equal(refreshed.exitCode, EXIT_CODES.PASS);
  assert.equal(refreshed.result.status, 'prepared');
});

test('Flutter preflight fails closed on unexpected tracked mutation', (t) => {
  const root = flutterFixture(t);
  const result = prepareTaskToolchain({
    root,
    profile: 'flutter',
    runStepFn: (currentRoot, step) => {
      mkdirSync(path.join(currentRoot, '.dart_tool'), { recursive: true });
      writeFileSync(
        path.join(currentRoot, '.dart_tool', 'package_config.json'),
        '{}\n',
      );
      appendFileSync(path.join(currentRoot, 'README.md'), 'unexpected\n');
      return {
        id: step.id,
        status: 'passed',
        exitCode: 0,
        executable: step.executable,
        argv: step.argv,
      };
    },
  });
  assert.equal(result.exitCode, EXIT_CODES.ENVIRONMENT);
  assert.equal(result.result.status, 'environment-failure');
  assert.match(result.result.error, /outside generated allowlist|allowlist/);
  assert.equal(existsSync(path.join(root, 'tmp', 'opshub-toolchain-state.json')), false);
});
