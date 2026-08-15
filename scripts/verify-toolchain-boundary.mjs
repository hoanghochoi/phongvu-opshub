#!/usr/bin/env node

import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  writeFileSync,
} from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

export const EXIT_CODES = Object.freeze({
  PASS: 0,
  CONTRACT: 2,
});

const CURRENT_DOCUMENTS = Object.freeze([
  'AGENTS.md',
  'README.md',
  'README-backend.md',
  'backend-nest/README.md',
  'deploy/home-server/README.md',
]);

const COMMAND_SURFACE_DIRECTORIES = Object.freeze([
  ['docs/runbooks', new Set(['.md'])],
  ['.github/workflows', new Set(['.yml', '.yaml'])],
  ['scripts', new Set(['.mjs', '.ps1', '.sh'])],
]);

const EXCLUDED_SCRIPT_NAMES = new Set([
  'prepare-task-toolchain.mjs',
  'run-with-toolchain.mjs',
  'verify-toolchain-boundary.mjs',
  'task-lifecycle.mjs',
  'verify-task.mjs',
  'verify-task-shadow.mjs',
]);

const RAW_COMMAND_PATTERNS = Object.freeze([
  {
    kind: 'flutter',
    pattern: /\bflutter(?:\.bat)?\s+(?:pub\s+(?:get|upgrade)|analyze|test|build|run)\b/i,
  },
  {
    kind: 'dart',
    pattern: /\bdart(?:\.exe)?\s+(?:pub|test|run|compile|format|analyze|build)\b/i,
  },
  {
    kind: 'npm',
    pattern: /\bnpm(?:\.cmd)?\s+(?:ci|install|test|run|build)\b/i,
  },
  {
    kind: 'npx',
    pattern: /\bnpx(?:\.cmd)?\s+(?:--no-install\s+)?(?:prisma|jest|ts-node)\b/i,
  },
]);

function normalize(relativePath) {
  return relativePath.replaceAll('\\', '/');
}

function readSurfaceFiles(root) {
  const files = new Set();
  for (const relativePath of CURRENT_DOCUMENTS) {
    if (existsSync(path.resolve(root, relativePath))) files.add(relativePath);
  }

  for (const [relativeDirectory, extensions] of COMMAND_SURFACE_DIRECTORIES) {
    const directory = path.resolve(root, relativeDirectory);
    if (!existsSync(directory)) continue;
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      if (!entry.isFile() || !extensions.has(path.extname(entry.name).toLowerCase())) {
        continue;
      }
      if (
        relativeDirectory === 'scripts' &&
        EXCLUDED_SCRIPT_NAMES.has(entry.name)
      ) {
        continue;
      }
      files.add(normalize(path.join(relativeDirectory, entry.name)));
    }
  }
  return [...files].sort();
}

function isCommentOnly(line) {
  return /^\s*(?:\/\/|#|\*|<!--)/.test(line);
}

function isCommandLike(line) {
  return (
    line.includes('`') ||
    /^\s*(?:[-*]\s+)?(?:node|flutter|dart|npm|npx|&|run:|command:)/i.test(line) ||
    /\b(?:spawnSync|exec(?:File)?Sync|child_process|shell:)\b/.test(line)
  );
}

function lineHasWrapper(lines, index) {
  for (let offset = -2; offset <= 2; offset += 1) {
    const candidate = lines[index + offset];
    if (candidate && /run-with-toolchain\.mjs|runAffectedConsumerSuite/i.test(candidate)) {
      return true;
    }
  }
  return false;
}

function isExplicitlyAllowlisted(relativePath, line) {
  const normalizedPath = normalize(relativePath);
  if (/run-with-toolchain\.mjs|runAffectedConsumerSuite/i.test(line)) return true;
  if (/docker(?:\s+compose|-compose)|\bmaintenance\s+n(?:pm|px)\b/i.test(line)) {
    return true;
  }
  if (
    normalizedPath === '.github/actions/setup-flutter/action.yml' &&
    /\bflutter(?:\.bat)?\s+(?:config|--version)\b/i.test(line)
  ) {
    return true;
  }
  if (
    normalizedPath === '.github/workflows/deploy-opshub-staging.yml' &&
    /prisma\s+migrate\s+resolve\s+--rolled-back/i.test(line)
  ) {
    return true;
  }
  if (/^backend-nest\/Dockerfile$/i.test(normalizedPath)) return true;
  if (/\bnpm\s+run\s+run:nest-command\b/i.test(line)) return true;
  return false;
}

export function findBoundaryViolations(root = process.cwd()) {
  const violations = [];
  for (const relativePath of readSurfaceFiles(path.resolve(root))) {
    const contents = readFileSync(path.resolve(root, relativePath), 'utf8');
    const lines = contents.split(/\r?\n/);
    lines.forEach((line, index) => {
      if (isCommentOnly(line) || !isCommandLike(line)) return;
      if (lineHasWrapper(lines, index)) return;
      if (isExplicitlyAllowlisted(relativePath, line)) return;
      for (const { kind, pattern } of RAW_COMMAND_PATTERNS) {
        if (!pattern.test(line)) continue;
        violations.push({
          kind,
          path: normalize(relativePath),
          line: index + 1,
          text: line.trim().slice(0, 240),
        });
      }
    });
  }
  return violations;
}

function help() {
  return 'Usage: node scripts/verify-toolchain-boundary.mjs [--root <path>] [--json <path>]';
}

export function main(argv = process.argv.slice(2), { cwd = process.cwd() } = {}) {
  let root = cwd;
  let jsonPath = null;
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--help') {
      console.log(help());
      return EXIT_CODES.PASS;
    }
    if (argument === '--root' || argument === '--json') {
      const value = argv[index + 1];
      if (!value || value.startsWith('--')) {
        console.error(`${argument} requires a value`);
        return EXIT_CODES.CONTRACT;
      }
      if (argument === '--root') root = path.resolve(cwd, value);
      if (argument === '--json') jsonPath = path.resolve(root, value);
      index += 1;
      continue;
    }
    console.error(`Unknown argument: ${argument}`);
    return EXIT_CODES.CONTRACT;
  }

  const violations = findBoundaryViolations(root);
  const result = {
    schemaVersion: 1,
    root: '<worktree>',
    status: violations.length === 0 ? 'passed' : 'failed',
    scanned: readSurfaceFiles(root),
    violations,
  };
  if (jsonPath) {
    mkdirSync(path.dirname(jsonPath), { recursive: true });
    writeFileSync(jsonPath, `${JSON.stringify(result, null, 2)}\n`, 'utf8');
  }
  if (violations.length > 0) {
    console.error('TOOLCHAIN BOUNDARY FAILED');
    for (const violation of violations) {
      console.error(`${violation.path}:${violation.line} [${violation.kind}] ${violation.text}`);
    }
    return EXIT_CODES.CONTRACT;
  }
  console.log(`TOOLCHAIN BOUNDARY PASS files=${result.scanned.length}`);
  return EXIT_CODES.PASS;
}

const invoked =
  process.argv[1] &&
  pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invoked) process.exitCode = main();
