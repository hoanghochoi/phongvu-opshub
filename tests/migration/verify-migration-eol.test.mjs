import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';

import { inspectMigrationEol } from '../../scripts/verify-migration-eol.mjs';

function createRepo(bytes) {
  const root = mkdtempSync(join(tmpdir(), 'opshub-migration-eol-'));
  const relativePath = 'docs/migrations/harness-v1-disposition.json';
  const absolutePath = join(root, relativePath);
  execFileSync('git', ['init', '--quiet', root]);
  execFileSync('git', ['-C', root, 'config', 'core.autocrlf', 'false']);
  execFileSync('git', ['-C', root, 'config', 'user.email', 'test@example.invalid']);
  execFileSync('git', ['-C', root, 'config', 'user.name', 'Migration EOL Test']);
  const parent = join(root, 'docs', 'migrations');
  mkdirSync(parent, { recursive: true });
  writeFileSync(absolutePath, bytes);
  execFileSync('git', ['-C', root, 'add', relativePath]);
  execFileSync('git', ['-C', root, 'commit', '--quiet', '-m', 'fixture']);
  return { root, relativePath, absolutePath };
}

test('passes when migration evidence bytes are committed LF bytes', () => {
  const fixture = createRepo(Buffer.from('{"ok":true}\n', 'utf8'));
  try {
    const result = inspectMigrationEol(fixture.root, { paths: [fixture.relativePath] });
    assert.equal(result.status, 'pass');
    assert.equal(result.files[0].hasCrlf, false);
    assert.equal(result.files[0].matchesGitBlob, true);
  } finally {
    rmSync(fixture.root, { recursive: true, force: true });
  }
});

test('fails closed when a Windows checkout drifts to CRLF', () => {
  const fixture = createRepo(Buffer.from('{"ok":true}\n', 'utf8'));
  try {
    writeFileSync(fixture.absolutePath, Buffer.from('{"ok":true}\r\n', 'utf8'));
    const result = inspectMigrationEol(fixture.root, { paths: [fixture.relativePath] });
    assert.equal(result.status, 'fail');
    assert.equal(result.files[0].hasCrlf, true);
    assert.equal(result.files[0].matchesGitBlob, false);
    assert.ok(result.issues.some((item) => item.code === 'MIGRATION_EVIDENCE_NON_LF'));
    assert.ok(result.issues.some((item) => item.code === 'MIGRATION_EVIDENCE_BYTES_DRIFT'));
  } finally {
    rmSync(fixture.root, { recursive: true, force: true });
  }
});
