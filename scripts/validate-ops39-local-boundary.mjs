import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';

const tracked = execFileSync('git', ['ls-files'], { encoding: 'utf8' })
  .split(/\r?\n/)
  .filter(Boolean);
const forbiddenTracked = tracked.filter((file) => {
  if (!existsSync(file)) return false;
  const lower = file.toLowerCase();
  const bankMaterial = /(?:bidv|bankapi)/.test(lower);
  const operational =
    /(?:runbook|playbook|handoff|operator|operations|recovery)/.test(lower);
  return (
    (lower.startsWith('docs/runbooks/') && bankMaterial) ||
    (lower.startsWith('docs/help/') && bankMaterial) ||
    (bankMaterial && operational) ||
    (lower.endsWith('.pdf') && bankMaterial) ||
    (bankMaterial && /generate.*(?:pdf|playbook)/.test(lower)) ||
    lower.startsWith('output/bidv-private/')
  );
});
assert.deepEqual(forbiddenTracked, []);

for (const workflow of [
  '.github/workflows/deploy-opshub-staging.yml',
  '.github/workflows/deploy-opshub.yml',
  '.github/workflows/promote-production.yml',
]) {
  const source = readFileSync(workflow, 'utf8');
  assert.doesNotMatch(source, /upsert_env\s+BIDV_H2H_/);
  assert.doesNotMatch(source, /BIDV_H2H_KEK_BASE64/);
  assert.doesNotMatch(source, /BIDV_H2H_(?:INGEST|PROJECTION)_ENABLED/);
  assert.doesNotMatch(source, /prepare-bidv-legacy-rollback\.sh/);
  if (
    workflow.includes('deploy-opshub') ||
    workflow.includes('promote-production')
  ) {
    assert.match(source, /node scripts\/validate-ops39-local-boundary\.mjs/);
  }
}

const runtimeBuilder = readFileSync(
  'scripts/build-runtime-release.mjs',
  'utf8',
);
assert.doesNotMatch(runtimeBuilder, /output\/bidv-private/);
assert.match(runtimeBuilder, /deploy\/home-server\/bootstrap-bidv-kek\.sh/);

const runtimeManifest = 'dist/runtime-release/release-manifest.json';
if (existsSync(runtimeManifest)) {
  const manifest = JSON.parse(readFileSync(runtimeManifest, 'utf8'));
  const paths = manifest.files.map((entry) => String(entry.path).toLowerCase());
  assert.ok(paths.includes('deploy/home-server/bootstrap-bidv-kek.sh'));
  assert.equal(
    paths.some(
      (file) =>
        /(?:bidv|bankapi)/.test(file) &&
        /(?:runbook|playbook|handoff|operator|operations|recovery|\.pdf$)/.test(
          file,
        ),
    ),
    false,
  );
}
console.log('OPS-39 local-only promotion boundary PASS');
