#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

export const EXIT_CODES = Object.freeze({
  PASS: 0,
  CONTRACT: 2,
  ENVIRONMENT: 5,
});

// Bumped when hydration behavior/commands change so old cached readiness is
// never trusted after a toolchain policy update.
const SCHEMA_VERSION = 2;
const PROFILE_ID = 'nestjs';
const FLUTTER_PROFILE_ID = 'flutter';
const ALL_PROFILE_ID = 'all';
const SUPPORTED_PROFILES = Object.freeze([
  PROFILE_ID,
  FLUTTER_PROFILE_ID,
  ALL_PROFILE_ID,
]);
const STATE_PATH = 'tmp/opshub-toolchain-state.json';
const NESTJS_REQUIRED_FILES = [
  'backend-nest/package.json',
  'backend-nest/package-lock.json',
  'backend-nest/prisma/schema.prisma',
  'backend-nest/prisma.config.ts',
];
const FLUTTER_REQUIRED_FILES = [
  'pubspec.yaml',
  'pubspec.lock',
  '.metadata',
];
const COMMAND_MAX_BUFFER_BYTES = 16 * 1024 * 1024;

const FLUTTER_GENERATED_TRACKED_PATHS = Object.freeze([
  /^lib\/l10n\/.+\.dart$/,
  /^ios\/Runner\/GeneratedPluginRegistrant\.(?:h|m)$/,
  /^linux\/flutter\/generated_plugin_registrant\.(?:cc|h)$/,
  /^linux\/flutter\/generated_plugins\.cmake$/,
  /^macos\/Flutter\/GeneratedPluginRegistrant\.swift$/,
  /^windows\/flutter\/generated_plugin_registrant\.(?:cc|h)$/,
  /^windows\/flutter\/generated_plugins\.cmake$/,
]);

class PreparationError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'PreparationError';
    this.code = code;
  }
}

function fail(code, message) {
  throw new PreparationError(code, message);
}

export function parseArgs(argv) {
  const options = {
    profile: PROFILE_ID,
    dryRun: false,
    force: false,
    json: null,
    help: false,
  };

  if (argv.includes('--help')) {
    return { ...options, help: true };
  }

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--profile') {
      const value = argv[index + 1];
      if (!value || value.startsWith('--'))
        fail(EXIT_CODES.CONTRACT, 'Thiếu giá trị cho --profile.');
      options.profile = value;
      index += 1;
      continue;
    }
    if (argument === '--dry-run') {
      options.dryRun = true;
      continue;
    }
    if (argument === '--force') {
      options.force = true;
      continue;
    }
    if (argument === '--json') {
      const value = argv[index + 1];
      if (!value || value.startsWith('--'))
        fail(EXIT_CODES.CONTRACT, 'Thiếu giá trị cho --json.');
      options.json = value;
      index += 1;
      continue;
    }
    fail(EXIT_CODES.CONTRACT, `Tham số không hỗ trợ: ${argument}`);
  }

  if (!SUPPORTED_PROFILES.includes(options.profile)) {
    fail(
      EXIT_CODES.CONTRACT,
      `Profile không hỗ trợ: ${options.profile}. Chọn một trong: ${SUPPORTED_PROFILES.join(', ')}.`,
    );
  }
  return options;
}

function hashFile(root, relativePath) {
  const absolutePath = path.resolve(root, relativePath);
  if (!existsSync(absolutePath)) {
    fail(EXIT_CODES.CONTRACT, `Thiếu file contract: ${relativePath}`);
  }
  return createHash('sha256').update(readFileSync(absolutePath)).digest('hex');
}

function requiredFilesForProfile(profile) {
  if (profile === PROFILE_ID) return NESTJS_REQUIRED_FILES;
  if (profile === FLUTTER_PROFILE_ID) return FLUTTER_REQUIRED_FILES;
  fail(EXIT_CODES.CONTRACT, `Không có manifest cho profile: ${profile}.`);
}

export function toolchainFingerprint(root, profile = PROFILE_ID) {
  const requiredFiles = requiredFilesForProfile(profile);
  const files = Object.fromEntries(
    requiredFiles.map((relativePath) => [
      relativePath,
      hashFile(root, relativePath),
    ]),
  );
  return createHash('sha256')
    .update(
      JSON.stringify({
        schemaVersion: SCHEMA_VERSION,
        profile,
        node: process.version,
        platform: process.platform,
        arch: process.arch,
        files,
      }),
    )
    .digest('hex');
}

function relativeStatePath(root) {
  return path.resolve(root, STATE_PATH);
}

