import assert from 'node:assert/strict';
import {
  mkdirSync,
  mkdtempSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { findBoundaryViolations } from '../../scripts/verify-toolchain-boundary.mjs';

function fixture(t, files) {
  const root = mkdtempSync(path.join(os.tmpdir(), 'opshub-boundary-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  for (const [relativePath, contents] of Object.entries(files)) {
    const target = path.join(root, relativePath);
    mkdirSync(path.dirname(target), { recursive: true });
    writeFileSync(target, contents, 'utf8');
  }
  return root;
}

test('current repository command surfaces have no unguarded dependency consumers', () => {
  const root = path.resolve(import.meta.dirname, '../..');
  assert.deepEqual(findBoundaryViolations(root), []);
});

test('raw Flutter and Nest commands fail closed', (t) => {
  const root = fixture(t, {
    'AGENTS.md': '| Flutter | `flutter build web` |\n| Nest | `npm test` |\n',
    'deploy/home-server/README.md': 'flutter build apk --release\n',
  });
  const violations = findBoundaryViolations(root);
  assert.deepEqual(
    violations.map(({ kind, path: relativePath, line }) => ({ kind, path: relativePath, line })),
    [
      { kind: 'flutter', path: 'AGENTS.md', line: 1 },
      { kind: 'npm', path: 'AGENTS.md', line: 2 },
      { kind: 'flutter', path: 'deploy/home-server/README.md', line: 1 },
    ],
  );
});

test('wrapper continuation, Docker maintenance and SDK setup are explicit exceptions', (t) => {
  const root = fixture(t, {
    'AGENTS.md': 'node scripts/run-with-toolchain.mjs\n  --profile flutter -- flutter test\n',
    'deploy/home-server/README.md': 'docker compose run --rm maintenance npm run import:users\n',
    '.github/workflows/setup.yml': 'flutter --version\n',
  });
  assert.deepEqual(findBoundaryViolations(root), []);
});

test('raw workflow Prisma maintenance is allowlisted only for the explicit remote path', (t) => {
  const root = fixture(t, {
    '.github/workflows/deploy-opshub-staging.yml':
      'npx --no-install prisma migrate resolve --rolled-back "$migration_name"\n',
    '.github/workflows/other.yml':
      'npx --no-install prisma migrate resolve --rolled-back "$migration_name"\n',
  });
  const violations = findBoundaryViolations(root);
  assert.deepEqual(violations.map(({ path: relativePath }) => relativePath), [
    '.github/workflows/other.yml',
  ]);
});
