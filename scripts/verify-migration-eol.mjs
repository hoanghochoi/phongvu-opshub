#!/usr/bin/env node

/**
 * Fail closed when tracked migration evidence is not byte-identical to its
 * committed LF representation.  The migration validators intentionally hash
 * raw bytes; silently normalizing them here would change evidence identity.
 */

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { isAbsolute, relative, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

export const MIGRATION_EVIDENCE_PATHS = Object.freeze([
  'docs/migrations/harness-v1-archive-manifest.json',
  'docs/migrations/harness-v1-disposition.json',
  'docs/migrations/harness-v1-linear-targets.json',
]);

function git(root, args) {
  try {
    return execFileSync('git', ['-C', root, ...args], {
      encoding: 'buffer',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch (error) {
    const stderr = Buffer.isBuffer(error.stderr)
      ? error.stderr.toString('utf8').trim()
      : String(error.stderr || '').trim();
    const message = stderr || error.message || 'git command failed';
    throw new Error(`GIT_COMMAND_FAILED:${args.join(' ')}:${message}`);
  }
}

function gitText(root, args) {
  return git(root, args).toString('utf8').trim();
}

function hasByte(bytes, value) {
  return bytes.includes(value);
}

function issue(code, path, detail) {
  return { code, path, detail };
}

export function inspectMigrationEol(
  repositoryRoot = process.cwd(),
  { paths = MIGRATION_EVIDENCE_PATHS, revision = 'HEAD' } = {},
) {
  const root = resolve(repositoryRoot);
  const files = [];
  const issues = [];

  for (const relativePath of paths) {
    const path = String(relativePath).replaceAll('\\', '/');
    const absolutePath = resolve(root, path);
    const pathFromRoot = relative(root, absolutePath);
    if (isAbsolute(pathFromRoot) || pathFromRoot.startsWith('..')) {
      issues.push(issue('MIGRATION_EVIDENCE_PATH_INVALID', path, 'path escapes repository root'));
      continue;
    }
    if (!existsSync(absolutePath)) {
      issues.push(issue('MIGRATION_EVIDENCE_MISSING', path, 'tracked evidence file is missing'));
      continue;
    }

    const bytes = readFileSync(absolutePath);
    const hasCrlf = bytes.includes(Buffer.from([0x0d, 0x0a]));
    const hasBareCr = hasByte(bytes, 0x0d) && !hasCrlf;
    let expected;
    let eolAttribute = 'unknown';
    try {
      const attr = gitText(root, ['check-attr', 'eol', '--', path]);
      eolAttribute = attr.split(':').at(-1)?.trim() || 'unknown';
      expected = git(root, ['cat-file', 'blob', `${revision}:${path}`]);
    } catch (error) {
      issues.push(issue('MIGRATION_EVIDENCE_GIT_LOOKUP_FAILED', path, error.message));
    }

    const matchesGitBlob = expected ? Buffer.compare(bytes, expected) === 0 : false;
    const record = {
      path,
      byteLength: bytes.length,
      eolAttribute,
      hasCrlf,
      hasBareCr,
      matchesGitBlob,
    };
    files.push(record);

    if (hasCrlf || hasBareCr) {
      issues.push(
        issue(
          'MIGRATION_EVIDENCE_NON_LF',
          path,
          'working-tree bytes contain CRLF/CR; checkout the tracked LF bytes with core.autocrlf=false',
        ),
      );
    }
    if (expected && !matchesGitBlob) {
      issues.push(
        issue(
          'MIGRATION_EVIDENCE_BYTES_DRIFT',
          path,
          `working-tree bytes do not match ${revision}:${path}`,
        ),
      );
    }
  }

  return {
    schemaVersion: 1,
    revision,
    status: issues.length === 0 ? 'pass' : 'fail',
    files,
    issues,
  };
}

export function assertMigrationEol(repositoryRoot = process.cwd(), options) {
  const result = inspectMigrationEol(repositoryRoot, options);
  if (result.status !== 'pass') {
    const summary = result.issues.map(({ code, path }) => `${code}:${path}`).join(', ');
    const error = new Error(`MIGRATION_EVIDENCE_EOL_INVALID: ${summary}`);
    error.result = result;
    throw error;
  }
  return result;
}

function parseArgs(argv) {
  const options = { root: process.cwd(), json: false };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--root') {
      options.root = resolve(argv[++index]);
    } else if (argument === '--json') {
      options.json = true;
    } else if (argument === '--help' || argument === '-h') {
      options.help = true;
    } else {
      throw new Error(`UNKNOWN_ARGUMENT:${argument}`);
    }
  }
  return options;
}

const invokedAsScript =
  process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href;

if (invokedAsScript) {
  try {
    const options = parseArgs(process.argv.slice(2));
    if (options.help) {
      console.log('Usage: node scripts/verify-migration-eol.mjs [--root <repo>] [--json]');
      process.exit(0);
    }
    const result = inspectMigrationEol(options.root);
    if (options.json) {
      console.log(JSON.stringify(result));
    } else if (result.status === 'pass') {
      console.log(`migration evidence EOL PASS (${result.files.length} files)`);
    } else {
      for (const item of result.issues) {
        console.error(`${item.code}: ${item.path} — ${item.detail}`);
      }
    }
    process.exitCode = result.status === 'pass' ? 0 : 2;
  } catch (error) {
    console.error(error.message);
    process.exitCode = 2;
  }
}
