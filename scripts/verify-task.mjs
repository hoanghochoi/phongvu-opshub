#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import {
  allProfiles,
  FULL_PROFILE_ID,
  matchProfiles,
  profileById,
  resolveCommandCwd,
} from './verification-profiles.mjs';

export const EXIT_CODES = Object.freeze({
  PASS: 0,
  CONTRACT: 2,
  PRODUCT_FAILURE: 3,
  STALE: 4,
  ENVIRONMENT: 5,
});

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SHA_RE = /^[0-9a-f]{40}$/i;

function normalizePath(value) {
  return String(value).trim().replaceAll('\\', '/').replace(/^\.\//, '');
}

function runGit(root, argv, { allowFailure = false, encoding = 'utf8' } = {}) {
  const result = spawnSync('git', argv, {
    cwd: root,
    encoding,
    windowsHide: true,
  });
  if (result.error) {
    throw new RunnerError(
      EXIT_CODES.ENVIRONMENT,
      `Không chạy được Git: ${result.error.message}`,
    );
  }
  if (!allowFailure && result.status !== 0) {
    const detail = String(result.stderr || result.stdout || '').trim();
    throw new RunnerError(
      EXIT_CODES.CONTRACT,
      `Git thất bại: ${detail || `exit ${result.status}`}`,
    );
  }
  return result;
}

function gitOutput(root, argv) {
  return String(runGit(root, argv).stdout || '').trim();
}

export class RunnerError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'RunnerError';
    this.code = code;
  }
}

export function parseArgs(argv) {
  const options = {
    base: null,
    profiles: [],
    full: false,
    dryRun: false,
    json: null,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--full') {
      options.full = true;
      continue;
    }
    if (argument === '--dry-run') {
      options.dryRun = true;
      continue;
    }
    if (argument === '--base' || argument === '--profile' || argument === '--json') {
      const value = argv[index + 1];
      if (!value || value.startsWith('--')) {
        throw new RunnerError(EXIT_CODES.CONTRACT, `${argument} requires a value`);
      }
      if (argument === '--base') options.base = value;
      if (argument === '--profile') options.profiles.push(value);
      if (argument === '--json') options.json = value;
      index += 1;
      continue;
    }
    if (argument === '--help' || argument === '-h') {
      options.help = true;
      continue;
    }
    throw new RunnerError(EXIT_CODES.CONTRACT, `Unknown argument: ${argument}`);
  }
  if (options.base && /[\0\r\n]/.test(options.base)) {
    throw new RunnerError(EXIT_CODES.CONTRACT, 'Invalid base ref');
  }
  if (options.json && /[\0\r\n]/.test(options.json)) {
    throw new RunnerError(EXIT_CODES.CONTRACT, 'Invalid JSON output path');
  }
  return options;
}

export function resolveBase(root, base) {
  if (base == null) return null;
  const revision = gitOutput(root, [
    'rev-parse',
    '--verify',
    '--end-of-options',
    `${base}^{commit}`,
  ]);
  if (!SHA_RE.test(revision)) {
    throw new RunnerError(EXIT_CODES.CONTRACT, `Base ref is not a commit: ${base}`);
  }
  const mergeBase = runGit(root, ['merge-base', revision, 'HEAD'], {
    allowFailure: true,
  });
  if (mergeBase.status !== 0) {
    throw new RunnerError(EXIT_CODES.CONTRACT, `Base has no merge base with HEAD: ${base}`);
  }
  return revision.toLowerCase();
}

function parseNameOnly(output) {
  return String(output || '')
    .split(/\r?\n/)
    .map(normalizePath)
    .filter(Boolean);
}

export function collectChangedPaths({ root = ROOT, base = null } = {}) {
  const resolvedBase = resolveBase(root, base);
  const outputs = [];
  if (resolvedBase) {
    outputs.push(
      runGit(root, ['diff', '--no-renames', '--name-only', resolvedBase, 'HEAD', '--']).stdout,
    );
  }
  outputs.push(
    runGit(root, ['diff', '--no-renames', '--name-only', '--']).stdout,
    runGit(root, ['diff', '--cached', '--no-renames', '--name-only', '--']).stdout,
    runGit(root, ['ls-files', '--others', '--exclude-standard']).stdout,
  );
  return [...new Set(outputs.flatMap(parseNameOnly))].sort();
}

function trackedDiffBytes(root, args) {
  const result = runGit(
    root,
    ['diff', '--binary', '--no-ext-diff', ...args, '--'],
    { encoding: null },
  );
  return Buffer.isBuffer(result.stdout)
    ? result.stdout
    : Buffer.from(result.stdout || '');
}

