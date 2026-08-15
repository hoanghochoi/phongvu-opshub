import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';

const ROOT = path.resolve(import.meta.dirname, '../..');
const PREPARE_HOOK =
  'node ../scripts/run-with-toolchain.mjs --root .. --profile nestjs --preflight-only';
const DOCKER_ONLY = new Set(['verify:dockerfile:sharp']);

function read(relativePath) {
  return readFileSync(path.join(ROOT, relativePath), 'utf8');
}

test('dependency-owning Nest scripts have a local toolchain pre-hook', () => {
  const packageJson = JSON.parse(read('backend-nest/package.json'));
  for (const [name, command] of Object.entries(packageJson.scripts)) {
    if (name.startsWith('pre') || DOCKER_ONLY.has(name)) continue;
    const dependencyOwning = /^(?:node(?:\s|$)|node\s+-r|pwsh(?:\s|$))/.test(command);
    if (!dependencyOwning) continue;
    const hook = packageJson.scripts[`pre${name}`];
    assert.equal(
      hook,
      PREPARE_HOOK,
      `Missing Nest toolchain pre-hook for npm script ${name}`,
    );
  }
});

test('current runbooks and product contracts use the repository gate', () => {
  const currentDocs = [
    'backend-nest/README.md',
    'README-backend.md',
    'docs/product/help.md',
    'docs/product/profile-admin.md',
    'docs/product/ui-ux.md',
    'docs/product/warranty.md',
    'docs/runbooks/emergency-admin-access.md',
  ];
  const content = currentDocs.map(read).join('\n');
  assert.doesNotMatch(content, /`(?:npx prisma|npm (?:install|run|test)|flutter (?:pub|get|analyze|test|build|run)|dart format)\b/);
  assert.match(content, /run-with-toolchain\.mjs/);
});

test('Docker-only exceptions remain documented and the doctor is tracked', () => {
  const scriptsReadme = read('scripts/README.md');
  const profiles = read('scripts/verification-profiles.mjs');
  assert.match(scriptsReadme, /Docker-only verification commands/);
  assert.match(profiles, /toolchain-doctor/);
});
