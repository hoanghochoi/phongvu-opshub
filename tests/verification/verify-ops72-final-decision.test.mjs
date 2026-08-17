import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { validateDecision } from '../../scripts/verify-ops72-final-decision.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

function loadDecision() {
  return JSON.parse(readFileSync(path.join(root, 'docs/migrations/ops-72-final-decision.json'), 'utf8'));
}

test('OPS-190 accepts the final revise/do-not-promote decision', () => {
  assert.deepEqual(validateDecision(loadDecision(), { root }), {
    status: 'passed',
    issue: 'OPS-190',
    subjectIssue: 'OPS-72',
    decision: 'revise',
    promotionDecision: 'do-not-promote',
    matrixMode: 'observational',
    observations: 5,
    timingReductionPercent: 8.77,
    timingTargetPercent: 25,
  });
});

test('OPS-190 rejects a decision that claims promotion eligibility', () => {
  const decision = loadDecision();
  decision.promotionDecision = 'promote';
  assert.throws(() => validateDecision(decision, { root }), /promotionDecision must remain do-not-promote/);
});

test('OPS-190 rejects a changed evidence digest', () => {
  const decision = loadDecision();
  decision.evidence[0].sha256 = '0'.repeat(64);
  assert.throws(() => validateDecision(decision, { root }), /evidence hash mismatch/);
});

test('OPS-190 rejects a decision that claims the timing target was met', () => {
  const decision = loadDecision();
  decision.observed.timingTargetMet = true;
  assert.throws(() => validateDecision(decision, { root }), /timing target/);
});
