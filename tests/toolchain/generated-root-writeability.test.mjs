import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, rmSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  clearReadOnlyDirectoryAttribute,
  ensureGeneratedRootWriteability,
  inspectGeneratedRootWriteability,
} from '../../scripts/prepare-task-toolchain.mjs';

function fixture(t) {
  const root = mkdtempSync(path.join(os.tmpdir(), 'opshub-generated-roots-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  for (const relativePath of [
    'lib/l10n',
    'ios/Runner',
    'linux/flutter',
    'macos/Flutter',
    'windows/flutter',
    'build/unit_test_assets/kernel',
    'backend-nest',
    'backend-nest/node_modules',
    '.dart_tool',
  ]) {
    mkdirSync(path.join(root, relativePath), { recursive: true });
  }
  return root;
}

function relative(root, absolutePath) {
  return path.relative(root, absolutePath).replaceAll('\\', '/');
}

test('Windows ReadOnly generated roots are normalized before hydration', (t) => {
  const root = fixture(t);
  const readOnlyPaths = new Set(['lib/l10n']);
  const cleared = [];

  const result = ensureGeneratedRootWriteability({
    root,
    profile: 'flutter',
    platform: 'win32',
    access: () => {},
    readOnly: (absolutePath) => readOnlyPaths.has(relative(root, absolutePath)),
    clearReadOnly: (absolutePath) => {
      const current = relative(root, absolutePath);
      cleared.push(current);
      readOnlyPaths.delete(current);
      return true;
    },
    probeWrite: (absolutePath) => !readOnlyPaths.has(relative(root, absolutePath)),
  });

  assert.equal(result.ready, true);
  assert.deepEqual(cleared, ['lib/l10n']);
  assert.deepEqual(result.normalizedPaths, ['lib/l10n']);
  assert.equal(
    inspectGeneratedRootWriteability({
      root,
      profile: 'flutter',
      platform: 'win32',
      access: () => {},
      readOnly: (absolutePath) => readOnlyPaths.has(relative(root, absolutePath)),
      probe: false,
    }).ready,
    true,
  );
});

test('Windows normalizes the nested Flutter unit-test output and its descendants only', (t) => {
  const root = fixture(t);
  const readOnlyPaths = new Set(['build/unit_test_assets']);
  const clearCalls = [];

  const result = ensureGeneratedRootWriteability({
    root,
    profile: 'flutter',
    platform: 'win32',
    access: () => {},
    readOnly: (absolutePath) => readOnlyPaths.has(relative(root, absolutePath)),
    clearReadOnly: (absolutePath, _platform, options) => {
      const current = relative(root, absolutePath);
      clearCalls.push({ current, ...options });
      if (options?.recursive) readOnlyPaths.delete(current);
      return true;
    },
    probeWrite: (absolutePath) => !readOnlyPaths.has(relative(root, absolutePath)),
  });

  assert.equal(result.ready, true);
  assert.deepEqual(result.normalizedPaths, ['build/unit_test_assets']);
  assert.deepEqual(clearCalls, [
    { current: 'build/unit_test_assets', recursive: true },
  ]);
  assert.equal(
    existsSync(path.join(root, 'build', 'unit_test_assets', 'kernel')),
    true,
  );
});

test('Windows recursive read-only repair clears only the unit-test output root and descendants', () => {
  const calls = [];
  const absolutePath = path.join('C:', 'fixture', 'build', 'unit_test_assets');
  const result = clearReadOnlyDirectoryAttribute(absolutePath, 'win32', {
    recursive: true,
    spawn: (executable, argv) => {
      calls.push({ executable, argv });
      return { status: 0 };
    },
  });

  assert.equal(result, true);
  assert.deepEqual(calls, [
    { executable: 'attrib', argv: ['-R', absolutePath] },
    {
      executable: 'attrib',
      argv: ['-R', path.join(absolutePath, '*'), '/S', '/D'],
    },
  ]);
});

