import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import http from 'node:http';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repositoryRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
  '..',
);
const composePath = path.join(
  repositoryRoot,
  'deploy',
  'home-server',
  'docker-compose.home.yml',
);
const caddyfilePath = path.join(
  repositoryRoot,
  'deploy',
  'home-server',
  'Caddyfile',
);
const compose = fs.readFileSync(composePath, 'utf8');
const image = compose.match(
  /^\s*image:\s*(caddy:2-alpine@sha256:[0-9a-f]{64})\s*$/m,
)?.[1];

assert.ok(image, 'Pinned production Caddy image is missing from Compose');
const localBinary = String(process.env.OPSHUB_CADDY_BIN || '').trim();

function docker(args, { allowFailure = false } = {}) {
  const result = spawnSync('docker', args, {
    cwd: repositoryRoot,
    encoding: 'utf8',
    windowsHide: true,
  });
  if (!allowFailure && result.status !== 0) {
    const detail = [result.stdout, result.stderr]
      .filter(Boolean)
      .join('\n')
      .trim();
    throw new Error(
      `Docker command failed (${args.slice(0, 3).join(' ')}): ${detail}`,
    );
  }
  return result;
}

function request(port, host, requestPath) {
  return new Promise((resolve, reject) => {
    const request = http.request(
      {
        hostname: '127.0.0.1',
        port,
        path: requestPath,
        method: 'GET',
        headers: {
          Host: host,
          'X-Forwarded-Proto': 'https',
        },
        timeout: 3_000,
      },
      (response) => {
        const chunks = [];
        response.on('data', (chunk) => chunks.push(chunk));
        response.on('end', () => {
          resolve({
            status: response.statusCode,
            headers: response.headers,
            body: Buffer.concat(chunks).toString('utf8'),
          });
        });
      },
    );
    request.on('timeout', () => request.destroy(new Error('request timed out')));
    request.on('error', reject);
    request.end();
  });
}

async function waitForCaddy(port) {
  let lastError;
  for (let attempt = 1; attempt <= 40; attempt += 1) {
    try {
      const response = await request(port, 'phongvu.work', '/health');
      if (response.status === 200 && response.body.trim() === 'ok') return;
      lastError = new Error(
        `readiness returned ${response.status} body=${JSON.stringify(response.body)}`,
      );
    } catch (error) {
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(`Caddy did not become ready: ${lastError?.message}`);
}

function availablePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      server.close((error) => {
        if (error) reject(error);
        else resolve(address.port);
      });
    });
  });
}

function caddyPath(value) {
  return value.replaceAll('\\', '/');
}

async function startLocalCaddy(binary, tempRoot) {
  const port = await availablePort();
  const source = fs.readFileSync(caddyfilePath, 'utf8');
  const runtimeConfig = source
    .replace(/^\{\r?\n/, `{\n  admin off\n  http_port ${port}\n`)
    .replaceAll('/srv/web', caddyPath(path.join(tempRoot, 'web')))
    .replaceAll('/srv/downloads', caddyPath(path.join(tempRoot, 'downloads')))
    .replaceAll('/srv/uploads', caddyPath(path.join(tempRoot, 'uploads')))
    .replaceAll(
      '/srv/private-media',
      caddyPath(path.join(tempRoot, 'private-media')),
    );
  const runtimeConfigPath = path.join(tempRoot, 'Caddyfile');
  fs.writeFileSync(runtimeConfigPath, runtimeConfig);

  let diagnostics = '';
  const child = spawn(
    binary,
    ['run', '--config', runtimeConfigPath, '--adapter', 'caddyfile'],
    {
      cwd: repositoryRoot,
      env: {
        ...process.env,
        OPSHUB_DOMAIN: 'phongvu.work',
        OPSHUB_API_DOMAIN: 'api.phongvu.work',
        OPSHUB_LEGACY_DOMAIN: 'opshub.hoanghochoi.com',
      },
      stdio: ['ignore', 'ignore', 'pipe'],
      windowsHide: true,
    },
  );
  child.stderr.setEncoding('utf8');
  child.stderr.on('data', (chunk) => {
    diagnostics = `${diagnostics}${chunk}`.slice(-8_000);
  });

  try {
    await waitForCaddy(port);
  } catch (error) {
    child.kill();
    throw new Error(`${error.message}\n${diagnostics}`.trim());
  }
  return {
    port,
    stop: () => child.kill(),
  };
}

if (!localBinary) {
  const dockerInfo = docker(
    ['info', '--format', '{{.ServerVersion}}'],
    { allowFailure: true },
  );
  if (dockerInfo.status !== 0) {
    if (String(process.env.CI || '').toLowerCase() === 'true') {
      throw new Error(
        `Docker is required for the CI Caddy routing contract: ${dockerInfo.stderr.trim()}`,
      );
    }
    console.log(
      'Caddy exact-host isolation runtime contract: SKIP (Docker unavailable outside CI)',
    );
    process.exit(0);
  }
}

const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'opshub-caddy-host-'));
const containerName = `opshub-caddy-host-${process.pid}-${Date.now()}`;
let localCaddy;
for (const directory of ['web', 'downloads', 'uploads', 'private-media']) {
  fs.mkdirSync(path.join(tempRoot, directory), { recursive: true });
}
fs.writeFileSync(
  path.join(tempRoot, 'web', 'index.html'),
  '<!doctype html><title>OpsHub routing fixture</title>',
);

