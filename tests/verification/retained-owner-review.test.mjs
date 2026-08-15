import assert from 'node:assert/strict';
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