function readState(root) {
  const statePath = relativeStatePath(root);
  if (!existsSync(statePath))
    return { schemaVersion: SCHEMA_VERSION, profiles: {} };
  try {
    const parsed = JSON.parse(readFileSync(statePath, 'utf8'));
    if (
      parsed?.schemaVersion !== SCHEMA_VERSION ||
      typeof parsed.profiles !== 'object'
    ) {
      return { schemaVersion: SCHEMA_VERSION, profiles: {} };
    }
    return parsed;
  } catch {
    return { schemaVersion: SCHEMA_VERSION, profiles: {} };
  }
}

function writeState(root, state) {
  const statePath = relativeStatePath(root);
  mkdirSync(path.dirname(statePath), { recursive: true });
  writeFileSync(statePath, `${JSON.stringify(state, null, 2)}\n`, 'utf8');
}

function nestExecutable(name) {
  return process.platform === 'win32' ? `${name}.cmd` : name;
}

function flutterExecutable() {
  return process.platform === 'win32' ? 'flutter.bat' : 'flutter';
}

function readinessForProfile(root, profile) {
  if (profile === FLUTTER_PROFILE_ID) {
    return {
      pubspec: existsSync(path.resolve(root, 'pubspec.yaml')),
      lockfile: existsSync(path.resolve(root, 'pubspec.lock')),
      packageConfig: existsSync(
        path.resolve(root, '.dart_tool', 'package_config.json'),
      ),
    };
  }
  const nodeModules = path.resolve(root, 'backend-nest/node_modules');
  const nestBinary = path.join(nodeModules, '.bin', nestExecutable('nest'));
  const prismaPackage = path.join(
    nodeModules,
    '@prisma',
    'client',
    'package.json',
  );
  const prismaGenerated = path.join(nodeModules, '.prisma', 'client');
  return {
    nestBinary: existsSync(nestBinary),
    prismaPackage: existsSync(prismaPackage),
    prismaGenerated: existsSync(prismaGenerated),
  };
}

function isReadyForProfile(value, profile) {
  if (profile === FLUTTER_PROFILE_ID) {
    return value.pubspec && value.lockfile && value.packageConfig;
  }
  return value.nestBinary && value.prismaPackage && value.prismaGenerated;
}

function normalizedStatusPath(value) {
  return String(value).replaceAll('\\', '/');
}

function statusEntries(root) {
  const result = spawnSync(
    'git',
    ['status', '--porcelain=v1', '--untracked-files=all'],
    {
      cwd: root,
      encoding: 'utf8',
      windowsHide: true,
      maxBuffer: COMMAND_MAX_BUFFER_BYTES,
    },
  );
  if (result.error || result.status !== 0) {
    fail(
      EXIT_CODES.ENVIRONMENT,
      `Không đọc được trạng thái worktree trước/sau Flutter preflight: ${
        result.error?.message || String(result.stderr || '').trim() || `exit ${result.status}`
      }`,
    );
  }
  return String(result.stdout || '')
    .split(/\r?\n/)
    .map((line) => line.trimEnd())
    .filter(Boolean)
    .map((line) => ({
      raw: line,
      path: normalizedStatusPath(line.slice(3)),
      untracked: line.startsWith('?? '),
    }));
}

function isFlutterGeneratedTrackedPath(relativePath) {
  return FLUTTER_GENERATED_TRACKED_PATHS.some((pattern) => pattern.test(relativePath));
}

function restoreGeneratedPath(root, relativePath) {
  const result = spawnSync(
    'git',
    ['restore', '--worktree', '--', relativePath],
    {
      cwd: root,
      encoding: 'utf8',
      windowsHide: true,
      maxBuffer: COMMAND_MAX_BUFFER_BYTES,
    },
  );
  if (result.error || result.status !== 0) {
    fail(
      EXIT_CODES.ENVIRONMENT,
      `Không thể dọn generated Flutter path ${relativePath}: ${
        result.error?.message || String(result.stderr || '').trim() || `exit ${result.status}`
      }`,
    );
  }
}

