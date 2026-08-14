import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';

const root = path.resolve(import.meta.dirname, '..', '..');

// These are live execution entrypoints, rather than historical proof in docs.
// The source command must be wrapped inline: a preflight in a different CI job,
// shell block or manually resumed terminal is not sufficient proof of readiness.
const dependencyConsumers = [
  { relativePath: 'scripts/validate-contract-appendix.sh', pattern: /(?:flutter\s+(?:analyze|test|build)|npm\s+(?:test|run|ci|install)|npx\s+.*prisma)/i },
  { relativePath: 'scripts/validate-ops-11-payment-audio.ps1', pattern: /(?:flutter\s+(?:analyze|test|build)|npm\s+(?:test|run|ci|install)|npx\s+.*prisma)/i },
  { relativePath: '.github/workflows/build-windows-msix.yml', pattern: /flutter\s+(?:analyze|test|build)/i },
  { relativePath: '.github/workflows/deploy-opshub-staging.yml', pattern: /flutter\s+(?:analyze|test|build)/i },
  { relativePath: '.github/workflows/deploy-opshub.yml', pattern: /flutter\s+(?:analyze|test|build)/i },
];

const localConsumerPattern = /(?:flutter\s+(?:analyze|test|build)|npm\s+(?:test|run|ci|install)|npx\s+.*prisma)/i;

function source(relativePath) {
  return readFileSync(path.join(root, relativePath), 'utf8');
}

function sourceLine(contents, index) {
  const start = contents.lastIndexOf('\n', index) + 1;
  const end = contents.indexOf('\n', index);
  return contents.slice(start, end < 0 ? contents.length : end);
}

function consumerLines(contents, pattern) {
  return contents.split(/\r?\n/).filter((line) => {
    const trimmed = line.trimStart();
    return (
      pattern.test(trimmed) &&
      (/^(?:flutter|npm|npx)\s/i.test(trimmed) ||
        /(?:--|run:)\s+(?:flutter|npm|npx)\s/i.test(trimmed))
    );
  });
}

export function assertInlineToolchainBoundary(
  contents,
  relativePath = '<fixture>',
  pattern = localConsumerPattern,
) {
  const lines = consumerLines(contents, pattern);
  assert.ok(lines.length > 0, `${relativePath} must contain a dependency consumer`);
  for (const line of lines) {
    const failure = `${relativePath} runs a dependency consumer outside its own toolchain command block: ${line.trim()}`;
    assert.match(line, /run-with-toolchain\.mjs\b/i, failure);
    assert.match(line, /--profile\s+(?:flutter|nestjs)\b/i, failure);
    assert.match(line, /\s--\s+(?:flutter|npm|npx)\b/i, failure);
  }
}

test('dependency-consuming scripts and release workflows use an inline shared boundary', () => {
  for (const { relativePath, pattern } of dependencyConsumers) {
    assertInlineToolchainBoundary(source(relativePath), relativePath, pattern);
  }
});

test('a preflight in an earlier CI job or shell block cannot authorize a raw consumer', () => {
  assert.throws(
    () =>
      assertInlineToolchainBoundary(`
jobs:
  prepare:
    steps:
      - run: node scripts/prepare-task-toolchain.mjs --profile flutter
  build:
    steps:
      - run: flutter build web --no-pub
`, 'separate-workflow-job.yml'),
    /outside its own toolchain command block/,
  );
});

test('standalone Flutter validation forbids an implicit second pub writer', () => {
  const contents = source('scripts/validate-contract-appendix.sh');
  assert.match(contents, /node scripts\/run-with-toolchain\.mjs --profile flutter -- flutter test --no-pub/);
  assert.doesNotMatch(contents, /\nflutter test \\\n/);
});

test('Nest package lifecycle commands keep the gate before build/test/start consumers', () => {
  const packageJson = JSON.parse(source('backend-nest/package.json'));
  const scripts = packageJson.scripts;
  for (const command of [
    'build',
    'format',
    'lint',
    'start',
    'start:dev',
    'start:debug',
    'start:prod',
    'test',
    'test:watch',
    'test:cov',
    'test:debug',
    'test:e2e',
  ]) {
    assert.match(
      scripts[`pre${command}`],
      /run-with-toolchain\.mjs --root \.\. --profile nestjs --preflight-only/,
      `pre${command} must use the shared gate`,
    );
  }
});

test('Docker Nest build is self-contained without weakening local lifecycle gates', () => {
  const packageJson = JSON.parse(source('backend-nest/package.json'));
  const dockerfile = source('backend-nest/Dockerfile');

  assert.match(
    packageJson.scripts.prebuild,
    /run-with-toolchain\.mjs --root \.\. --profile nestjs --preflight-only/,
    'local npm run build must keep the shared Nest toolchain gate',
  );
  assert.match(
    dockerfile,
    /npx prisma generate && npm run build --ignore-scripts/,
    'the backend-only Docker context must execute Nest build without the local prebuild hook',
  );
});

test('release Flutter builds use the inline boundary and disable the implicit Pub writer', () => {
  for (const relativePath of [
    '.github/workflows/build-windows-msix.yml',
    '.github/workflows/deploy-opshub-staging.yml',
    '.github/workflows/deploy-opshub.yml',
  ]) {
    const contents = source(relativePath);
    for (const match of contents.matchAll(/flutter build [^\r\n]+/g)) {
      const line = sourceLine(contents, match.index);
      assert.match(line, /run-with-toolchain\.mjs --profile flutter -- flutter build/);
      assert.match(match[0], /--no-pub/, `${relativePath} has an implicit Flutter Pub writer`);
    }
  }
});

test('existing worktree repair command remains documented', () => {
  const contents = source('scripts/README.md');
  assert.match(contents, /prepare-task-toolchain\.mjs --root .* --profile all --force/);
  assert.match(contents, /repair\/doctor command/);
});
