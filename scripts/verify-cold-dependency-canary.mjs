#!/usr/bin/env node

import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

export const EXIT_CODES = Object.freeze({
  PASS: 0,
  CONTRACT: 2,
  ENVIRONMENT: 5,
});

class CanaryError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'CanaryError';
    this.code = code;
  }
}

function assertContract(condition, message) {
  if (!condition) throw new CanaryError(EXIT_CODES.CONTRACT, message);
}

function assertEnvironment(condition, message) {
  if (!condition) throw new CanaryError(EXIT_CODES.ENVIRONMENT, message);
}

function profileResult(report, id) {
  return report?.preparation?.profiles?.find((entry) => entry?.profile === id);
}

function validateProfile(report, id) {
  const entry = profileResult(report, id);
  assertEnvironment(entry, `Missing ${id} preparation result.`);
  assertEnvironment(
    ['prepared', 'cached'].includes(entry.status),
    `${id} preparation did not complete: ${entry.status || 'unknown'}.`,
  );
  assertEnvironment(entry.readiness?.writableGeneratedRoots?.ready === true, `${id} generated roots are not writable.`);
  return entry;
}

function assertReadOnlyCleared(target) {
  if (process.platform !== 'win32' || !existsSync(target)) return;
  const result = spawnSync('attrib', [target], {
    encoding: 'utf8',
    windowsHide: true,
  });
  assertEnvironment(
    !result.error && result.status === 0,
    `Cannot inspect Windows attributes for ${target}.`,
  );
  const line = String(result.stdout || '')
    .split(/\r?\n/)
    .find((value) => value.trim());
  assertEnvironment(line && !line.slice(0, 8).includes('R'), `ReadOnly attribute remains on ${target}.`);
}

export function verifyColdDependencyCanary({
  report,
  root = process.cwd(),
  checkFilesystem = process.platform === 'win32',
} = {}) {
  assertContract(report && typeof report === 'object', 'Doctor report must be an object.');
  assertContract(report.profile === 'all', 'Canary must prepare the all profile.');
  assertEnvironment(report.status === 'passed', `Toolchain doctor failed: ${report.status || 'unknown'}.`);

  const nest = validateProfile(report, 'nestjs');
  const flutter = validateProfile(report, 'flutter');
  assertEnvironment(
    Array.isArray(nest.readiness?.missingDirectDependencies) &&
      nest.readiness.missingDirectDependencies.length === 0 &&
      Array.isArray(nest.readiness?.missingLockPackages) &&
      nest.readiness.missingLockPackages.length === 0 &&
      Array.isArray(nest.readiness?.missingPackageEntrypoints) &&
      nest.readiness.missingPackageEntrypoints.length === 0 &&
      nest.readiness?.prismaGenerated === true,
    'Nest dependency graph or Prisma output is incomplete.',
  );
  assertEnvironment(
    Array.isArray(flutter.readiness?.missingPackages) &&
      flutter.readiness.missingPackages.length === 0 &&
      Array.isArray(flutter.readiness?.missingPlugins) &&
      flutter.readiness.missingPlugins.length === 0 &&
      flutter.readiness?.packageConfigReadable === true &&
      flutter.readiness?.pluginMetadataReadable === true,
    'Flutter package or plugin materialization is incomplete.',
  );

  const materializedPaths = [
    'backend-nest/node_modules',
    'backend-nest/node_modules/.bin',
    'backend-nest/node_modules/.prisma/client',
    '.dart_tool/package_config.json',
    '.flutter-plugins-dependencies',
  ];
  if (checkFilesystem) {
    for (const relativePath of materializedPaths) {
      assertEnvironment(
        existsSync(path.resolve(root, relativePath)),
        `Expected materialized path is missing: ${relativePath}.`,
      );
    }
    for (const relativePath of ['backend-nest', 'lib/l10n']) {
      assertReadOnlyCleared(path.resolve(root, relativePath));
    }
  }

  return {
    schemaVersion: 1,
    status: 'passed',
    root: '<worktree>',
    profiles: ['nestjs', 'flutter'],
    materializedPaths: checkFilesystem ? materializedPaths : [],
    generatedRootsWritable: true,
  };
}

function parseArgs(argv) {
  const options = { input: null, root: process.cwd() };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--input' || argument === '--root') {
      const value = argv[index + 1];
      if (!value || value.startsWith('--')) {
        throw new CanaryError(EXIT_CODES.CONTRACT, `${argument} requires a value.`);
      }
      if (argument === '--input') options.input = value;
      if (argument === '--root') options.root = path.resolve(value);
      index += 1;
      continue;
    }
    if (argument === '--help' || argument === '-h') {
      options.help = true;
      continue;
    }
    throw new CanaryError(EXIT_CODES.CONTRACT, `Unknown argument: ${argument}.`);
  }
  if (!options.help && !options.input) {
    throw new CanaryError(EXIT_CODES.CONTRACT, '--input is required.');
  }
  return options;
}

function help() {
  return 'Usage: node scripts/verify-cold-dependency-canary.mjs --input <doctor-json> [--root <worktree>]';
}

export function main(argv = process.argv.slice(2), { cwd = process.cwd() } = {}) {
  try {
    const options = parseArgs(argv);
    if (options.help) {
      console.log(help());
      return EXIT_CODES.PASS;
    }
    const root = path.resolve(cwd, options.root);
    const input = path.resolve(root, options.input);
    const relative = path.relative(root, input);
    assertContract(
      relative !== '..' && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative),
      '--input escapes the worktree.',
    );
    assertEnvironment(existsSync(input), `Doctor report does not exist: ${options.input}.`);
    const report = JSON.parse(readFileSync(input, 'utf8'));
    const result = verifyColdDependencyCanary({ report, root });
    console.log(JSON.stringify(result, null, 2));
    return EXIT_CODES.PASS;
  } catch (error) {
    const code = error instanceof CanaryError ? error.code : EXIT_CODES.ENVIRONMENT;
    console.error(`COLD DEPENDENCY CANARY FAILED (${code}): ${String(error?.message || error).slice(0, 800)}`);
    return code;
  }
}

const invoked =
  process.argv[1] &&
  pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invoked) process.exitCode = main();
