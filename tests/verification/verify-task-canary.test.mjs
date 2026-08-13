import assert from 'node:assert/strict';
import test from 'node:test';
import { runCanaries } from '../../scripts/verify-task-canary.mjs';

test('repository protocol canaries select the expected consumers without DB state', () => {
  const results = runCanaries();
  assert.equal(results.length, 3);
  assert.ok(results.every((result) => result.status === 'passed'));
  assert.ok(results.every((result) => result.fingerprint.length === 64));
  assert.deepEqual(results.map((result) => result.name), [
    'harness-docs',
    'verification-tooling',
    'cross-stack-consumers',
  ]);
});