function hashBytes(hash, bytes) {
  hash.update(bytes);
  return hash;
}

function hashFileIfPresent(hash, root, relative) {
  const target = path.join(root, relative);
  if (!existsSync(target) || !statSync(target).isFile()) {
    hash.update(`${relative}\0<missing>\0`);
    return;
  }
  hash.update(`${relative}\0`);
  hashBytes(hash, readFileSync(target));
  hash.update('\0');
}

export function fingerprint({
  root = ROOT,
  base = null,
  head = null,
  commandDefinitions = [],
} = {}) {
  const resolvedBase = resolveBase(root, base);
  const resolvedHead = head || gitOutput(root, ['rev-parse', 'HEAD']).toLowerCase();
  const hash = createHash('sha256');
  hash.update(`base=${resolvedBase || ''}\nhead=${resolvedHead}\n`);
  hash.update(`commands=${JSON.stringify(commandDefinitions)}\n`);
  if (resolvedBase) hash.update(trackedDiffBytes(root, [resolvedBase, 'HEAD']));
  hash.update(trackedDiffBytes(root, []));
  hash.update(trackedDiffBytes(root, ['--cached']));
  const untracked = parseNameOnly(
    runGit(root, ['ls-files', '--others', '--exclude-standard']).stdout,
  );
  for (const relative of untracked) hashFileIfPresent(hash, root, relative);
  hashFileIfPresent(hash, root, 'scripts/verify-task.mjs');
  hashFileIfPresent(hash, root, 'scripts/verification-profiles.mjs');
  return hash.digest('hex');
}

function toolVersion(executable, root, cwd = root) {
  const result = spawnSync(executable, ['--version'], {
    cwd,
    encoding: 'utf8',
    windowsHide: true,
    shell: process.platform === 'win32' && /\.(?:cmd|bat)$/i.test(executable),
  });
  if (result.error || result.status !== 0) return 'unavailable';
  return String(result.stdout || result.stderr || '').trim().split(/\r?\n/)[0].slice(0, 160);
}

function displayCwd(root, cwd) {
  const relative = path.relative(root, cwd).replaceAll('\\', '/');
  return relative || '.';
}

function displayExecutable(executable) {
  return path.isAbsolute(executable) ? path.basename(executable) : executable;
}

function displayCommand(command) {
  return [displayExecutable(command.executable), ...command.argv].join(' ');
}

function sanitizeCommandResult(root, result) {
  return {
    ...result,
    executable: displayExecutable(result.executable),
    command: result.command
      ? result.command
          .replaceAll(root, '.')
          .replaceAll('\\', '/')
      : result.command,
    cwd: result.cwd ? displayCwd(root, path.resolve(result.cwd)) : result.cwd,
    error: result.error
      ? String(result.error).replaceAll(root, '.').replaceAll('\\', '/')
      : result.error,
  };
}

function commandDefinition(command) {
  return {
    id: command.id,
    cwd: command.cwd || '.',
    executable: displayExecutable(command.executable),
    argv: [...command.argv],
  };
}

function runCommand(root, command) {
  const cwd = resolveCommandCwd(root, command);
  const started = Date.now();
  const result = spawnSync(command.executable, command.argv, {
    cwd,
    encoding: 'utf8',
    windowsHide: true,
    shell: process.platform === 'win32' && /\.(?:cmd|bat)$/i.test(command.executable),
    stdio: 'inherit',
  });
  const durationMs = Date.now() - started;
  if (result.error) {
    return {
      id: command.id,
      executable: displayExecutable(command.executable),
      argv: command.argv,
      command: displayCommand(command),
      cwd: displayCwd(root, cwd),
      status: 'environment-failure',
      exitCode: null,
      durationMs,
      error: String(result.error.message).slice(0, 240),
    };
  }
  return {
    id: command.id,
    executable: displayExecutable(command.executable),
    argv: command.argv,
    command: displayCommand(command),
    cwd: displayCwd(root, cwd),
    status: result.status === 0 ? 'passed' : 'failed',
    exitCode: result.status,
    durationMs,
  };
}

function selectProfiles(changedPaths, options) {
  try {
    const requested = [...options.profiles];
    const profiles = options.full
      ? allProfiles()
      : matchProfiles(changedPaths, requested);
    if (options.full) {
      for (const id of requested) {
        if (!profileById(id)) throw new Error(`Unknown verification profile: ${id}`);
      }
    }
    return profiles;
  } catch (error) {
    throw new RunnerError(EXIT_CODES.CONTRACT, error.message);
  }
}

