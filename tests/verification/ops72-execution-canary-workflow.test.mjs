import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';

const root = path.resolve(import.meta.dirname, '../..');
const workflow = readFileSync(path.join(root, '.github/workflows/verify-task-shadow.yml'), 'utf8');

test('execution canary is a separate non-blocking lane with pinned actions', () => {
  assert.match(workflow, /execution-canary:/);
  assert.match(workflow, /name: OPS-72 execution canary/);
  assert.match(workflow, /continue-on-error: true/);
  assert.match(workflow, /--execution-canary/);
  assert.match(workflow, /OPSHUB_SHADOW_RUN_ATTEMPT:/);
  assert.match(workflow, /name: verify-task-execution-canary-\$\{\{ github\.event\.pull_request\.number \}\}/);
  assert.match(workflow, /uses: actions\/checkout@[0-9a-f]{40}/);
  assert.match(workflow, /uses: actions\/upload-artifact@[0-9a-f]{40}/);
});

test('existing plan-only shadow lane remains intact and observational', () => {
  assert.match(workflow, /OPSHUB_SHADOW_COHORT_ID: ops72-live-v2/);
  assert.match(workflow, /node scripts\/verify-task-shadow\.mjs \\\n\s+--base \"\$BASE_SHA\" \\\n\s+--json tmp\/verify-task-shadow\.json/);
  assert.match(workflow, /blockingChecksUnchanged/);
});
