import assert from 'node:assert/strict';
import test from 'node:test';

import { readFileSync } from 'node:fs';
import { validateProgress } from '../../scripts/verify-ops72-execution-canary-progress.mjs';

const fixture = JSON.parse(readFileSync('docs/migrations/ops-72-execution-canary-progress.json', 'utf8'));

test('accepts the current partial execution-canary progress ledger', () => {
  const result = validateProgress(fixture);
  assert.deepEqual(result, {
    status: 'collecting',
    issue: 'OPS-72',
    cohortId: 'ops72-execution-canary-v1',
    collectedObservationCount: 4,
    requiredObservationCount: 5,
    promotionEligible: false,
  });
});

test('rejects duplicate PR/run identities', () => {
  const duplicate = structuredClone(fixture);
  duplicate.observations[1].pullRequest = duplicate.observations[0].pullRequest;
  assert.throws(() => validateProgress(duplicate), /duplicate pull request/);
});

test('rejects stale or unmatched proof', () => {
  const stale = structuredClone(fixture);
  stale.observations[0].stale = true;
  assert.throws(() => validateProgress(stale), /stale must be false/);

  const unmatched = structuredClone(fixture);
  unmatched.observations[0].unmatchedPaths = ['unknown/path'];
  assert.throws(() => validateProgress(unmatched), /unmatchedPaths must be empty/);
});

test('rejects promotion or local-path claims for a partial ledger', () => {
  const promoted = structuredClone(fixture);
  promoted.promotionEligible = true;
  assert.throws(() => validateProgress(promoted), /promotion eligible/);

  const localPath = structuredClone(fixture);
  localPath.authority.finalEvidencePath = 'C:\\Users\\local\\evidence.json';
  assert.throws(() => validateProgress(localPath), /final evidence path is invalid/);
});
