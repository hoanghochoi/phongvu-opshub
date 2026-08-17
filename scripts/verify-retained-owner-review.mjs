#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const ALLOWED_KINDS = new Set(['file', 'directory']);
const ALLOWED_DISPOSITIONS = new Set(['retain']);

function fail(message) {
  throw new Error(`RETAINED_OWNER_REVIEW_INVALID: ${message}`);
}

function isSafeRelativePath(value) {
  const segments =
    typeof value === 'string' ? value.replaceAll('\\', '/').split('/') : [];
  return (
    typeof value === 'string' &&
    value.length > 0 &&
    !path.isAbsolute(value) &&
    !/^(?:[A-Za-z]:[\\/]|[\\/]{2}|file:)/.test(value) &&
    !segments.includes('..')
  );
}

function gitOutput(args, { binary = false } = {}) {
  const result = spawnSync('git', args, {
    cwd: ROOT,
    encoding: binary ? null : 'utf8',
    windowsHide: true,
    maxBuffer: 16 * 1024 * 1024,
  });
  if (result.error || result.status !== 0) {
    fail(`git ${args.join(' ')} failed: ${result.error?.message || String(result.stderr || '').trim()}`);
  }
  return result.stdout;
}

function normalizedCurrentFile(relativePath) {
  const currentBlob = String(
    // Write the normalized blob to the local object store before reading it
    // back. `git hash-object` without `-w` only computes the id, so cat-file
    // would fail for an intentionally dirty file during an affected proof.
    gitOutput(['hash-object', '-w', `--path=${relativePath}`, '--', relativePath]),
  ).trim();
  if (!/^[0-9a-f]{40}$/.test(currentBlob)) {
    fail(`current normalized blob is invalid: ${relativePath}`);
  }
  const bytes = gitOutput(['cat-file', 'blob', currentBlob], { binary: true });
  return {
    bytes,
    sha256: createHash('sha256').update(bytes).digest('hex'),
  };
}

function normalizedSourceFile(sourceRevision, relativePath) {
  const sourceBlob = String(
    gitOutput(['rev-parse', '--verify', `${sourceRevision}:${relativePath}`]),
  ).trim();
  if (!/^[0-9a-f]{40}$/.test(sourceBlob)) {
    fail(`source blob is invalid: ${relativePath}`);
  }
  const current = normalizedCurrentFile(relativePath);
  const currentBlob = String(
    gitOutput(['hash-object', `--path=${relativePath}`, '--', relativePath]),
  ).trim();
  if (currentBlob !== sourceBlob) {
    fail(`normalized file content mismatch: ${relativePath}`);
  }
  return current;
}

function validatePath(entry, seenPaths, sourceRevision) {
  if (!entry || typeof entry !== 'object') fail('path entry is not an object');
  if (!isSafeRelativePath(entry.path)) fail(`unsafe path: ${entry.path}`);
  if (!ALLOWED_KINDS.has(entry.kind)) fail(`invalid path kind: ${entry.path}`);
  if (seenPaths.has(entry.path)) fail(`duplicate path: ${entry.path}`);
  seenPaths.add(entry.path);

  const absolutePath = path.resolve(ROOT, entry.path);
  if (!existsSync(absolutePath)) fail(`missing reviewed path: ${entry.path}`);
  const stats = statSync(absolutePath);
  if (entry.kind === 'directory' && !stats.isDirectory()) {
    fail(`expected directory: ${entry.path}`);
  }
  if (entry.kind === 'file') {
    if (!stats.isFile()) fail(`expected file: ${entry.path}`);
    if (!/^[0-9a-f]{64}$/.test(entry.sha256 || '')) {
      fail(`file SHA-256 missing: ${entry.path}`);
    }
    const normalized = normalizedSourceFile(sourceRevision, entry.path);
    if (entry.sha256 !== normalized.sha256) {
      fail(`file SHA-256 mismatch: ${entry.path}`);
    }
    if (entry.bytes !== normalized.bytes.length) {
      fail(`file byte count mismatch: ${entry.path}`);
    }
  }
}

