import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';

const root = path.resolve(import.meta.dirname, '..', '..');

const dependencyConsumers = [
  'scripts/validate-contract-appendix.sh',
  'scripts/validate-ops-11-payment-audio.ps1',
  '.github/workflows/build-windows-msix.yml',
  '.github/workflows/deploy-opshub-staging.yml',
  '.github/workflows/deploy-opshub.yml',
];

function source(relativePath) {
  return readFileSync(path.join(root, relativePath), 'utf8');
}

test('dependency-consuming scripts and release workflows preflight before raw commands', () => {
  for (const relativePath of dependencyConsumers) {
    const contents = source(relativePath);
    const consumerPattern =
      /(?:^\s*(?:run:\s*)?|\{\s*)(?:flutter\s+(?:analyze|test|build)|npm\s+(?:test|run|ci|install)|npx\s+[^\n]*prisma)/gim;
    const consumerIndexes = [...contents.matchAll(consumerPattern)].map(
      (match) => match.index,
    );
    assert.ok(consumerIndexes.length > 0, `${relativePath} must contain a dependency consumer`);
    const preflight = contents.indexOf('prepare-task-toolchain.mjs');
    assert.notEqual(preflight, -1, `${relativePath} must invoke the shared preflight`);
    for (const consumerIndex of consumerIndexes) {
      assert.ok(
        preflight < consumerIndex,
        `${relativePath} invokes a dependency consumer before the shared preflight`,
      );
    }
  }
});

test('standalone Flutter validation forbids an implicit second pub writer', () => {
  const contents = source('scripts/validate-contract-appendix.sh');
  assert.match(contents, /node scripts\/prepare-task-toolchain\.mjs --profile all/);
  assert.match(contents, /flutter test --no-pub/);
  assert.doesNotMatch(contents, /\nflutter test \\\n/);
});

test('existing worktree repair command remains documented', () => {
  const contents = source('scripts/README.md');
  assert.match(contents, /prepare-task-toolchain\.mjs --root .* --profile all --force/);
  assert.match(contents, /repair\/doctor command/);
});
