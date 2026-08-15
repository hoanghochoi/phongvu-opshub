#!/usr/bin/env node

import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// Local migration verifiers must enter through the repository-owned Nest gate.
// The helper deliberately uses npx --no-install so a cold worktree cannot
// download a different Prisma CLI while the proof is running.
const backendRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
);
const repositoryRoot = path.resolve(backendRoot, '..');
const toolchainRunner = path.join(
  repositoryRoot,
  'scripts',
  'run-with-toolchain.mjs',
);

const result = spawnSync(
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
    'npx',
    '--no-install',
    'prisma',
    'migrate',
    'deploy',
  ],
  {
    cwd: repositoryRoot,
    env: process.env,
    encoding: 'utf8',
    stdio: 'inherit',
  },
);

if (result.error) {
  console.error(`Prisma migration toolchain failed: ${result.error.message}`);
  process.exitCode = 1;
} else {
  process.exitCode = result.status ?? 1;
}
