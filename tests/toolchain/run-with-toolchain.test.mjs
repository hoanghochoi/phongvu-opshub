import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import {
  closeSync,
  existsSync,
  openSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
  statSync,
} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import test from 'node:test';

import {
  EXIT_CODES,
  defaultRunCommand,
  parseArgs,
  runWithToolchain,
} from '../../scripts/run-with-toolchain.mjs';
import {
  acquireToolchainLease,
  toolchainLeaseEnvironment,
} from '../../scripts/prepare-task-toolchain.mjs';

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

test('a cold worktree hydrates its own Flutter state before the consumer command', (t) => {
  const root = fixture(t);
  const packageConfig = path.join(root, '.dart_tool', 'package_config.json');
  let commandRan = false;
  const result = runWithToolchain({
    root,
    profile: 'flutter',
    command: ['flutter', 'analyze'],
    prepare: ({ root: preparedRoot, profile }) => {
      assert.equal(preparedRoot, root);
      assert.equal(profile, 'flutter');
      mkdirSync(path.dirname(packageConfig), { recursive: true });
      writeFileSync(packageConfig, '{"configVersion":2,"packages":[]}\n');
      return successfulPrepare();
    },
    runCommand: (_executable, _argv, cwd) => {
      commandRan = true;
      assert.equal(cwd, root);
      assert.equal(existsSync(packageConfig), true);
      return { status: 0 };
    },
  });

  assert.equal(result.exitCode, EXIT_CODES.PASS);
  assert.equal(commandRan, true);
  assert.equal(result.result.status, 'passed');
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

test('gated Flutter commands inherit the resolved Pub cache environment', (t) => {
  const root = fixture(t);
  const cacheRoot = mkdtempSync(path.join(os.tmpdir(), 'opshub-run-pub-cache-'));
  t.after(() => rmSync(cacheRoot, { recursive: true, force: true }));
  const hadPubCache = Object.prototype.hasOwnProperty.call(
    process.env,
    'PUB_CACHE',
  );
  const previousPubCache = process.env.PUB_CACHE;
  process.env.PUB_CACHE = cacheRoot;
  try {
    let commandOptions;
    const result = runWithToolchain({
      root,
      profile: 'flutter',
      command: ['flutter', 'analyze'],
      prepare: successfulPrepare,
      runCommand: (_executable, _argv, _cwd, options) => {
        commandOptions = options;
        return { status: 0 };
      },
    });

    assert.equal(result.exitCode, EXIT_CODES.PASS);
    assert.equal(commandOptions.env.PUB_CACHE, path.resolve(cacheRoot));
    assert.equal(
      JSON.parse(commandOptions.env.OPSHUB_TOOLCHAIN_LEASE).profile,
      'flutter',
    );
  } finally {
    if (hadPubCache) process.env.PUB_CACHE = previousPubCache;
    else delete process.env.PUB_CACHE;
  }
});

test('Flutter Pub cache lease serializes separate hydration processes', async (t) => {
  const root = fixture(t);
  const cacheRoot = mkdtempSync(
    path.join(os.tmpdir(), 'opshub-concurrent-pub-cache-'),
  );
  t.after(() => rmSync(cacheRoot, { recursive: true, force: true }));

  const prepareModule = pathToFileURL(
    path.resolve(import.meta.dirname, '../../scripts/prepare-task-toolchain.mjs'),
  ).href;
  const childScript = `import { acquireToolchainLease } from ${JSON.stringify(
    prepareModule,
  )};
const release = acquireToolchainLease({
  root: ${JSON.stringify(root)},
  profile: 'flutter',
});
console.log('acquired');
setTimeout(() => {
  release();
  process.exit(0);
}, 350);
`;
  const env = { ...process.env, PUB_CACHE: cacheRoot };
  delete env.OPSHUB_TOOLCHAIN_LEASE;

  const spawnLease = () =>
    spawn(process.execPath, ['--input-type=module', '-e', childScript], {
      cwd: root,
      env,
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true,
    });
  const waitForAcquired = (child) =>
    new Promise((resolve, reject) => {
      let output = '';
      let settled = false;
      child.stdout.on('data', (chunk) => {
        output += String(chunk);
        if (!settled && output.includes('acquired')) {
          settled = true;
          resolve(Date.now());
        }
      });
      child.on('error', reject);
      child.on('exit', (code) => {
        if (!settled && code !== 0) {
          reject(new Error(`lease child exited before acquiring: ${code}`));
        }
      });
    });
  const waitForExit = (child) =>
    new Promise((resolve, reject) => {
      child.on('error', reject);
      child.on('exit', (code) => {
        if (code === 0) resolve();
        else reject(new Error(`lease child exited with ${code}`));
      });
    });

  const first = spawnLease();
  const firstExit = waitForExit(first);
  const firstAcquiredAt = await waitForAcquired(first);
  const second = spawnLease();
  const secondExit = waitForExit(second);
  const secondAcquiredAt = await waitForAcquired(second);
  assert.ok(
    secondAcquiredAt - firstAcquiredAt >= 200,
    `second lease acquired too early: ${secondAcquiredAt - firstAcquiredAt}ms`,
  );
  await Promise.all([firstExit, secondExit]);
});

test('sensitive command arguments are redacted from proof output and fingerprint', (t) => {
  const root = fixture(t);
  const run = (password) =>
    runWithToolchain({
      root,
      profile: 'flutter',
      command: [
        'dart',
        'run',
        'msix:create',
        '--certificate-password',
        password,
        '--output-name=internal-msix',
      ],
      dryRun: true,
      prepare: successfulPrepare,
    });

  const first = run('first-secret');
  const second = run('second-secret');
  assert.deepEqual(first.result.command.argv, [
    'run',
    'msix:create',
    '--certificate-password',
    '<redacted>',
    '--output-name=internal-msix',
  ]);
  assert.equal(JSON.stringify(first.result).includes('first-secret'), false);
  assert.equal(first.result.fingerprint, second.result.fingerprint);
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
  assert.equal(
    result.result.remediation,
    'node scripts/prepare-task-toolchain.mjs --profile nestjs --force',
  );
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

test('Flutter command-time package loss repairs once and retries with a stable fingerprint', (t) => {
  const root = fixture(t);
  let ready = false;
  let prepareCalls = 0;
  let commandCalls = 0;
  const result = runWithToolchain({
    root,
    profile: 'flutter',
    command: ['flutter', 'analyze'],
    prepare: ({ force }) => {
      prepareCalls += 1;
      if (force) ready = true;
      return {
        exitCode: 0,
        result: {
          schemaVersion: 7,
          profile: 'flutter',
          fingerprint: 'stable-fingerprint',
          readiness: { ready },
        },
      };
    },
    readiness: () => ({ ready }),
    runCommand: () => {
      commandCalls += 1;
      return commandCalls === 1
        ? { status: 1, diagnostic: 'Could not find package http' }
        : { status: 0 };
    },
  });

  assert.equal(result.exitCode, EXIT_CODES.PASS);
  assert.equal(result.result.status, 'passed');
  assert.equal(prepareCalls, 2);
  assert.equal(commandCalls, 2);
  assert.equal(result.result.recovery.status, 'repaired-and-retried');
  assert.equal(result.result.recovery.profile, 'flutter');
});

test('Nest command-time module loss repairs once and retries with a stable fingerprint', (t) => {
  const root = fixture(t);
  let ready = false;
  let prepareCalls = 0;
  let commandCalls = 0;
  const result = runWithToolchain({
    root,
    profile: 'nestjs',
    cwd: 'backend-nest',
    command: ['npm', 'run', 'build'],
    prepare: ({ force }) => {
      prepareCalls += 1;
      if (force) ready = true;
      return {
        exitCode: 0,
        result: {
          schemaVersion: 7,
          profile: 'nestjs',
          fingerprint: 'stable-fingerprint',
          readiness: { ready },
        },
      };
    },
    readiness: () => ({ ready }),
    runCommand: () => {
      commandCalls += 1;
      return commandCalls === 1
        ? {
            status: 1,
            diagnostic: "Cannot find module 'node_modules/@nestjs/core'",
          }
        : { status: 0 };
    },
  });

  assert.equal(result.exitCode, EXIT_CODES.PASS);
  assert.equal(result.result.status, 'passed');
  assert.equal(prepareCalls, 2);
  assert.equal(commandCalls, 2);
  assert.equal(result.result.recovery.profile, 'nestjs');
});

test('persistent dependency failure is environment failure after one repair', (t) => {
  const root = fixture(t);
  let prepareCalls = 0;
  let commandCalls = 0;
  const result = runWithToolchain({
    root,
    profile: 'nestjs',
    cwd: 'backend-nest',
    command: ['npm', 'run', 'build'],
    prepare: ({ force }) => {
      prepareCalls += 1;
      return {
        exitCode: 0,
        result: {
          profile: 'nestjs',
          fingerprint: 'stable-fingerprint',
          readiness: { ready: Boolean(force) },
        },
      };
    },
    readiness: ({ profile }) => {
      assert.equal(profile, 'nestjs');
      return { ready: prepareCalls > 1 };
    },
    runCommand: () => {
      commandCalls += 1;
      return {
        status: 1,
        diagnostic: "Error: Cannot find module 'node_modules/@nestjs/core'",
      };
    },
  });

  assert.equal(result.exitCode, EXIT_CODES.ENVIRONMENT);
  assert.equal(result.result.status, 'environment-failure');
  assert.equal(result.result.recovery.status, 'failed-after-repair');
  assert.equal(result.result.recovery.profile, 'nestjs');
  assert.equal(commandCalls, 2);
  assert.equal(prepareCalls, 2);
  assert.match(result.result.error, /Cannot find module/);
  assert.equal(
    existsSync(path.join(root, 'tmp', '.opshub-nest-toolchain.lock')),
    false,
  );
});

test('persistent dependency failure is fail-closed with the default command runner', (t) => {
  const root = fixture(t);
  const readinessState = { ready: false };
  let prepareCalls = 0;
  const result = runWithToolchain({
    root,
    profile: 'nestjs',
    cwd: 'backend-nest',
    command: [
      process.execPath,
      '-e',
      "console.error('MODULE_NOT_FOUND: node_modules/@nestjs/core'); process.exit(1)",
    ],
    prepare: ({ force }) => {
      prepareCalls += 1;
      readinessState.ready = Boolean(force);
      return {
        exitCode: 0,
        result: {
          profile: 'nestjs',
          fingerprint: 'stable-fingerprint',
          readiness: { ready: readinessState.ready },
        },
      };
    },
    readiness: () => ({ ready: readinessState.ready }),
  });

  assert.equal(result.exitCode, EXIT_CODES.ENVIRONMENT);
  assert.equal(result.result.status, 'environment-failure');
  assert.equal(result.result.recovery.status, 'failed-after-repair');
  assert.match(result.result.recovery.reason, /MODULE_NOT_FOUND/);
  assert.equal(prepareCalls, 2);
});

test('default command runner captures only a bounded diagnostic tail while replaying large output', (t) => {
  const root = fixture(t);
  const result = defaultRunCommand(
    process.execPath,
    [
      '-e',
      "process.stdout.write('x'.repeat(4 * 1024 * 1024)); process.stderr.write('Target of URI doesn\\'t exist: package:http/http.dart\\n')",
    ],
    root,
  );

  assert.equal(result.status, 0);
  assert.equal(result.diagnosticUnavailable, false);
  assert.match(result.diagnostic, /Target of URI doesn't exist/);
  assert.ok(Buffer.byteLength(result.diagnostic, 'utf8') <= 8192);
});

test('captured Flutter materialization diagnostics repair once even when readiness receipt was healthy', (t) => {
  const root = fixture(t);
  mkdirSync(path.join(root, '.dart_tool'), { recursive: true });
  writeFileSync(
    path.join(root, '.dart_tool', 'package_config.json'),
    JSON.stringify({
      configVersion: 2,
      packages: [
        {
          name: 'http',
          rootUri: 'file:///tmp/http',
          packageUri: 'lib/',
        },
      ],
    }),
  );
  let prepareCalls = 0;
  let commandCalls = 0;
  const result = runWithToolchain({
    root,
    profile: 'flutter',
    command: ['flutter', 'test'],
    prepare: ({ force }) => {
      prepareCalls += 1;
      return {
        exitCode: 0,
        result: {
          profile: 'flutter',
          fingerprint: 'stable-fingerprint',
          readiness: { ready: true, forced: Boolean(force) },
        },
      };
    },
    readiness: () => ({ ready: true }),
    runCommand: () => {
      commandCalls += 1;
      return commandCalls === 1
        ? {
            status: 1,
            diagnostic: "Target of URI doesn't exist: package:http/http.dart",
          }
        : { status: 0 };
    },
  });

  assert.equal(result.exitCode, EXIT_CODES.PASS);
  assert.equal(result.result.recovery.status, 'repaired-and-retried');
  assert.equal(result.result.recovery.reason, 'flutter-declared-package-entrypoint');
  assert.equal(prepareCalls, 2);
  assert.equal(commandCalls, 2);
});

test('all profile maps command-time repair to the executable and cwd profile', (t) => {
  const root = fixture(t);
  let repairProfile = null;
  let commandCalls = 0;
  const result = runWithToolchain({
    root,
    profile: 'all',
    cwd: 'backend-nest',
    command: ['npm', 'run', 'build'],
    prepare: ({ profile, force }) => {
      if (force) repairProfile = profile;
      return {
        exitCode: 0,
        result: {
          profile: 'all',
          fingerprint: 'all-fingerprint',
          profiles: [
            { profile: 'nestjs', fingerprint: 'nest-fingerprint' },
            { profile: 'flutter', fingerprint: 'flutter-fingerprint' },
          ],
        },
      };
    },
    readiness: ({ profile }) => ({
      ready: profile === 'nestjs' && repairProfile === 'nestjs',
    }),
    runCommand: () => {
      commandCalls += 1;
      return commandCalls === 1
        ? { status: 1, diagnostic: 'MODULE_NOT_FOUND: @nestjs/core' }
        : { status: 0 };
    },
  });

  assert.equal(result.exitCode, EXIT_CODES.PASS);
  assert.equal(repairProfile, 'nestjs');
  assert.equal(commandCalls, 2);
  assert.equal(result.result.recovery.profile, 'nestjs');
});

test('toolchain lease is re-entrant and releases the Nest worktree lock', (t) => {
  const root = fixture(t);
  const lockPath = path.join(root, 'tmp', '.opshub-nest-toolchain.lock');
  const releaseOuter = acquireToolchainLease({ root, profile: 'nestjs' });
  const releaseInner = acquireToolchainLease({ root, profile: 'nestjs' });
  assert.equal(existsSync(lockPath), true);
  releaseInner();
  assert.equal(existsSync(lockPath), true);
  releaseOuter();
  assert.equal(existsSync(lockPath), false);
});

test('gated Nest commands pass the parent lease marker to child processes', (t) => {
  const root = fixture(t);
  let commandOptions;
  const result = runWithToolchain({
    root,
    profile: 'nestjs',
    cwd: 'backend-nest',
    command: ['npm', 'run', 'build'],
    prepare: successfulPrepare,
    runCommand: (_executable, _argv, _cwd, options) => {
      commandOptions = options;
      return { status: 0 };
    },
  });

  assert.equal(result.exitCode, EXIT_CODES.PASS);
  const marker = JSON.parse(commandOptions.env.OPSHUB_TOOLCHAIN_LEASE);
  assert.equal(marker.profile, 'nestjs');
  assert.equal(marker.root, root);
  assert.equal(Number.isInteger(marker.pid), true);
});

test('nested gated processes preserve the original lease owner marker', (t) => {
  const root = fixture(t);
  const leaseScript = path.join(root, 'nested-lease-check.mjs');
  writeFileSync(
    leaseScript,
    `import { spawnSync } from 'node:child_process';
import { acquireToolchainLease, toolchainLeaseEnvironment } from ${JSON.stringify(
      pathToFileURL(
        path.resolve(import.meta.dirname, '../../scripts/prepare-task-toolchain.mjs'),
      ).href,
    )};

const root = process.env.OPSHUB_NESTED_ROOT;
const level = Number(process.env.OPSHUB_NESTED_LEVEL || '1');
const release = acquireToolchainLease({ root, profile: 'nestjs' });
const commandEnv = toolchainLeaseEnvironment({ root, profile: 'nestjs' });
if (level < 3) {
  const child = spawnSync(process.execPath, [process.argv[1]], {
    env: { ...commandEnv, OPSHUB_NESTED_ROOT: root, OPSHUB_NESTED_LEVEL: String(level + 1) },
    encoding: 'utf8',
    windowsHide: true,
  });
  if (child.stdout) process.stdout.write(child.stdout);
  if (child.stderr) process.stderr.write(child.stderr);
  release();
  process.exit(child.status ?? 1);
}
const marker = JSON.parse(commandEnv.OPSHUB_TOOLCHAIN_LEASE);
if (marker.pid !== Number(process.env.OPSHUB_NESTED_OWNER_PID)) process.exit(2);
release();
`,
    'utf8',
  );

  const release = acquireToolchainLease({ root, profile: 'nestjs' });
  const commandEnv = toolchainLeaseEnvironment({ root, profile: 'nestjs' });
  const child = spawnSync(process.execPath, [leaseScript], {
    env: {
      ...commandEnv,
      OPSHUB_NESTED_ROOT: root,
      OPSHUB_NESTED_LEVEL: '1',
      OPSHUB_NESTED_OWNER_PID: String(process.pid),
    },
    encoding: 'utf8',
    windowsHide: true,
  });
  release();

  assert.equal(child.status, 0, child.stderr || child.stdout);
});

test('command lease is already held while readiness preparation runs', (t) => {
  const root = fixture(t);
  const lockPath = path.join(root, 'tmp', '.opshub-nest-toolchain.lock');
  let heldDuringPrepare = false;
  const result = runWithToolchain({
    root,
    profile: 'nestjs',
    cwd: 'backend-nest',
    command: ['npm', 'run', 'build'],
    prepare: () => {
      heldDuringPrepare = existsSync(lockPath);
      return successfulPrepare();
    },
    runCommand: () => ({ status: 0 }),
  });

  assert.equal(result.exitCode, EXIT_CODES.PASS);
  assert.equal(heldDuringPrepare, true);
  assert.equal(existsSync(lockPath), false);
});

test('dead Nest lease metadata is recovered without waiting for the stale timeout', (t) => {
  const root = fixture(t);
  const lockPath = path.join(root, 'tmp', '.opshub-nest-toolchain.lock');
  mkdirSync(path.dirname(lockPath), { recursive: true });
  writeFileSync(lockPath, '{"pid":999999,"worktree":"<worktree>"}\n');
  const release = acquireToolchainLease({ root, profile: 'nestjs' });
  assert.equal(existsSync(lockPath), true);
  release();
  assert.equal(existsSync(lockPath), false);
});

test('a product missing-package diagnostic is not retried while readiness is healthy', (t) => {
  const root = fixture(t);
  let prepareCalls = 0;
  let commandCalls = 0;
  const result = runWithToolchain({
    root,
    profile: 'flutter',
    command: ['flutter', 'test'],
    prepare: () => {
      prepareCalls += 1;
      return {
        exitCode: 0,
        result: {
          profile: 'flutter',
          fingerprint: 'stable-fingerprint',
          readiness: { ready: true },
        },
      };
    },
    readiness: () => ({ ready: true }),
    runCommand: () => {
      commandCalls += 1;
      return {
        status: 1,
        diagnostic: 'Could not find package typo_from_source',
      };
    },
  });

  assert.equal(result.exitCode, EXIT_CODES.PRODUCT_FAILURE);
  assert.equal(result.result.status, 'product-failure');
  assert.equal(prepareCalls, 1);
  assert.equal(commandCalls, 1);
  assert.equal(result.result.recovery, undefined);
});

test('command-time repair stops stale when the toolchain fingerprint changes', (t) => {
  const root = fixture(t);
  let ready = false;
  let prepareCalls = 0;
  let commandCalls = 0;
  const result = runWithToolchain({
    root,
    profile: 'flutter',
    command: ['flutter', 'analyze'],
    prepare: ({ force }) => {
      prepareCalls += 1;
      if (force) ready = true;
      return {
        exitCode: 0,
        result: {
          profile: 'flutter',
          fingerprint: force ? 'changed-fingerprint' : 'stable-fingerprint',
          readiness: { ready },
        },
      };
    },
    readiness: () => ({ ready }),
    runCommand: () => {
      commandCalls += 1;
      return { status: 1, diagnostic: 'Could not find package http' };
    },
  });

  assert.equal(result.exitCode, EXIT_CODES.STALE);
  assert.equal(result.result.status, 'environment-failure');
  assert.equal(prepareCalls, 2);
  assert.equal(commandCalls, 1);
  assert.equal(result.result.recovery.status, 'stale');
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

test('default command runner replays large output without a fixed max-buffer ceiling', (t) => {
  const root = fixture(t);
  const outputPath = path.join(root, 'tmp', 'large-output.log');
  mkdirSync(path.dirname(outputPath), { recursive: true });
  const outputDescriptor = openSync(outputPath, 'w');
  const moduleUrl = pathToFileURL(
    path.resolve(import.meta.dirname, '../../scripts/run-with-toolchain.mjs'),
  ).href;
  const childCode = `
    import { defaultRunCommand } from ${JSON.stringify(moduleUrl)};
    const result = defaultRunCommand(
      process.execPath,
      ['-e', "process.stdout.write('x'.repeat(4 * 1024 * 1024))"],
      ${JSON.stringify(root)},
    );
    process.exit(result.status === 0 ? 0 : 1);
  `;
  const child = spawnSync(
    process.execPath,
    ['--input-type=module', '-e', childCode],
    {
      cwd: root,
      stdio: ['ignore', outputDescriptor, outputDescriptor],
      windowsHide: true,
    },
  );
  closeSync(outputDescriptor);

  assert.equal(child.status, 0);
  assert.ok(statSync(outputPath).size >= 4 * 1024 * 1024);
});

test('Windows Nest helper executes the local .cmd shim', { skip: process.platform !== 'win32' }, () => {
  const repositoryRoot = path.resolve(import.meta.dirname, '../..');
  const helper = path.join(repositoryRoot, 'backend-nest', 'scripts', 'run-nest-command.mjs');
  const child = spawnSync(process.execPath, [helper, '--', 'nest', '--version'], {
    cwd: repositoryRoot,
    encoding: 'utf8',
    windowsHide: true,
  });

  assert.equal(child.status, 0, child.stderr || child.stdout);
  assert.match(`${child.stdout || ''}${child.stderr || ''}`, /\d+\.\d+/);
});