test('ACL or filesystem denial fails closed without broad attribute repair', (t) => {
  const root = fixture(t);
  const cleared = [];
  const result = ensureGeneratedRootWriteability({
    root,
    profile: 'flutter',
    platform: 'win32',
    access: () => {
      throw new Error('access denied');
    },
    readOnly: () => false,
    clearReadOnly: (absolutePath) => {
      cleared.push(relative(root, absolutePath));
      return true;
    },
    probeWrite: () => false,
  });

  assert.equal(result.ready, false);
  assert.deepEqual(cleared, []);
  assert.match(result.error, /lib/);
  assert.match(result.error, /not writable/i);
});

test('dry-run reports a ReadOnly root but never normalizes it', (t) => {
  const root = fixture(t);
  const readOnlyPaths = new Set(['lib/l10n']);
  let clearCount = 0;
  const result = ensureGeneratedRootWriteability({
    root,
    profile: 'flutter',
    dryRun: true,
    platform: 'win32',
    access: () => {},
    readOnly: (absolutePath) => readOnlyPaths.has(relative(root, absolutePath)),
    clearReadOnly: () => {
      clearCount += 1;
      return true;
    },
    probeWrite: () => false,
  });

  assert.equal(result.ready, false);
  assert.equal(clearCount, 0);
  assert.equal(result.normalizedPaths, undefined);
  assert.equal(
    result.paths.find((entry) => entry.path === 'lib/l10n')?.error,
    'read-only-directory-attribute',
  );
});

test('a missing Nest node_modules directory is not mistaken for an unwritable parent', (t) => {
  const root = fixture(t);
  rmSync(path.join(root, 'backend-nest', 'node_modules'), {
    recursive: true,
    force: true,
  });
  const result = ensureGeneratedRootWriteability({
    root,
    profile: 'nestjs',
    platform: 'win32',
    access: () => {},
    readOnly: () => false,
    probeWrite: () => true,
  });

  assert.equal(result.ready, true);
  assert.equal(result.paths.some((entry) => entry.path === 'backend-nest'), true);
  assert.equal(result.paths.some((entry) => entry.path === 'backend-nest/node_modules'), true);
});

test('existing ignored dependency roots are normalized before hydration', (t) => {
  const root = fixture(t);
  const readOnlyPaths = new Set(['.dart_tool', 'backend-nest/node_modules']);
  const cleared = [];

  const result = ensureGeneratedRootWriteability({
    root,
    profile: 'all',
    platform: 'win32',
    access: () => {},
    readOnly: (absolutePath) => readOnlyPaths.has(relative(root, absolutePath)),
    clearReadOnly: (absolutePath) => {
      const current = relative(root, absolutePath);
      cleared.push(current);
      readOnlyPaths.delete(current);
      return true;
    },
    probeWrite: (absolutePath) => !readOnlyPaths.has(relative(root, absolutePath)),
  });

  assert.equal(result.ready, true);
  assert.deepEqual(cleared, ['backend-nest/node_modules', '.dart_tool']);
  assert.deepEqual(result.normalizedPaths, cleared);
  assert.equal(
    result.paths.find((entry) => entry.path === '.dart_tool')?.readOnlyAttribute,
    false,
  );
  assert.equal(
    result.paths.find((entry) => entry.path === 'backend-nest/node_modules')?.readOnlyAttribute,
    false,
  );
});

test('dry-run reports ignored dependency roots without changing their attributes', (t) => {
  const root = fixture(t);
  const readOnlyPaths = new Set(['.dart_tool', 'backend-nest/node_modules']);
  let clearCount = 0;

  const result = ensureGeneratedRootWriteability({
    root,
    profile: 'all',
    dryRun: true,
    platform: 'win32',
    access: () => {},
    readOnly: (absolutePath) => readOnlyPaths.has(relative(root, absolutePath)),
    clearReadOnly: () => {
      clearCount += 1;
      return true;
    },
    probeWrite: () => false,
  });

  assert.equal(result.ready, false);
  assert.equal(clearCount, 0);
  assert.equal(result.normalizedPaths, undefined);
  assert.equal(
    result.paths.find((entry) => entry.path === '.dart_tool')?.error,
    'read-only-directory-attribute',
  );
  assert.equal(
    result.paths.find((entry) => entry.path === 'backend-nest/node_modules')?.error,
    'read-only-directory-attribute',
  );
});