try {
  let port;
  if (localBinary) {
    localCaddy = await startLocalCaddy(localBinary, tempRoot);
    port = localCaddy.port;
  } else {
    docker([
      'run',
      '--rm',
      '--detach',
      '--name',
      containerName,
      '--env',
      'OPSHUB_DOMAIN=phongvu.work',
      '--env',
      'OPSHUB_API_DOMAIN=api.phongvu.work',
      '--env',
      'OPSHUB_LEGACY_DOMAIN=opshub.hoanghochoi.com',
      '--publish',
      '127.0.0.1::80',
      '--mount',
      `type=bind,source=${caddyfilePath},target=/etc/caddy/Caddyfile,readonly`,
      '--mount',
      `type=bind,source=${path.join(tempRoot, 'web')},target=/srv/web,readonly`,
      '--mount',
      `type=bind,source=${path.join(tempRoot, 'downloads')},target=/srv/downloads,readonly`,
      '--mount',
      `type=bind,source=${path.join(tempRoot, 'uploads')},target=/srv/uploads,readonly`,
      '--mount',
      `type=bind,source=${path.join(tempRoot, 'private-media')},target=/srv/private-media,readonly`,
      image,
    ]);

    const portOutput = docker(['port', containerName, '80/tcp']).stdout.trim();
    port = Number(portOutput.match(/:(\d+)$/)?.[1]);
    assert.ok(
      Number.isInteger(port) && port > 0,
      `Invalid Caddy port: ${portOutput}`,
    );
    await waitForCaddy(port);
  }

  const webHealth = await request(port, 'phongvu.work', '/health');
  assert.equal(webHealth.status, 200);
  assert.equal(webHealth.body.trim(), 'ok');

  const legacyHealth = await request(
    port,
    'opshub.hoanghochoi.com',
    '/health',
  );
  assert.equal(legacyHealth.status, 200);
  assert.equal(legacyHealth.body.trim(), 'ok');

  const legacyHelp = await request(port, 'opshub.hoanghochoi.com', '/help');
  assert.equal(legacyHelp.status, 308);
  assert.equal(legacyHelp.headers.location, 'https://phongvu.work/help');

  const apiWrongPath = await request(port, 'api.phongvu.work', '/health');
  assert.equal(apiWrongPath.status, 404);

  for (const [host, requestPath] of [
    ['unknown.phongvu.work', '/health'],
    ['unknown.phongvu.work', '/'],
    ['attacker.example', '/health'],
  ]) {
    const response = await request(port, host, requestPath);
    assert.equal(
      response.status,
      404,
      `${host}${requestPath} must fail closed`,
    );
    assert.equal(response.body.trim(), 'Not found');
  }

  console.log('Caddy exact-host isolation runtime contract: PASS');
} finally {
  localCaddy?.stop();
  docker(['rm', '--force', containerName], { allowFailure: true });
  fs.rmSync(tempRoot, { recursive: true, force: true });
}
