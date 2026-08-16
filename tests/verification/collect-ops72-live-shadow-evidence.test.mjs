import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  collectLiveEvidence,
} from '../../scripts/collect-ops72-live-shadow-evidence.mjs';
import {
  validateLiveEvidence,
} from '../../scripts/verify-ops72-live-shadow-evidence.mjs';

const ROOT = path.resolve(import.meta.dirname, '../..');
const COHORT = 'ops72-live-v2';

function sha(character) {
  return character.repeat(40);
}

function digest(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function baselineDocument() {
  return JSON.parse(readFileSync(path.join(ROOT, 'docs/migrations/ops-72-live-shadow-evidence.json'), 'utf8'));
}

function createFixture(t) {
  const root = mkdtempSync(path.join(os.tmpdir(), 'opshub-ops130-live-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const rawRoot = path.join(root, 'raw');
  mkdirSync(rawRoot, { recursive: true });
  const baseline = path.join(root, 'baseline.json');
  writeFileSync(baseline, `${JSON.stringify(baselineDocument(), null, 2)}\n`);
  return { root, rawRoot, baseline, output: path.join(root, 'evidence.json') };
}

function writeRun(fixture, index, durationMs = 6000 + index * 100) {
  const pullRequest = 900 + index;
  const runId = 40000 + index;
  const directory = path.join(fixture.rawRoot, String(runId));
  mkdirSync(directory, { recursive: true });
  const started = `2026-08-15T10:0${index}:00.000Z`;
  const completed = new Date(Date.parse(started) + durationMs).toISOString();
  const report = {
    schemaVersion: 3,
    mode: 'shadow',
    baseSha: sha('a'),
    headSha: sha('bcdef'[Math.min(index, 5) - 1] || 'b'),
    changedPaths: ['docs/example.md'],
    autoSelectedProfiles: ['docs'],
    autoAffectedConsumers: ['repository documentation'],
    fullProfiles: ['harness', 'docs'],
    fullAffectedConsumers: ['repository documentation'],
    omittedProfiles: ['harness'],
    omittedConsumers: [],
    unmatchedPaths: [],
    autoExitCode: 0,
    fullExitCode: 0,
    status: 'passed',
    classification: 'shadow-observation',
    fingerprint: { before: {}, after: {}, stale: false },
    commandDefinitions: [],
    blockingChecksUnchanged: true,
    retryPolicy: { maxInfrastructureRetries: 1 },
    telemetry: {
      schemaVersion: 3,
      cohortId: COHORT,
      queuedAtUtc: started,
      startedAtUtc: started,
      completedAtUtc: completed,
      queueDurationMs: 0,
      executionDurationMs: durationMs,
      executionMode: 'plan-only',
      autoDurationMs: Math.max(0, durationMs - 100),
      fullDurationMs: 100,
      decisionDurationMs: Math.max(0, durationMs - 100),
      queueTimestampSource: 'workflow-run-started-at',
      retryCount: 0,
      autoRetryCount: 0,
      fullRetryCount: 0,
      firstActionableFailure: null,
      firstObservedFailure: null,
      measurementEligibility: {
        retryReduction: false,
        timeToActionableFailure: false,
        reasonCode: 'plan-only-shadow',
      },
    },
    metrics: {
      firstActionableFailure: null,
      reruns: 0,
      humanIntervention: false,
      falsePositive: null,
      falseNegative: null,
      requiresCanaryReview: true,
    },
  };
  const reportBytes = Buffer.from(`${JSON.stringify(report, null, 2)}\n`);
  writeFileSync(path.join(directory, 'verify-task-shadow.json'), reportBytes);
  const manifest = {
    formatVersion: 1,
    issue: 'OPS-72',
    targetBranch: 'staging',
    cohortId: COHORT,
    pullRequest,
    runId,
    runUrl: `https://github.com/hoanghochi/phongvu-opshub/actions/runs/${runId}`,
    prHeadSha: sha('fedcba'[Math.min(index, 5) - 1] || 'a'),
    baseSha: sha('a'),
    reportedHeadSha: report.headSha,
    reportFile: 'verify-task-shadow.json',
    reportSha256: digest(reportBytes),
    generatedAtUtc: completed,
    run: {
      createdAt: started,
      startedAt: started,
      completedAt: completed,
      githubDurationMs: durationMs + 500,
    },
  };
  writeFileSync(path.join(directory, 'verify-task-shadow-manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`);
}

test('collects five workflow manifests into validator-compatible evidence', (t) => {
  const fixture = createFixture(t);
  for (let index = 1; index <= 5; index += 1) writeRun(fixture, index);

  const document = collectLiveEvidence(fixture);
  assert.equal(document.observations.length, 5);
  assert.equal(document.cohortId, COHORT);
  assert.equal(document.aggregate.targetStatus, 'revise');
  assert.equal(document.aggregate.shadowDurationMedianMs, 6300);
  assert.equal(document.aggregate.rerunReductionPercent, null);
  assert.equal(validateLiveEvidence(document, { rawRoot: fixture.rawRoot }).passCount, 5);
  assert.equal(JSON.stringify(document).includes(fixture.root), false);
});

test('fails closed on report hash mismatch and duplicate/missing manifests', (t) => {
  const fixture = createFixture(t);
  for (let index = 1; index <= 5; index += 1) writeRun(fixture, index);

  const firstReport = path.join(fixture.rawRoot, '40001', 'verify-task-shadow.json');
  writeFileSync(firstReport, `${readFileSync(firstReport, 'utf8')}\n`);
  assert.throws(() => collectLiveEvidence(fixture), /reportSha256 does not match/);

  const secondFixture = createFixture(t);
  for (let index = 1; index <= 4; index += 1) writeRun(secondFixture, index);
  writeRun(secondFixture, 5);
  writeRun(secondFixture, 6);
  assert.throws(() => collectLiveEvidence(secondFixture), /expected exactly 5 manifests/);
});

test('CLI accepts repository-relative raw-root, baseline and output paths', (t) => {
  const fixture = createFixture(t);
  for (let index = 1; index <= 5; index += 1) writeRun(fixture, index);
  const script = path.join(ROOT, 'scripts/collect-ops72-live-shadow-evidence.mjs');
  const output = path.relative(ROOT, fixture.output);
  const rawRoot = path.relative(ROOT, fixture.rawRoot);
  const baseline = path.relative(ROOT, fixture.baseline);
  const result = execFileSync(process.execPath, [script, '--raw-root', rawRoot, '--baseline', baseline, '--output', output], {
    cwd: ROOT,
    encoding: 'utf8',
    windowsHide: true,
  });
  assert.match(result, /"observations": 5/);
});
