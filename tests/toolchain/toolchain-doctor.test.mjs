import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  EXIT_CODES,
  doctorToolchain,
  parseArgs,
} from '../../scripts/toolchain-doctor.mjs';

function git(cwd, args) {
  return execFileSync('git', args, {
    cwd,
    encoding: 'utf8',
    windowsHide: true,
  }).trim();
}

function fixture(t) {
  const root = mkdtempSync(path.join(os.tmpdir(), 'opshub-toolchain-doctor-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  git(root, ['init', '--quiet']);
  git(root, ['config', 'user.name', 'toolchain-doctor-test']);
  git(root, ['config', 'user.email', 'toolchain-doctor@example.invalid']);
  writeFileSync(path.join(root, 'README.md'), '# doctor fixture\n');
  git(root, ['add', '--all']);
  git(root, ['commit', '--quiet', '-m', 'fixture']);
  return root;
}

test('doctor parser defaults to all and supports an existing worktree', () => {
  assert.deepEqual(parseArgs([]), {
    root: '.',
    profile: 'all',
    dryRun: false,
    check: false,
    force: false,
    json: null,
    help: false,
  });
  assert.deepEqual(
    parseArgs(['--root', '..\\opshub-ops-121', '--profile', 'flutter', '--force']),
    {
      root: '..\\opshub-ops-121',
      profile: 'flutter',
      dryRun: false,
      check: false,
      force: true,
      json: null,
      help: false,
    },
  );
  assert.throws(() => parseArgs(['--profile', 'unknown']), /Unsupported profile/);
  assert.deepEqual(parseArgs(['--check', '--profile', 'flutter']), {
    root: '.',
    profile: 'flutter',
    dryRun: false,
    check: true,
    force: false,
    json: null,
    help: false,
  });
  assert.throws(
    () => parseArgs(['--check', '--force']),
    /cannot be combined/,
  );
});

test('doctor uses the requested existing Git worktree and returns sanitized proof', (t) => {
  const root = fixture(t);
  let received;
  const result = doctorToolchain({
    root,
    profile: 'flutter',
    dryRun: true,
    prepare: (options) => {
      received = options;
      return {
        exitCode: 0,
        result: {
          profile: options.profile,
          status: 'planned',
          readiness: { packageConfig: false },
        },
      };
    },
  });

  assert.equal(result.exitCode, EXIT_CODES.PASS);
  assert.equal(result.result.root, '<worktree>');
  assert.equal(result.result.status, 'passed');
  assert.equal(received.root, root);
  assert.equal(received.profile, 'flutter');
  assert.equal(received.dryRun, true);
});

test('doctor preserves an environment failure and gives a repair command', (t) => {
  const root = fixture(t);
  const result = doctorToolchain({
    root,
    profile: 'all',
    prepare: () => ({
      exitCode: 5,
      result: {
        profile: 'all',
        status: 'environment-failure',
        error: 'Flutter: package config missing',
      },
    }),
  });

  assert.equal(result.exitCode, EXIT_CODES.ENVIRONMENT);
  assert.equal(result.result.status, 'failed');
  assert.match(result.result.remediation, /toolchain-doctor\.mjs/);
  assert.match(result.result.preparation.error, /package config missing/);
});

test('doctor check fails closed when a non-mutating readiness probe is incomplete', (t) => {
  const root = fixture(t);
  const result = doctorToolchain({
    root,
    profile: 'flutter',
    check: true,
    prepare: (options) => {
      assert.equal(options.dryRun, true);
      assert.equal(options.force, false);
      return {
        exitCode: 0,
        result: { profile: 'flutter', status: 'planned' },
      };
    },
  });

  assert.equal(result.exitCode, EXIT_CODES.ENVIRONMENT);
  assert.equal(result.result.status, 'failed');
  assert.equal(result.result.check, true);
  assert.equal(result.result.readiness.ready, false);
  assert.match(result.result.error, /readiness is incomplete/i);
});
