#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import {
  mkdirSync,
  mkdtempSync,
  realpathSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { verifyTask, EXIT_CODES } from './verify-task.mjs';

function git(cwd, args) {
  return execFileSync('git', args, {
    cwd,
    encoding: 'utf8',
    windowsHide: true,
  }).trim();
}

function write(root, relative, content) {
  const target = path.join(root, relative);
  mkdirSync(path.dirname(target), { recursive: true });
  writeFileSync(target, content, 'utf8');
}

function createRepository() {
  const root = mkdtempSync(path.join(os.tmpdir(), 'opshub-verify-canary-'));
  git(root, ['init', '--quiet']);
  git(root, ['config', 'user.name', 'OpsHub verify canary']);
  git(root, ['config', 'user.email', 'verify-canary@example.invalid']);
  write(root, 'README.md', '# canary\n');
  git(root, ['add', '--all']);
  git(root, ['commit', '--quiet', '-m', 'canary baseline']);
  return root;
}

function runFixture(name, changes, expectedProfiles) {
  const root = createRepository();
  try {
    for (const [relative, content] of changes) write(root, relative, content);
    const proof = verifyTask({ root, options: { dryRun: true } });
    if (proof.exitCode !== EXIT_CODES.PASS) {
      throw new Error(`${name} failed with exit ${proof.exitCode}`);
    }
    const actual = [...proof.result.selectedProfiles].sort();
    const expected = [...expectedProfiles].sort();
    if (JSON.stringify(actual) !== JSON.stringify(expected)) {
      throw new Error(`${name} selected ${actual.join(',')} expected ${expected.join(',')}`);
    }
    return {
      name,
      status: 'passed',
      changedPaths: proof.result.changedPaths,
      selectedProfiles: actual,
      affectedConsumers: proof.result.affectedConsumers,
      fingerprint: proof.result.fingerprint.before,
    };
  } finally {
    const resolved = realpathSync(root);
    const prefix = path.join(realpathSync(os.tmpdir()), 'opshub-verify-canary-');
    if (!resolved.toLowerCase().startsWith(prefix.toLowerCase())) {
      throw new Error(`refusing to remove unexpected canary directory: ${resolved}`);
    }
    rmSync(resolved, { recursive: true, force: true });
  }
}

export function runCanaries() {
  return [
    runFixture(
      'harness-docs',
      [['docs/README.md', '# changed docs\n']],
      ['docs', 'harness'],
    ),
    runFixture(
      'verification-tooling',
      [['scripts/verify-task.mjs', '// canary change\n']],
      ['verification-runner'],
    ),
    runFixture(
      'cross-stack-consumers',
      [
        ['backend-nest/src/common/contract.ts', 'export const contract = true;\n'],
        ['backend-go/realtime.go', 'package realtime\n'],
        ['lib/features/auth/contract.dart', 'const contract = true;\n'],
      ],
      ['flutter', 'go-realtime', 'nestjs'],
    ),
  ];
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  try {
    const fixtures = runCanaries();
    console.log(JSON.stringify({ schemaVersion: 1, mode: 'fixture-canary', database: 'none', fixtures }, null, 2));
  } catch (error) {
    console.error(`VERIFY TASK CANARY FAILED: ${error.message}`);
    process.exitCode = 1;
  }
}