function validateReferenceList(values, label) {
  if (!Array.isArray(values) || values.length === 0) fail(`${label} missing`);
  for (const value of values) {
    if (!isSafeRelativePath(value)) fail(`${label} contains unsafe path: ${value}`);
    if (!existsSync(path.resolve(ROOT, value))) fail(`${label} path missing: ${value}`);
  }
}

export function validateRetainedOwnerReview(document) {
  if (document?.formatVersion !== 1) fail('formatVersion must be 1');
  if (document.issue !== 'OPS-73') fail('issue must be OPS-73');
  if (!/^[0-9a-f]{40}$/.test(document.sourceRevision || '')) {
    fail('sourceRevision must be a commit SHA');
  }
  if (!isSafeRelativePath(document.sourceInventory)) {
    fail('sourceInventory must be repository-relative');
  }
  const inventoryPath = path.resolve(ROOT, document.sourceInventory);
  if (!existsSync(inventoryPath)) fail('source inventory is missing');
  if (!/^[0-9a-f]{64}$/.test(document.sourceInventorySha256 || '')) {
    fail('sourceInventorySha256 is invalid');
  }
  const normalizedInventory = normalizedCurrentFile(document.sourceInventory);
  if (normalizedInventory.sha256 !== document.sourceInventorySha256) {
    fail('source inventory SHA-256 mismatch');
  }
  if (!Array.isArray(document.candidates) || document.candidates.length < 4) {
    fail('at least four retained-owner candidates are required');
  }

  const candidateIds = new Set();
  const seenPaths = new Set();
  for (const candidate of document.candidates) {
    if (!candidate || typeof candidate !== 'object') fail('candidate is not an object');
    if (!candidate.id || candidateIds.has(candidate.id)) fail(`duplicate candidate: ${candidate.id}`);
    candidateIds.add(candidate.id);
    if (!ALLOWED_DISPOSITIONS.has(candidate.disposition)) {
      fail(`candidate is not retained: ${candidate.id}`);
    }
    if (!candidate.owner || !candidate.reasonCode) fail(`owner/reason missing: ${candidate.id}`);
    if (!Array.isArray(candidate.paths) || candidate.paths.length === 0) {
      fail(`candidate paths missing: ${candidate.id}`);
    }
    for (const entry of candidate.paths) {
      validatePath(entry, seenPaths, document.sourceRevision);
    }
    validateReferenceList(candidate.ownerReferences, `${candidate.id}.ownerReferences`);
    if (!candidate.rollback?.required || !candidate.rollback?.method || !candidate.rollback?.owner) {
      fail(`rollback metadata missing: ${candidate.id}`);
    }
  }

  if (document.summary?.deletionDecision !== 'no-safe-deletion-candidate') {
    fail('summary must record no-safe-deletion-candidate');
  }
  if (document.summary?.secretScan !== 'not-committed-payloads') {
    fail('summary secret-scan disposition missing');
  }
  return {
    status: 'passed',
    candidateCount: document.candidates.length,
    retainedPathCount: seenPaths.size,
    deletionDecision: document.summary.deletionDecision,
  };
}

export function main(argv = process.argv.slice(2)) {
  if (argv.length !== 2 || argv[0] !== '--input' || argv[1].startsWith('--')) {
    throw new Error('Usage: node scripts/verify-retained-owner-review.mjs --input <path>');
  }
  const input = path.resolve(ROOT, argv[1]);
  if (!existsSync(input)) fail(`missing input: ${argv[1]}`);
  const result = validateRetainedOwnerReview(JSON.parse(readFileSync(input, 'utf8')));
  console.log(JSON.stringify(result, null, 2));
  return 0;
}

if (
  process.argv[1] &&
  pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url
) {
  try {
    process.exitCode = main();
  } catch (error) {
    console.error(error.message);
    process.exitCode = 2;
  }
}