function reconcileFlutterGeneratedChanges(root, beforeEntries) {
  const beforeByPath = new Map(beforeEntries.map((entry) => [entry.path, entry]));
  const afterEntries = statusEntries(root);
  const introduced = [];

  for (const entry of afterEntries) {
    const before = beforeByPath.get(entry.path);
    if (!before || before.raw !== entry.raw) introduced.push({ before, after: entry });
  }

  const unsafe = [];
  for (const change of introduced) {
    const { before, after } = change;
    if (after.untracked) {
      unsafe.push(`${after.path} (new non-ignored file)`);
      continue;
    }
    if (!isFlutterGeneratedTrackedPath(after.path)) {
      unsafe.push(`${after.path} (tracked file outside generated allowlist)`);
      continue;
    }
    if (before) {
      unsafe.push(`${after.path} (pre-existing user change was modified)`);
      continue;
    }
    restoreGeneratedPath(root, after.path);
  }

  const remaining = statusEntries(root).filter((entry) => {
    const before = beforeByPath.get(entry.path);
    return !before || before.raw !== entry.raw;
  });
  if (remaining.length > 0) {
    unsafe.push(...remaining.map((entry) => `${entry.path} (cleanup incomplete)`));
  }
  if (unsafe.length > 0) {
    fail(
      EXIT_CODES.ENVIRONMENT,
      `Flutter pub get làm thay đổi worktree ngoài generated allowlist; review trước khi chạy tiếp:\n${[
        ...new Set(unsafe),
      ].join('\n')}`,
    );
  }
  return {
    introducedPaths: introduced.map(({ after }) => after.path),
    restoredPaths: introduced
      .filter(({ after }) => isFlutterGeneratedTrackedPath(after.path) && !after.untracked)
      .map(({ after }) => after.path),
    status: 'clean',
  };
}

function sanitizedExecutable(executable) {
  return path.basename(executable).replaceAll('\\', '/');
}

function runStep(root, step) {
  const result = spawnSync(step.executable, step.argv, {
    cwd: step.cwd,
    encoding: 'utf8',
    windowsHide: true,
    shell:
      process.platform === 'win32' && /\.(?:cmd|bat)$/i.test(step.executable),
    stdio: ['inherit', 'pipe', 'pipe'],
    maxBuffer: 16 * 1024 * 1024,
  });
  const stdout = String(result.stdout || '');
  const stderr = String(result.stderr || '');
  if (stdout) process.stdout.write(stdout);
  if (stderr) process.stderr.write(stderr);
  if (result.error) {
    return {
      id: step.id,
      executable: sanitizedExecutable(step.executable),
      argv: step.argv,
      status: 'environment-failure',
      exitCode: null,
      error: result.error.message.slice(0, 240),
    };
  }
  return {
    id: step.id,
    executable: sanitizedExecutable(step.executable),
    argv: step.argv,
    status: result.status === 0 ? 'passed' : 'environment-failure',
    exitCode: result.status,
    ...(result.status === 0
      ? {}
      : { error: `${stdout}\n${stderr}`.trim().slice(-240) }),
  };
}

function stepsFor(root, profile) {
  if (profile === FLUTTER_PROFILE_ID) {
    return [
      {
        id: 'flutter-pub-get',
        executable: flutterExecutable(),
        argv: ['pub', 'get', '--enforce-lockfile'],
        cwd: path.resolve(root),
      },
    ];
  }
  const backendRoot = path.resolve(root, 'backend-nest');
  return [
      {
        id: 'nestjs-npm-ci',
        executable: nestExecutable('npm'),
        argv: ['ci', '--include=dev', '--ignore-scripts'],
      cwd: backendRoot,
    },
    {
      id: 'nestjs-prisma-generate',
      executable: nestExecutable('npx'),
      argv: ['--no-install', 'prisma', 'generate'],
      cwd: backendRoot,
    },
  ];
}

function resultBase(root, profile, fingerprint, options) {
  return {
    schemaVersion: SCHEMA_VERSION,
    profile,
    fingerprint,
    statePath: STATE_PATH,
    dryRun: options.dryRun,
    forced: options.force,
    readiness: readinessForProfile(root, profile),
    steps: [],
  };
}

function prepareSingleProfile({
  resolvedRoot,
  profile,
  dryRun,
  force,
  runStepFn,
} = {}) {
  const fingerprint = toolchainFingerprint(resolvedRoot, profile);
  const options = { dryRun, force };
  const result = resultBase(resolvedRoot, profile, fingerprint, options);
  const state = readState(resolvedRoot);
  const previous = state.profiles?.[profile];
  const readyBefore = isReadyForProfile(result.readiness, profile);
  if (!force && readyBefore && previous?.fingerprint === fingerprint) {
    result.status = 'cached';
    return { exitCode: EXIT_CODES.PASS, result };
  }

  result.status = dryRun ? 'planned' : 'preparing';
  const steps = stepsFor(resolvedRoot, profile);
  result.steps = steps.map((step) => ({
    id: step.id,
    executable: sanitizedExecutable(step.executable),
    argv: step.argv,
  }));
  if (dryRun) return { exitCode: EXIT_CODES.PASS, result };

  const beforeEntries = profile === FLUTTER_PROFILE_ID ? statusEntries(resolvedRoot) : null;
  result.steps = [];
  for (const step of steps) {
    const stepResult = runStepFn(resolvedRoot, step);
    result.steps.push(stepResult);
    if (profile === FLUTTER_PROFILE_ID) {
      try {
        result.worktree = reconcileFlutterGeneratedChanges(
          resolvedRoot,
          beforeEntries,
        );
      } catch (error) {
        result.status = 'environment-failure';
        result.error = String(error?.message || error).slice(0, 800);
        result.readiness = readinessForProfile(resolvedRoot, profile);
        return { exitCode: EXIT_CODES.ENVIRONMENT, result };
      }
    }
    if (stepResult.status !== 'passed') {
      result.status = 'environment-failure';
      result.readiness = readinessForProfile(resolvedRoot, profile);
      return { exitCode: EXIT_CODES.ENVIRONMENT, result };
    }
  }

  result.readiness = readinessForProfile(resolvedRoot, profile);
  if (!isReadyForProfile(result.readiness, profile)) {
    result.status = 'environment-failure';
    return { exitCode: EXIT_CODES.ENVIRONMENT, result };
  }
  state.schemaVersion = SCHEMA_VERSION;
  state.profiles = {
    ...(state.profiles || {}),
    [profile]: {
      fingerprint,
      ready: true,
      preparedAtUtc: new Date().toISOString(),
    },
  };
  writeState(resolvedRoot, state);
  result.status = 'prepared';
  return { exitCode: EXIT_CODES.PASS, result };
}

