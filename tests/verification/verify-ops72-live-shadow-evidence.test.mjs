import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { validateLiveEvidence } from '../../scripts/verify-ops72-live-shadow-evidence.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

test('OPS-72 live evidence records five comparable v2 observations and one explicit contract gap', () => {
  const artifact = JSON.parse(readFileSync(path.join(root, 'docs/migrations/ops-72-live-shadow-evidence.json'), 'utf8'));
  assert.deepEqual(validateLiveEvidence(artifact), {
    schemaVersion: 2,
    issue: 'OPS-72',
    observations: 5,
    excludedObservations: 1,
    passCount: 5,
    targetStatus: 'revise',
    rawArtifactsChecked: false,
  });
});

test('OPS-72 verifier rejects stale accepted proof', () => {
  const artifact = JSON.parse(readFileSync(path.join(root, 'docs/migrations/ops-72-live-shadow-evidence.json'), 'utf8'));
  artifact.observations[0].stale = true;
  assert.throws(() => validateLiveEvidence(artifact), /stale must be false/);
});

test('OPS-72 verifier accepts schema-v2 telemetry fields on comparable evidence', () => {
  const artifact = JSON.parse(readFileSync(path.join(root, 'docs/migrations/ops-72-live-shadow-evidence.json'), 'utf8'));
  artifact.observations[0].telemetry = {
    schemaVersion: 2,
    cohortId: 'ops72-live-v2',
    queuedAtUtc: '2026-08-14T18:00:00.000Z',
    startedAtUtc: '2026-08-14T18:00:01.000Z',
    completedAtUtc: '2026-08-14T18:00:03.000Z',
    queueDurationMs: 1000,
    executionDurationMs: 2000,
    retryCount: 0,
    autoRetryCount: 0,
    fullRetryCount: 0,
    firstActionableFailure: null,
  };
  assert.equal(validateLiveEvidence(artifact).passCount, 5);
});

test('OPS-72 verifier keeps an unmet timing target in revise state', () => {
  const artifact = JSON.parse(readFileSync(path.join(root, 'docs/migrations/ops-72-live-shadow-evidence.json'), 'utf8'));
  artifact.aggregate.shadowDurationReductionPercent = 25.1;
  artifact.aggregate.rerunReductionPercent = 5;
  assert.throws(() => validateLiveEvidence(artifact), /revise status must retain an unmet or unmeasurable target/);
});

test('OPS-72 verifier rejects malformed schema-v2 telemetry', () => {
  const artifact = JSON.parse(readFileSync(path.join(root, 'docs/migrations/ops-72-live-shadow-evidence.json'), 'utf8'));
  artifact.observations[0].telemetry = { schemaVersion: 1 };
  assert.throws(() => validateLiveEvidence(artifact), /telemetry\.schemaVersion must be 2/);
});
