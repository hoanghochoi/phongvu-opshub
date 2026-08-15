import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  SCENARIOS,
  collectFailureInjectionCohort,
} from '../../scripts/collect-ops72-failure-injection.mjs';
import {
  validateFailureInjectionCohort,
} from '../../scripts/verify-ops72-failure-injection.mjs';

const CONTROLLED_REVISION = 'a'.repeat(40);

function fixture(t) {
  const root = mkdtempSync(path.join(os.tmpdir(), 'opshub-ops126-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  return root;
}

test('controlled cohort runs the real verifier seam and keeps promotion disabled', (t) => {
  const root = fixture(t);
  const output = path.join(root, 'cohort.json');
  const document = collectFailureInjectionCohort({
    root,
    output,
    revision: CONTROLLED_REVISION,
  });

  assert.equal(document.scenarios.length, 5);
  assert.equal(document.aggregate.targetStatus, 'controlled-evidence-only');
  assert.equal(document.aggregate.promotionDecision, 'do-not-promote');
  assert.equal(document.aggregate.metricBasis, 'controlled-decision-latency');
  assert.deepEqual(
    document.scenarios.map((scenario) => scenario.id),
    SCENARIOS.map((scenario) => scenario.id),
  );
  assert.equal(document.aggregate.baselineMedianDecisionLatencyMs, 1500);
  assert.equal(document.aggregate.candidateMedianDecisionLatencyMs, 700);
  assert.equal(document.aggregate.controlledDecisionLatencyReductionPercent, 53.33);
  assert.equal(document.aggregate.baselineRetryCount, 2);
  assert.equal(document.aggregate.candidateRetryCount, 0);
  assert.equal(document.aggregate.rerunReductionPercent, 100);

  const product = document.scenarios.find((scenario) => scenario.id === 'product-failure');
  assert.equal(product.observed.candidate.auto.exitCode, 3);
  assert.equal(product.observed.candidate.auto.retryCount, 0);
  assert.equal(product.invariants.productFailureDidNotRetryToGreen, true);

  const stale = document.scenarios.find((scenario) => scenario.id === 'stale-proof');
  assert.equal(stale.observed.candidate.auto.exitCode, 4);
  assert.equal(stale.observed.candidate.auto.fingerprint.stale, true);
  assert.equal(stale.invariants.staleProofRejected, true);

  const unknown = document.scenarios.find((scenario) => scenario.id === 'contract-unknown-path');
  assert.equal(unknown.observed.candidate.auto.exitCode, 2);
  assert.equal(unknown.observed.candidate.auto.commandAttempts, 0);
  assert.equal(validateFailureInjectionCohort(document, { rawRoot: root }).valid, true);

  const firstRaw = path.resolve(root, document.scenarios[0].rawArtifacts[0].file);
  assert.equal(existsSync(firstRaw), true);
  const tampered = structuredClone(document);
  tampered.scenarios[0].observed.candidate.auto.decisionLatencyMs += 1;
  assert.throws(() => validateFailureInjectionCohort(tampered), /Scenario hash/);
  tampered.scenarios[0].rawArtifacts[0].sha256 = '0'.repeat(64);
  assert.throws(
    () => validateFailureInjectionCohort(tampered, { rawRoot: root }),
    /Raw artifact hash/,
  );
});

test('CLI generator and validator produce sanitized repository-relative output', (t) => {
  const output = 'tmp/ops126-cli-test.json';
  const script = path.resolve(
    import.meta.dirname,
    '../../scripts/collect-ops72-failure-injection.mjs',
  );
  const validator = path.resolve(
    import.meta.dirname,
    '../../scripts/verify-ops72-failure-injection.mjs',
  );
  execFileSync(process.execPath, [script, '--output', output], {
    cwd: process.cwd(),
    encoding: 'utf8',
    windowsHide: true,
  });
  const generatedOutput = path.resolve(process.cwd(), output);
  const parsed = JSON.parse(readFileSync(generatedOutput, 'utf8'));
  assert.equal(parsed.aggregate.targetStatus, 'controlled-evidence-only');
  assert.equal(JSON.stringify(parsed).includes(process.cwd()), false);
  execFileSync(process.execPath, [validator, '--input', output, '--raw-root', '.'], {
    cwd: process.cwd(),
    encoding: 'utf8',
    windowsHide: true,
  });
});
