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

const marker = 'http://{$BIDV_H2H_DOMAIN} {';
const start = caddy.indexOf(marker);
assert.notEqual(start, -1, 'Dedicated BIDV site is missing');
const site = caddy.slice(start);
assert.match(site, /path \/oauth2\/token \/v1\/balance-changes/);
assert.match(site, /handle \/health/);
assert.match(site, /respond "Not found" 404/);
for (const forbidden of [
  'handle_path /api/',
  'handle /ws',
  'root * /srv/web',
  'root * /srv/uploads',
  'root * /srv/downloads',
]) {
  assert.equal(
    site.includes(forbidden),
    false,
    `Dedicated BIDV site exposes forbidden handler: ${forbidden}`,
  );
}
assert.match(compose, /BIDV_H2H_DOMAIN: \$\{BIDV_H2H_DOMAIN:\?/);
assert.match(productionEnv, /BIDV_H2H_DOMAIN=bidv\.opshub\.hoanghochoi\.com/);
assert.match(
  stagingEnv,
  /BIDV_H2H_DOMAIN=bidv-staging\.opshub\.hoanghochoi\.com/,
);
for (const source of [productionEnv, stagingEnv]) {
  assert.match(source, /BIDV_H2H_INGEST_ENABLED=false/);
  assert.match(source, /BIDV_H2H_PROJECTION_ENABLED=false/);
}

console.log('OPS-39 Caddy/env isolation contract: PASS');
