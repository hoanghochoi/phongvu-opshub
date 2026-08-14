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

const SCHEMA_VERSION = 1;
const PROFILE_ID = 'nestjs';
const STATE_PATH = 'tmp/opshub-toolchain-state.json';
const REQUIRED_FILES = [
  'backend-nest/package.json',
  'backend-nest/package-lock.json',
  'backend-nest/prisma/schema.prisma',
  'backend-nest/prisma.config.ts',
];

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

  if (options.profile !== PROFILE_ID) {
    fail(
      EXIT_CODES.CONTRACT,
      `Profile không hỗ trợ: ${options.profile}. Slice này chỉ hỗ trợ ${PROFILE_ID}.`,
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

export function toolchainFingerprint(root) {
  const files = Object.fromEntries(
    REQUIRED_FILES.map((relativePath) => [
      relativePath,
      hashFile(root, relativePath),
    ]),
  );
  return createHash('sha256')
    .update(
      JSON.stringify({
        schemaVersion: SCHEMA_VERSION,
        profile: PROFILE_ID,
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

function readiness(root) {
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

function isReady(value) {
  return value.nestBinary && value.prismaPackage && value.prismaGenerated;
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

function stepsFor(root) {
  const backendRoot = path.resolve(root, 'backend-nest');
  return [
    {
      id: 'nestjs-npm-ci',
      executable: nestExecutable('npm'),
      argv: ['ci', '--ignore-scripts'],
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

function resultBase(root, fingerprint, options) {
  return {
    schemaVersion: SCHEMA_VERSION,
    profile: PROFILE_ID,
    fingerprint,
    statePath: STATE_PATH,
    dryRun: options.dryRun,
    forced: options.force,
    readiness: readiness(root),
    steps: [],
  };
}

export function prepareTaskToolchain({
  root = process.cwd(),
  profile = PROFILE_ID,
  dryRun = false,
  force = false,
  runStepFn = runStep,
} = {}) {
  const resolvedRoot = path.resolve(root);
  if (profile !== PROFILE_ID) {
    fail(
      EXIT_CODES.CONTRACT,
      `Profile không hỗ trợ: ${profile}. Slice này chỉ hỗ trợ ${PROFILE_ID}.`,
    );
  }
  const fingerprint = toolchainFingerprint(resolvedRoot);
  const options = { dryRun, force };
  const result = resultBase(resolvedRoot, fingerprint, options);
  const state = readState(resolvedRoot);
  const previous = state.profiles?.[PROFILE_ID];
  const readyBefore = isReady(result.readiness);
  if (!force && readyBefore && previous?.fingerprint === fingerprint) {
    result.status = 'cached';
    return { exitCode: EXIT_CODES.PASS, result };
  }

  result.status = dryRun ? 'planned' : 'preparing';
  result.steps = stepsFor(resolvedRoot).map((step) => ({
    id: step.id,
    executable: sanitizedExecutable(step.executable),
    argv: step.argv,
  }));
  if (dryRun) return { exitCode: EXIT_CODES.PASS, result };

  result.steps = [];
  for (const step of stepsFor(resolvedRoot)) {
    const stepResult = runStepFn(resolvedRoot, step);
    result.steps.push(stepResult);
    if (stepResult.status !== 'passed') {
      result.status = 'environment-failure';
      result.readiness = readiness(resolvedRoot);
      return { exitCode: EXIT_CODES.ENVIRONMENT, result };
    }
  }

  result.readiness = readiness(resolvedRoot);
  if (!isReady(result.readiness)) {
    result.status = 'environment-failure';
    return { exitCode: EXIT_CODES.ENVIRONMENT, result };
  }
  state.schemaVersion = SCHEMA_VERSION;
  state.profiles = {
    ...(state.profiles || {}),
    [PROFILE_ID]: {
      fingerprint,
      ready: true,
      preparedAtUtc: new Date().toISOString(),
    },
  };
  writeState(resolvedRoot, state);
  result.status = 'prepared';
  return { exitCode: EXIT_CODES.PASS, result };
}

function help() {
  return (
    `Usage: node scripts/prepare-task-toolchain.mjs [options]\n\n` +
    `  --profile nestjs       Prepare backend-nest dependencies and Prisma client (default)\n` +
    `  --dry-run              Report required steps without executing them\n` +
    `  --force                Re-run npm ci and Prisma generation\n` +
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
