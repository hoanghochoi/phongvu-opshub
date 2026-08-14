#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import {
  existsSync,
  mkdirSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import {
  EXIT_CODES as PREPARE_EXIT_CODES,
  prepareTaskToolchain,
} from './prepare-task-toolchain.mjs';

export const EXIT_CODES = Object.freeze({
  PASS: 0,
  CONTRACT: 2,
  PRODUCT_FAILURE: 3,
  STALE: 4,
  ENVIRONMENT: 5,
});

const SCHEMA_VERSION = 1;
const SUPPORTED_PROFILES = new Set(['nestjs', 'flutter', 'all']);
const FLUTTER_GATED_COMMANDS = new Set(['analyze', 'test', 'build']);

class GateError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'GateError';
    this.code = code;
  }
}

function fail(code, message) {
  throw new GateError(code, message);
}

export function parseArgs(argv) {
  const options = {
    root: null,
    cwd: '.',
    profile: 'all',
    json: null,
    dryRun: false,
    force: false,
    preflightOnly: false,
    command: null,
  };

  const separator = argv.indexOf('--');
  const optionArgs = separator >= 0 ? argv.slice(0, separator) : argv;
  if (separator >= 0) {
    options.command = argv.slice(separator + 1);
  }

  for (let index = 0; index < optionArgs.length; index += 1) {
    const argument = optionArgs[index];
    if (argument === '--root' || argument === '--cwd' || argument === '--profile' || argument === '--json') {
      const value = optionArgs[index + 1];
      if (!value || value.startsWith('--')) {
        fail(EXIT_CODES.CONTRACT, `${argument} requires a value`);
      }
      if (argument === '--root') options.root = value;
      if (argument === '--cwd') options.cwd = value;
      if (argument === '--profile') options.profile = value;
      if (argument === '--json') options.json = value;
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
    if (argument === '--preflight-only') {
      options.preflightOnly = true;
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
  if (options.preflightOnly && options.command?.length) {
    fail(EXIT_CODES.CONTRACT, '--preflight-only cannot be combined with a command');
  }
  if (!options.preflightOnly && !options.dryRun && (!options.command || options.command.length === 0)) {
    fail(EXIT_CODES.CONTRACT, 'A command is required after --');
  }
  return options;
}

function resolveInside(root, relativePath, label) {
  const resolved = path.resolve(root, relativePath || '.');
  const relative = path.relative(root, resolved);
  if (
    relative === '..' ||
    relative.startsWith(`..${path.sep}`) ||
    path.isAbsolute(relative)
  ) {
    fail(EXIT_CODES.CONTRACT, `${label} escapes repository root`);
  }
  if (!existsSync(resolved) || !statSync(resolved).isDirectory()) {
    fail(EXIT_CODES.CONTRACT, `${label} does not exist: ${relativePath}`);
  }
  return resolved;
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

function platformExecutable(executable) {
  if (process.platform !== 'win32') return executable;
  const basename = path.basename(executable).toLowerCase();
  if (basename === 'flutter') return 'flutter.bat';
  if (basename === 'npm') return 'npm.cmd';
  if (basename === 'npx') return 'npx.cmd';
  return executable;
}

function flutterCommandArgs(executable, argv) {
  const basename = path.basename(executable).toLowerCase();
  if (!basename.startsWith('flutter')) return [...argv];
  const command = argv[0]?.toLowerCase();
  if (!FLUTTER_GATED_COMMANDS.has(command)) return [...argv];
  if (argv.some((argument) => argument === '--no-pub')) return [...argv];
  return [...argv, '--no-pub'];
}

function sanitize(value, root) {
  let text = String(value || '');
  const normalizedRoot = path.resolve(root);
  text = text.replaceAll(normalizedRoot, '<worktree>');
  text = text.replaceAll(normalizedRoot.replaceAll('\\', '/'), '<worktree>');
  text = text.replace(/\b[A-Za-z]:[\/][^\s'"<>]+/g, '<path>');
  return text.slice(-800);
}

function preparationFingerprint(preparation) {
  if (!preparation || typeof preparation !== 'object') return null;
  if (preparation.profile === 'all') {
    return preparation.profiles
      ?.map((profile) => profile.fingerprint)
      .filter(Boolean)
      .join(':') || null;
  }
  return preparation.fingerprint || null;
}

function commandFingerprint({ root, profile, cwd, executable, argv, preparation }) {
  return createHash('sha256')
    .update(
      JSON.stringify({
        schemaVersion: SCHEMA_VERSION,
        profile,
        cwd: path.relative(root, cwd).replaceAll('\\', '/') || '.',
        executable,
        argv,
        preparation: preparationFingerprint(preparation),
      }),
    )
    .digest('hex');
}

function writeResult(root, outputPath, result) {
  if (!outputPath) return;
  mkdirSync(path.dirname(outputPath), { recursive: true });
  writeFileSync(outputPath, `${JSON.stringify(result, null, 2)}\n`, 'utf8');
}

function defaultRunCommand(executable, argv, cwd) {
  return spawnSync(executable, argv, {
    cwd,
    encoding: 'utf8',
    windowsHide: true,
    shell: process.platform === 'win32' && /\.(?:cmd|bat)$/i.test(executable),
    stdio: 'inherit',
  });
}

export function runWithToolchain({
  root = process.cwd(),
  profile = 'all',
  cwd = '.',
  command = [],
  dryRun = false,
  force = false,
  preflightOnly = false,
  json = null,
  prepare = prepareTaskToolchain,
  runCommand = defaultRunCommand,
} = {}) {
  const resolvedRoot = path.resolve(root);
  if (!SUPPORTED_PROFILES.has(profile)) {
    fail(EXIT_CODES.CONTRACT, `Unsupported profile: ${profile}`);
  }
  if (!existsSync(resolvedRoot)) {
    fail(EXIT_CODES.CONTRACT, `Repository root does not exist: ${root}`);
  }
  const resolvedCwd = resolveInside(resolvedRoot, cwd, 'Command cwd');
  if (preflightOnly && command.length > 0) {
    fail(EXIT_CODES.CONTRACT, '--preflight-only cannot be combined with a command');
  }
  if (!preflightOnly && !dryRun && command.length === 0) {
    fail(EXIT_CODES.CONTRACT, 'A command is required');
  }

  const startedAt = Date.now();
  const executable = command.length > 0 ? platformExecutable(command[0]) : null;
  const argv = executable ? flutterCommandArgs(executable, command.slice(1)) : [];
  const outputPath = resolveOutputPath(resolvedRoot, json);
  const result = {
    schemaVersion: SCHEMA_VERSION,
    status: 'preparing',
    profile,
    root: '<worktree>',
    command: executable
      ? {
          cwd: path.relative(resolvedRoot, resolvedCwd).replaceAll('\\', '/') || '.',
          executable,
          argv,
        }
      : null,
    preparation: null,
    fingerprint: null,
    durationMs: 0,
  };

  let preparation;
  try {
    const prepared = prepare({
      root: resolvedRoot,
      profile,
      dryRun,
      force,
    });
    preparation = prepared.result;
    result.preparation = preparation;
    result.fingerprint = commandFingerprint({
      root: resolvedRoot,
      profile,
      cwd: resolvedCwd,
      executable,
      argv,
      preparation,
    });

    if (prepared.exitCode !== PREPARE_EXIT_CODES.PASS) {
      result.status = 'environment-failure';
      result.exitCode =
        prepared.exitCode === PREPARE_EXIT_CODES.CONTRACT
          ? EXIT_CODES.CONTRACT
          : EXIT_CODES.ENVIRONMENT;
      result.durationMs = Date.now() - startedAt;
      writeResult(resolvedRoot, outputPath, result);
      return { exitCode: result.exitCode, result };
    }
    if (dryRun || preflightOnly) {
      result.status = 'planned';
      result.exitCode = EXIT_CODES.PASS;
      result.durationMs = Date.now() - startedAt;
      writeResult(resolvedRoot, outputPath, result);
      return { exitCode: EXIT_CODES.PASS, result };
    }
  } catch (error) {
    const code =
      error instanceof GateError
        ? error.code
        : error?.code === PREPARE_EXIT_CODES.CONTRACT
          ? EXIT_CODES.CONTRACT
          : EXIT_CODES.ENVIRONMENT;
    result.status = 'environment-failure';
    result.exitCode = code;
    result.error = sanitize(error?.message || error, resolvedRoot);
    result.durationMs = Date.now() - startedAt;
    writeResult(resolvedRoot, outputPath, result);
    return { exitCode: code, result };
  }

  let commandResult;
  try {
    commandResult = runCommand(executable, argv, resolvedCwd);
  } catch (error) {
    result.status = 'environment-failure';
    result.exitCode = EXIT_CODES.ENVIRONMENT;
    result.error = sanitize(error?.message || error, resolvedRoot);
    result.durationMs = Date.now() - startedAt;
    writeResult(resolvedRoot, outputPath, result);
    return { exitCode: result.exitCode, result };
  }

  if (commandResult?.error) {
    result.status = 'environment-failure';
    result.exitCode = EXIT_CODES.ENVIRONMENT;
    result.error = sanitize(commandResult.error.message || commandResult.error, resolvedRoot);
  } else if (commandResult?.status === 0) {
    result.status = 'passed';
    result.exitCode = EXIT_CODES.PASS;
  } else {
    result.status = 'product-failure';
    result.exitCode = EXIT_CODES.PRODUCT_FAILURE;
    result.error = `command exited with code ${commandResult?.status ?? 'unknown'}`;
  }
  result.durationMs = Date.now() - startedAt;
  writeResult(resolvedRoot, outputPath, result);
  return { exitCode: result.exitCode, result };
}

function help() {
  return `Usage: node scripts/run-with-toolchain.mjs [options] -- <command> [args...]

Options:
  --root <path>              Repository root (default: current directory)
  --cwd <path>               Command cwd relative to repository root (default: .)
  --profile nestjs|flutter|all
  --preflight-only           Hydrate/check only; do not execute a command
  --dry-run                  Report hydration and command without executing
  --force                    Force dependency hydration
  --json <path>              Write schema-v1 sanitized result JSON
`;
}

export function main(argv = process.argv.slice(2), { root = process.cwd() } = {}) {
  let options;
  try {
    options = parseArgs(argv);
    if (options.help) {
      console.log(help());
      return EXIT_CODES.PASS;
    }
    const result = runWithToolchain({
      root: options.root ? path.resolve(root, options.root) : root,
      profile: options.profile,
      cwd: options.cwd,
      command: options.command || [],
      dryRun: options.dryRun,
      force: options.force,
      preflightOnly: options.preflightOnly,
      json: options.json,
    });
    console.log(JSON.stringify(result.result, null, 2));
    return result.exitCode;
  } catch (error) {
    const code =
      error instanceof GateError ? error.code : EXIT_CODES.ENVIRONMENT;
    console.error(`TOOLCHAIN COMMAND GATE FAILED (${code}): ${sanitize(error?.message || error, root)}`);
    return code;
  }
}

const invoked =
  process.argv[1] &&
  pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invoked) process.exitCode = main();
