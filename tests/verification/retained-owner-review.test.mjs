import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { validateRetainedOwnerReview } from '../../scripts/verify-retained-owner-review.mjs';

const artifact = JSON.parse(
  readFileSync('docs/migrations/ops-73-retained-owner-review.json', 'utf8'),
);

test('OPS-73 retained-owner review proves every candidate has an owner and rollback path', () => {
  const result = validateRetainedOwnerReview(artifact);
  assert.equal(result.status, 'passed');
  assert.equal(result.candidateCount, 4);
  assert.equal(result.retainedPathCount, 19);
  assert.equal(result.deletionDecision, 'no-safe-deletion-candidate');
  assert.deepEqual(
    artifact.candidates.map((candidate) => candidate.disposition),
    ['retain', 'retain', 'retain', 'retain'],
  );
});

test('OPS-73 retained-owner review rejects a deletion disposition', () => {
  const invalid = structuredClone(artifact);
  invalid.candidates[0].disposition = 'delete';
  assert.throws(
    () => validateRetainedOwnerReview(invalid),
    /candidate is not retained/,
  );
});

test('OPS-73 retained-owner review rejects path traversal', () => {
  const invalid = structuredClone(artifact);
  invalid.candidates[0].paths[0].path = 'n8n/../README.md';
  assert.throws(
    () => validateRetainedOwnerReview(invalid),
    /unsafe path/,
  );
});

test('OPS-73 file evidence is hashed from Git-normalized bytes', () => {
  for (const candidate of artifact.candidates) {
    for (const entry of candidate.paths) {
      if (entry.kind !== 'file') continue;
      const normalized = execFileSync(
        'git',
        ['show', `${artifact.sourceRevision}:${entry.path}`],
      );
      assert.equal(entry.bytes, normalized.length, entry.path);
      assert.equal(
        entry.sha256,
        createHash('sha256').update(normalized).digest('hex'),
        entry.path,
      );
    }
  }
});
