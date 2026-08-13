import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { validateLiveEvidence } from '../../scripts/verify-ops72-live-shadow-evidence.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

test('OPS-72 live evidence has five pass observations and one explicit contract gap', () => {
  const artifact = JSON.parse(readFileSync(path.join(root, 'docs/migrations/ops-72-live-shadow-evidence.json'), 'utf8'));
  assert.deepEqual(validateLiveEvidence(artifact), {
    schemaVersion: 1,
    issue: 'OPS-72',
    observations: 5,
    excludedObservations: 1,
    passCount: 5,
    targetStatus: 'pending-live-timing-baseline',
    rawArtifactsChecked: false,
  });
});

test('OPS-72 verifier rejects stale accepted proof', () => {
  const artifact = JSON.parse(readFileSync(path.join(root, 'docs/migrations/ops-72-live-shadow-evidence.json'), 'utf8'));
  artifact.observations[0].stale = true;
  assert.throws(() => validateLiveEvidence(artifact), /stale must be false/);
});
