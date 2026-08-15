#!/usr/bin/env node

import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const backendRoot = path.resolve(scriptDirectory, '..');
const repositoryRoot = path.resolve(backendRoot, '..');
const toolchainRunner = path.join(
  repositoryRoot,
  'scripts',
  'run-with-toolchain.mjs',
);

const command = process.argv.slice(2);
if (command[0] === '--') command.shift();
if (command.length === 0) {
  console.error('Usage: node scripts/run-nest-command.mjs -- <command> [args...]');
  process.exit(2);
}

function localExecutable(executable) {
  if (executable === 'node') return process.execPath;
  if (path.isAbsolute(executable) || executable.includes(path.sep)) {
    return executable;
  }
  const localName = process.platform === 'win32' ? `${executable}.cmd` : executable;
  const candidate = path.join(backendRoot, 'node_modules', '.bin', localName);
  return existsSync(candidate) ? candidate : executable;
}

const fallbackExecutable = localExecutable(command[0]);
const resolvedCommand = [fallbackExecutable, ...command.slice(1)];
if (!existsSync(toolchainRunner)) {
  console.error(
    'Repository toolchain gate is missing; refusing to run a raw Nest command.',
  );
  process.exit(5);
}

const resolved = spawnSync(
  process.execPath,
  [
    toolchainRunner,
    '--root',
    repositoryRoot,
    '--profile',
    'nestjs',
    '--cwd',
    'backend-nest',
    '--',
    ...resolvedCommand,
  ],
  { cwd: repositoryRoot, env: process.env, stdio: 'inherit' },
);

if (resolved.error) {
  console.error(resolved.error.message);
  process.exitCode = 1;
} else {
  process.exitCode = resolved.status ?? 1;
}