export function prepareTaskToolchain({
  root = process.cwd(),
  profile = PROFILE_ID,
  dryRun = false,
  force = false,
  runStepFn = runStep,
} = {}) {
  const resolvedRoot = path.resolve(root);
  if (!SUPPORTED_PROFILES.includes(profile)) {
    fail(
      EXIT_CODES.CONTRACT,
      `Profile không hỗ trợ: ${profile}. Chọn một trong: ${SUPPORTED_PROFILES.join(', ')}.`,
    );
  }
  if (profile !== ALL_PROFILE_ID) {
    return prepareSingleProfile({
      resolvedRoot,
      profile,
      dryRun,
      force,
      runStepFn,
    });
  }

  const profiles = [];
  for (const profileId of [PROFILE_ID, FLUTTER_PROFILE_ID]) {
    const prepared = prepareSingleProfile({
      resolvedRoot,
      profile: profileId,
      dryRun,
      force,
      runStepFn,
    });
    profiles.push(prepared);
    if (prepared.exitCode !== EXIT_CODES.PASS) break;
  }
  const failed = profiles.find((entry) => entry.exitCode !== EXIT_CODES.PASS);
  return {
    exitCode: failed?.exitCode ?? EXIT_CODES.PASS,
    result: {
      schemaVersion: SCHEMA_VERSION,
      profile: ALL_PROFILE_ID,
      statePath: STATE_PATH,
      dryRun,
      forced: force,
      status: failed
        ? 'environment-failure'
        : profiles.every((entry) => entry.result.status === 'cached')
          ? 'cached'
          : dryRun
            ? 'planned'
            : 'prepared',
      profiles: profiles.map((entry) => entry.result),
    },
  };
}

function help() {
  return (
    `Usage: node scripts/prepare-task-toolchain.mjs [options]\n\n` +
    `  --profile nestjs|flutter|all  Prepare the selected local toolchain (default: nestjs)\n` +
    `  --dry-run                    Report required steps without executing them\n` +
    `  --force                      Re-run hydration even when the fingerprint is cached\n` +
    `  --json <path>          Write schema-v1 result JSON\n`
  );
}

export function main(
  argv = process.argv.slice(2),
  { root = process.cwd() } = {},
) {
  let options;
  try {
    options = parseArgs(argv);
    if (options.help) {
      console.log(help());
      return EXIT_CODES.PASS;
    }
    const { exitCode, result } = prepareTaskToolchain({
      root,
      profile: options.profile,
      dryRun: options.dryRun,
      force: options.force,
    });
    if (options.json) {
      const outputPath = path.resolve(root, options.json);
      mkdirSync(path.dirname(outputPath), { recursive: true });
      writeFileSync(outputPath, `${JSON.stringify(result, null, 2)}\n`, 'utf8');
    }
    console.log(JSON.stringify(result, null, 2));
    return exitCode;
  } catch (error) {
    const code =
      error instanceof PreparationError ? error.code : EXIT_CODES.ENVIRONMENT;
    const result = {
      schemaVersion: SCHEMA_VERSION,
      status: 'failed',
      code,
      error: String(error?.message || error).slice(0, 500),
    };
    if (options?.json) {
      const outputPath = path.resolve(root, options.json);
      mkdirSync(path.dirname(outputPath), { recursive: true });
      writeFileSync(outputPath, `${JSON.stringify(result, null, 2)}\n`, 'utf8');
    }
    console.error(`TOOLCHAIN PREPARE FAILED (${code}): ${result.error}`);
    return code;
  }
}

const invoked =
  process.argv[1] &&
  pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invoked) process.exitCode = main();