function assertMatchedPaths(changedPaths, profiles) {
  const unmatched = changedPaths.filter((changedPath) =>
    !profiles.some((profile) =>
      profile.pathPatterns.some((pattern) => pattern.test(changedPath)),
    ),
  );
  if (unmatched.length > 0) {
    throw new RunnerError(
      EXIT_CODES.CONTRACT,
      `No verification profile owns changed path(s):\n${unmatched.join('\n')}`,
    );
  }
}

function uniqueCommands(profiles) {
  const commands = new Map();
  for (const profile of profiles) {
    for (const command of profile.commands) {
      const existing = commands.get(command.id);
      if (!existing) {
        commands.set(command.id, command);
        continue;
      }
      if (
        existing.cwd !== command.cwd ||
        existing.executable !== command.executable ||
        JSON.stringify(existing.argv) !== JSON.stringify(command.argv)
      ) {
        throw new RunnerError(
          EXIT_CODES.CONTRACT,
          `Verification command id is defined inconsistently: ${command.id}`,
        );
      }
    }
  }
  return [...commands.values()];
}

function validateCommandDefinition(root, command) {
  if (!command || typeof command !== 'object') {
    throw new RunnerError(EXIT_CODES.CONTRACT, 'Verification command must be an object');
  }
  if (!command.id || typeof command.id !== 'string') {
    throw new RunnerError(EXIT_CODES.CONTRACT, 'Verification command id is required');
  }
  if (!command.executable || typeof command.executable !== 'string') {
    throw new RunnerError(
      EXIT_CODES.CONTRACT,
      `Verification command ${command.id} has no executable`,
    );
  }
  if (!Array.isArray(command.argv) || command.argv.some((value) => typeof value !== 'string')) {
    throw new RunnerError(
      EXIT_CODES.CONTRACT,
      `Verification command ${command.id} argv must be a string array`,
    );
  }
  const cwd = resolveCommandCwd(root, command);
  const relativeCwd = path.relative(root, cwd);
  if (relativeCwd === '..' || relativeCwd.startsWith(`..${path.sep}`) || path.isAbsolute(relativeCwd)) {
    throw new RunnerError(
      EXIT_CODES.CONTRACT,
      `Verification command ${command.id} cwd escapes repository root`,
    );
  }
  if (!existsSync(cwd) || !statSync(cwd).isDirectory()) {
    throw new RunnerError(
      EXIT_CODES.CONTRACT,
      `Verification command ${command.id} cwd does not exist: ${displayCwd(root, cwd)}`,
    );
  }
}

function help() {
  return `Usage: node scripts/verify-task.mjs [options]\n\n` +
    `  --base <git-ref>       Include committed diff from base to HEAD\n` +
    `  --profile <id>        Add a profile (repeatable)\n` +
    `  --full                Select every repository profile\n` +
    `  --dry-run             Discover and report commands without executing\n` +
    `  --json <path>         Write schema-v1 result JSON\n`;
}

