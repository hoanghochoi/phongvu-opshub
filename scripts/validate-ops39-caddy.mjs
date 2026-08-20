import assert from 'node:assert/strict';
import fs from 'node:fs';

const caddy = fs.readFileSync('deploy/home-server/Caddyfile', 'utf8');
const compose = fs.readFileSync(
  'deploy/home-server/docker-compose.home.yml',
  'utf8',
);
const productionEnv = fs.readFileSync(
  'deploy/home-server/env.example',
  'utf8',
);
const stagingEnv = fs.readFileSync('deploy/staging/env.example', 'utf8');

const marker = 'http://{$OPSHUB_API_DOMAIN} {';
const start = caddy.indexOf(marker);
assert.notEqual(start, -1, 'Exact API site is missing');
const apiSite = caddy.slice(start, caddy.indexOf('http://{$OPSHUB_LEGACY_DOMAIN} {'));
assert.match(apiSite, /path \/v1\/bidv\/oauth2\/token/);
assert.match(apiSite, /path \/v1\/bidv\/balance-changes/);
assert.match(apiSite, /path \/v1\/bidv(?: |\/\*)/);
assert.match(apiSite, /path \/v1\/ws \/v1\/ws\*/);
assert.match(apiSite, /handle_path \/v1\/\*/);
assert.match(apiSite, /respond "Not found" 404/);
for (const forbidden of [
  'handle_path /api/',
  'root * /srv/web',
  'root * /srv/uploads',
  'root * /srv/downloads',
]) {
  assert.equal(
    apiSite.includes(forbidden),
    false,
    `API site exposes forbidden handler: ${forbidden}`,
  );
}
const legacyStart = caddy.indexOf('http://{$OPSHUB_LEGACY_DOMAIN} {');
assert.notEqual(legacyStart, -1, 'Legacy bridge site is missing');
const legacySite = caddy.slice(legacyStart);
assert.match(legacySite, /path \/api \/api\/\*/);
assert.match(legacySite, /handle @legacy_api/);
assert.match(legacySite, /handle \/ws\*/);
assert.match(legacySite, /redir https:\/\/\{\$OPSHUB_DOMAIN\}\{uri\} 308/);
assert.equal(caddy.includes('BIDV_H2H_DOMAIN'), false);
assert.match(compose, /OPSHUB_API_DOMAIN: \$\{OPSHUB_API_DOMAIN:\?/);
assert.match(compose, /OPSHUB_LEGACY_DOMAIN: \$\{OPSHUB_LEGACY_DOMAIN:\?/);
assert.match(productionEnv, /OPSHUB_DOMAIN=phongvu\.work/);
assert.match(productionEnv, /OPSHUB_API_DOMAIN=api\.phongvu\.work/);
assert.match(productionEnv, /BIDV_H2H_PUBLIC_BASE_URL=https:\/\/api\.phongvu\.work\/v1\/bidv/);
assert.match(stagingEnv, /OPSHUB_DOMAIN=staging\.phongvu\.work/);
assert.match(stagingEnv, /OPSHUB_API_DOMAIN=api-staging\.phongvu\.work/);
assert.match(stagingEnv, /BIDV_H2H_PUBLIC_BASE_URL=https:\/\/api-staging\.phongvu\.work\/v1\/bidv/);
for (const source of [productionEnv, stagingEnv]) {
  assert.match(source, /BIDV_H2H_INGEST_ENABLED=false/);
  assert.match(source, /BIDV_H2H_PROJECTION_ENABLED=false/);
}

console.log('OPS-39 Caddy/env isolation contract: PASS');
