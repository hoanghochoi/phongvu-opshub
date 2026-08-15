import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

import { verifyColdDependencyCanary } from '../../scripts/verify-cold-dependency-canary.mjs';

const root = new URL('../..', import.meta.url);
const read = (relativePath) =>
  readFileSync(new URL(relativePath, root), 'utf8');

function reportFixture(overrides = {}) {
  const writable = { ready: true };
  return {
    status: 'passed',
    profile: 'all',
    preparation: {
      profiles: [
        {
          profile: 'nestjs',
          status: 'prepared',
          readiness: {
            writableGeneratedRoots: writable,
            missingDirectDependencies: [],
            missingLockPackages: [],
            missingPackageEntrypoints: [],
            prismaGenerated: true,
          },
        },
        {
          profile: 'flutter',
          status: 'prepared',
          readiness: {
            writableGeneratedRoots: writable,
            missingPackages: [],
            missingPlugins: [],
            packageConfigReadable: true,
            pluginMetadataReadable: true,
          },
        },
      ],
    },
    ...overrides,
  };
}

test('cold canary contract is path-filtered to dependency/toolchain surfaces', () => {
  const workflow = read('.github/workflows/cold-dependency-canary.yml');
  assert.match(workflow, /runs-on:\s+windows-latest/);
  assert.match(workflow, /paths:\s*[\s\S]*backend-nest\/package-lock\.json/);
  assert.match(workflow, /paths:\s*[\s\S]*pubspec\.lock/);
  assert.match(workflow, /materialize-dependencies:\s*['"]false['"]/);
  assert.match(workflow, /backend-nest\/node_modules/);
  assert.match(workflow, /\.dart_tool/);
  assert.match(workflow, /attrib \+R lib\\l10n/);
  assert.match(workflow, /toolchain-doctor\.mjs --profile all --force --json/);
  assert.match(workflow, /run-with-toolchain\.mjs --profile flutter -- flutter analyze --no-pub/);
  assert.match(workflow, /run-with-toolchain\.mjs --profile nestjs --cwd backend-nest -- npm run build/);
  assert.doesNotMatch(workflow, /continue-on-error:\s*true/);
});

test('setup-flutter keeps hydration enabled by default and supports canary opt-out', () => {
  const action = read('.github/actions/setup-flutter/action.yml');
  assert.match(action, /materialize-dependencies:/);
  assert.match(action, /default:\s*["']true["']/);
  assert.match(action, /if:\s*inputs\.materialize-dependencies\s*==\s*'true'/);
});

test('canary verifier accepts complete dual-profile readiness', () => {
  const result = verifyColdDependencyCanary({
    report: reportFixture(),
    checkFilesystem: false,
  });
  assert.equal(result.status, 'passed');
  assert.deepEqual(result.profiles, ['nestjs', 'flutter']);
});

test('canary verifier rejects incomplete materialization', () => {
  const report = reportFixture();
  report.preparation.profiles[1].readiness.missingPackages = ['http'];
  assert.throws(
    () => verifyColdDependencyCanary({ report, checkFilesystem: false }),
    /Flutter package or plugin materialization is incomplete/,
  );
});

test('canary verifier rejects a non-ready generated root', () => {
  const report = reportFixture();
  report.preparation.profiles[0].readiness.writableGeneratedRoots.ready = false;
  assert.throws(
    () => verifyColdDependencyCanary({ report, checkFilesystem: false }),
    /generated roots are not writable/,
  );
});
