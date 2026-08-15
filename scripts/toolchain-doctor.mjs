#!/usr/bin/env node

import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

import {
  EXIT_CODES as PREPARE_EXIT_CODES,
  inspectToolchainReadiness,
  prepareTaskToolchain,
} from './prepare-task-toolchain.mjs';

export const EXIT_CODES = Object.freeze({
  PASS: 0,
  CONTRACT: 2,
  ENVIRONMENT: 5,
});

const SCHEMA_VERSION = 1;
const SUPPORTED_PROFILES = new Set(['nestjs', 'flutter', 'all']);

class DoctorError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'DoctorError';
    this.code = code;
  }
}

function fail(code, message) {
  throw new DoctorError(code, message);
}

export function parseArgs(argv) {
  const options = {
    root: '.',
    profile: 'all',
    dryRun: false,
    check: false,
    force: false,
    json: null,
    help: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--root' || argument === '--profile' || argument === '--json') {
      const value = argv[index + 1];
      if (!value || value.startsWith('--')) {
        fail(EXIT_CODES.CONTRACT, `${argument} requires a value`);
      }
      if (argument === '--root') options.root = value;
      if (argument === '--profile') options.profile = value;
      if (argument === '--json') options.json = value;
      index += 1;
      continue;
    }
    if (argument === '--dry-run') {
      options.dryRun = true;
      continue;
    }
    if (argument === '--check') {
      options.check = true;
      continue;
    }
    if (argument === '--force') {
      options.force = true;
      continue;
    }
    if (argument === '--help' || argument === '-h') {
      options.help = true;
      continue;
    }
    fail(EXIT_CODES.CONTRACT, `Unknown argument: ${argument}`);
  }

  if (!SUPPORTED_PROFILES.has(options.profile)) {
    fail(
      EXIT_CODES.CONTRACT,
      `Unsupported profile: ${options.profile}; expected nestjs, flutter or all`,
    );
  }
  if (options.check && options.force) {
    fail(EXIT_CODES.CONTRACT, '--check cannot be combined with --force');
  }
  return options;
}

function resolveRoot(root, cwd) {
  const resolved = path.resolve(cwd, root || '.');
  if (!existsSync(resolved)) {
    fail(EXIT_CODES.CONTRACT, `Worktree does not exist: ${root}`);
  }
  const result = spawnSync('git', ['-C', resolved, 'rev-parse', '--show-toplevel'], {
    encoding: 'utf8',
    windowsHide: true,
    maxBuffer: 1024 * 1024,
  });
  if (result.error || result.status !== 0) {
    fail(EXIT_CODES.CONTRACT, `Root is not a Git worktree: ${root}`);
  }
  const gitRoot = path.resolve(String(result.stdout || '').trim());
  if (!existsSync(gitRoot)) {
    fail(EXIT_CODES.CONTRACT, `Git worktree root does not exist: ${root}`);
  }
  return gitRoot;
}

function resolveOutputPath(root, outputPath) {
  if (!outputPath) return null;
  const resolved = path.resolve(root, outputPath);
  const relative = path.relative(root, resolved);
  if (
    relative === '..' ||
    relative.startsWith(`..${path.sep}`) ||
    path.isAbsolute(relative)
  ) {
    fail(EXIT_CODES.CONTRACT, '--json path escapes repository root');
  }
  return resolved;
}

function writeResult(root, outputPath, result) {
  if (!outputPath) return;
  mkdirSync(path.dirname(outputPath), { recursive: true });
  writeFileSync(outputPath, `${JSON.stringify(result, null, 2)}\n`, 'utf8');
}

export function doctorToolchain({
  root = process.cwd(),
  profile = 'all',
  dryRun = false,
  check = false,
  force = false,
  prepare = prepareTaskToolchain,
} = {}) {
  const resolvedRoot = resolveRoot(root, process.cwd());
  // `--check` is intentionally read-only. It must never turn a readiness
  // assertion into an implicit dependency writer.
  const effectiveDryRun = dryRun || check;
  const preparation = prepare({
    root: resolvedRoot,
    profile,
    dryRun: effectiveDryRun,
    force: check ? false : force,
  });
  let exitCode =
    preparation.exitCode === PREPARE_EXIT_CODES.PASS
      ? EXIT_CODES.PASS
      : preparation.exitCode === PREPARE_EXIT_CODES.CONTRACT
        ? EXIT_CODES.CONTRACT
        : EXIT_CODES.ENVIRONMENT;
  let readiness = null;
  if (exitCode === EXIT_CODES.PASS && check) {
    readiness = inspectToolchainReadiness({ root: resolvedRoot, profile });
    if (!readiness.ready) exitCode = EXIT_CODES.ENVIRONMENT;
  }
  const readinessError =
    readiness && !readiness.ready
      ? `Toolchain readiness is incomplete for profile ${profile}; run the non-dry doctor to hydrate dependencies.`
      : null;
  return {
    exitCode,
    result: {
      schemaVersion: SCHEMA_VERSION,
      operation: 'toolchain-doctor',
      root: '<worktree>',
      profile,
      dryRun: effectiveDryRun,
      check,
      forced: check ? false : force,
      status: exitCode === EXIT_CODES.PASS ? 'passed' : 'failed',
      preparation: preparation.result,
      ...(readiness ? { readiness } : {}),
      ...(readinessError ? { error: readinessError } : {}),
      ...(exitCode === EXIT_CODES.PASS
        ? {}
        : {
            remediation:
              'node scripts/toolchain-doctor.mjs --root <worktree> --profile ' +
              `${profile} --force`,
          }),
    },
  };
}

function help() {
  return `Usage: node scripts/toolchain-doctor.mjs [options]\n\n` +
    `  --root <path>              Existing worktree to inspect/repair\n` +
    `  --profile nestjs|flutter|all\n` +
    `  --dry-run                  Report readiness without hydrating\n` +
    `  --check                    Fail closed when current readiness is incomplete (read-only)\n` +
    `  --force                    Rehydrate even when readiness is cached\n` +
    `  --json <path>              Write sanitized schema-v1 result JSON\n`;
}

export function main(argv = process.argv.slice(2), { cwd = process.cwd() } = {}) {
  let options;
  try {
    options = parseArgs(argv);
    if (options.help) {
      console.log(help());
      return EXIT_CODES.PASS;
    }
    const root = resolveRoot(options.root, cwd);
    const outputPath = resolveOutputPath(root, options.json);
    const result = doctorToolchain({
      root,
      profile: options.profile,
      dryRun: options.dryRun,
      check: options.check,
      force: options.force,
    });
    writeResult(root, outputPath, result.result);
    console.log(JSON.stringify(result.result, null, 2));
    return result.exitCode;
  } catch (error) {
    const code = error instanceof DoctorError ? error.code : EXIT_CODES.ENVIRONMENT;
    const result = {
      schemaVersion: SCHEMA_VERSION,
      operation: 'toolchain-doctor',
      status: 'failed',
      code,
      error: String(error?.message || error).slice(0, 800),
    };
    if (options?.json) {
      try {
        const root = resolveRoot(options.root, cwd);
        writeResult(root, resolveOutputPath(root, options.json), result);
      } catch {
        // Preserve the primary diagnostic when the requested root is invalid.
      }
    }
    console.error(`TOOLCHAIN DOCTOR FAILED (${code}): ${result.error}`);
    return code;
  }
}

const invoked =
  process.argv[1] &&
  pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invoked) process.exitCode = main();
