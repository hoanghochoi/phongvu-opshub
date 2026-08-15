import assert from 'node:assert/strict';
import test from 'node:test';
import { buildInventory } from '../../scripts/collect-artifact-inventory.mjs';
import { validateInventory } from '../../scripts/verify-artifact-inventory.mjs';

function comparableInventory(inventory) {
  const copy = structuredClone(inventory);
  delete copy.generatedAtUtc;
  return JSON.stringify(copy);
}

test('OPS-73 inventory is machine-readable, owned and deletion-free', () => {
  const inventory = buildInventory();
  const result = validateInventory(inventory);
  assert.equal(result.status, 'passed');
  assert.equal(result.deletionBatchCount, 0);
  assert.ok(result.trackedCount > 1000);
  assert.ok(result.dependencyCount >= 7);
  assert.ok(result.assetCount > 0);
  assert.ok(inventory.ownerRules.some((rule) => rule.prefix === 'n8n/'));
});

test('inventory validator rejects absolute paths and deletion batches', () => {
  const inventory = buildInventory();
  inventory.tracked.paths.push('C:/private/file');
  inventory.tracked.fileCount += 1;
  assert.throws(() => validateInventory(inventory), /invalid\/duplicate tracked path/);
  const clean = buildInventory();
  clean.deletionBatches.push({ id: 'delete-anything' });
  assert.throws(() => validateInventory(clean), /cannot contain deletion batches/);
});

test('inventory validator accepts valid filenames containing consecutive dots', () => {
  const inventory = buildInventory();
  inventory.ignoredExisting.paths.push({
    path: 'build/androidx.lifecycle/lifecycle-runtime-2.8.7..jar',
    area: 'other',
    owner: 'generated/runtime output',
  });
  inventory.ignoredExisting.fileCount += 1;
  assert.doesNotThrow(() => validateInventory(inventory));
});

test('inventory validator rejects parent-directory traversal by path segment', () => {
  const inventory = buildInventory();
  inventory.tracked.paths[0] = 'docs/../README.md';
  assert.throws(() => validateInventory(inventory), /invalid\/duplicate tracked path/);
});

test('inventory collection is stable apart from its timestamp', () => {
  assert.equal(comparableInventory(buildInventory()), comparableInventory(buildInventory()));
});