export function verifyTask({ root = ROOT, options = {}, runCommandFn = runCommand } = {}) {
  const started = Date.now();
  const normalizedOptions = {
    base: options.base ?? null,
    profiles: options.profiles ?? [],
    full: Boolean(options.full),
    dryRun: Boolean(options.dryRun),
  };
  const head = gitOutput(root, ['rev-parse', 'HEAD']).toLowerCase();
  const base = resolveBase(root, normalizedOptions.base);
  const changedPaths = collectChangedPaths({ root, base });
  let profiles;
  try {
    profiles = selectProfiles(changedPaths, normalizedOptions);
    assertMatchedPaths(changedPaths, profiles);
  } catch (error) {
    if (error instanceof RunnerError) {
      return {
        exitCode: error.code,
        result: {
          schemaVersion: 1,
          baseSha: base,
          headSha: head,
          changedPaths,
          selectedProfiles: [],
          affectedConsumers: [],
          toolVersions: { node: process.version, git: toolVersion('git', root) },
          commandDefinitions: [],
          durationMs: Date.now() - started,
          result: { status: 'failed', code: error.code, dryRun: normalizedOptions.dryRun, error: error.message },
          fingerprint: { before: null, after: null, stale: false },
        },
      };
    }
    throw error;
  }
  const selectedProfiles = profiles.map((profile) => profile.id);
  const affectedConsumers = [...new Set(profiles.flatMap((profile) => profile.consumers))].sort();
  let commands;
  try {
    commands = uniqueCommands(profiles);
    commands.forEach((command) => validateCommandDefinition(root, command));
  } catch (error) {
    const runnerError = error instanceof RunnerError
      ? error
      : new RunnerError(EXIT_CODES.CONTRACT, String(error.message || error));
    return {
      exitCode: runnerError.code,
      result: {
        schemaVersion: 1,
        baseSha: base,
        headSha: head,
        changedPaths,
        selectedProfiles,
        affectedConsumers,
        toolVersions: { node: process.version, git: toolVersion('git', root) },
        commandDefinitions: [],
        durationMs: Date.now() - started,
        result: {
          status: 'failed',
          code: runnerError.code,
          dryRun: normalizedOptions.dryRun,
          error: runnerError.message,
        },
        fingerprint: { before: null, after: null, stale: false },
      },
    };
  }
  const commandDefinitions = commands.map(commandDefinition);
  const beforeFingerprint = fingerprint({ root, base, head, commandDefinitions });
  const commandResults = [];
  const toolVersions = {
    node: process.version,
    git: toolVersion('git', root),
  };
  for (const command of commands) {
    const key = displayExecutable(command.executable).replace(/[^A-Za-z0-9_.-]/g, '_');
    if (!(key in toolVersions)) {
      toolVersions[key] = toolVersion(
        command.executable,
        root,
        resolveCommandCwd(root, command),
      );
    }
  }
  let exitCode = EXIT_CODES.PASS;
  if (!normalizedOptions.dryRun) {
    for (const command of commands) {
      const result = sanitizeCommandResult(root, runCommandFn(root, command));
      commandResults.push(result);
      if (result.status === 'environment-failure') {
        exitCode = EXIT_CODES.ENVIRONMENT;
        break;
      }
      if (result.status === 'failed') {
        exitCode = EXIT_CODES.PRODUCT_FAILURE;
        break;
      }
    }
  } else {
    for (const command of commands) {
      commandResults.push({
        id: command.id,
        executable: displayExecutable(command.executable),
        argv: command.argv,
        command: `${displayExecutable(command.executable)} ${command.argv.join(' ')}`,
        cwd: displayCwd(root, resolveCommandCwd(root, command)),
        status: 'planned',
      });
    }
  }
  const afterFingerprint = fingerprint({ root, base, commandDefinitions });
  if (beforeFingerprint !== afterFingerprint) {
    exitCode = EXIT_CODES.STALE;
  }
  const result = {
    schemaVersion: 1,
    baseSha: base,
    headSha: head,
    changedPaths,
    selectedProfiles,
    affectedConsumers,
    toolVersions,
    commandDefinitions,
    durationMs: Date.now() - started,
    result: {
      status: exitCode === 0 ? 'passed' : 'failed',
      code: exitCode,
      dryRun: normalizedOptions.dryRun,
      commands: commandResults,
    },
    fingerprint: {
      before: beforeFingerprint,
      after: afterFingerprint,
      stale: beforeFingerprint !== afterFingerprint,
    },
  };
  return { exitCode, result };
}

export function main(argv = process.argv.slice(2), { root = ROOT } = {}) {
  let options;
  try {
    options = parseArgs(argv);
    if (options.help) {
      console.log(help());
      return EXIT_CODES.PASS;
    }
    const { exitCode, result } = verifyTask({ root, options });
    if (options.json) {
      writeFileSync(path.resolve(root, options.json), `${JSON.stringify(result, null, 2)}\n`, 'utf8');
    }
    if (options.dryRun) {
      console.log(JSON.stringify(result, null, 2));
    } else if (exitCode === 0) {
      console.log(`VERIFY TASK PASS profiles=${result.selectedProfiles.join(',') || 'none'} paths=${result.changedPaths.length}`);
    }
    return exitCode;
  } catch (error) {
    const code = error instanceof RunnerError ? error.code : EXIT_CODES.ENVIRONMENT;
    const payload = {
      schemaVersion: 1,
      result: { status: 'failed', code, error: String(error.message).slice(0, 500) },
    };
    if (options?.json) {
      writeFileSync(path.resolve(root, options.json), `${JSON.stringify(payload, null, 2)}\n`, 'utf8');
    }
    console.error(`VERIFY TASK FAILED (${code}): ${error.message}`);
    return code;
  }
}

const invoked = process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invoked) process.exitCode = main();
