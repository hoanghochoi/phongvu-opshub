import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { validateClosure } from '../../scripts/verify-ops191-phase9-closure.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

function loadClosure() {
  return JSON.parse(readFileSync(path.join(root, 'docs/migrations/ops-191-phase9-closure.json'), 'utf8'));
}

test('OPS-191 accepts the exact-SHA Phase 9 closure evidence', () => {
  const result = validateClosure(loadClosure(), { root });
  assert.equal(result.status, 'passed');
  assert.equal(result.dependencyReady, 'passed');
  assert.equal(result.flutterPassed, 864);
  assert.equal(result.nestSuites, 124);
  assert.equal(result.nestPassed, 1315);
  assert.equal(result.goStatus, 'passed');
  assert.deepEqual(result.remainingGates, {
    upstreamHarnessUpdater: 'blocked-upstream',
    authenticatedStagingQa: 'open',
    productionDeployment: 'open',
  });
});

test('OPS-191 rejects stale or suppressed proof', () => {
  const closure = loadClosure();
  closure.proof.stale = true;
  assert.throws(() => validateClosure(closure, { root }), /proof must not be stale/);

  const unsuppressed = loadClosure();
  unsuppressed.proof.profilesSuppressed = ['flutter'];
  assert.throws(() => validateClosure(unsuppressed, { root }), /profiles must not be suppressed/);
});

test('OPS-191 rejects an unapproved BigQuery atomicity claim', () => {
  const closure = loadClosure();
  closure.authority.bigQueryBatchAtomicity.status = 'resolved';
  assert.throws(() => validateClosure(closure, { root }), /BigQuery batch atomicity must remain unapproved follow-up/);
});
