import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

import {
  LEGACY_UPLOAD_LOGGER,
  parseAuditArgs,
  summarizeLegacyUploadAccessLines,
} from '../scripts/audit-legacy-upload-access.mjs';

const scriptPath = fileURLToPath(
  new URL('../scripts/audit-legacy-upload-access.mjs', import.meta.url),
);

function accessLine({ ts, pathHash, method = 'GET', status = 200 }) {
  return JSON.stringify({
    ts,
    logger: LEGACY_UPLOAD_LOGGER,
    request: { method },
    status,
    legacy_path: pathHash,
  });
}

test('summarizes legacy access without exposing paths or clients', () => {
  const summary = summarizeLegacyUploadAccessLines([
    'caddy startup message',
    JSON.stringify({ logger: 'http.log.access.other', request: {} }),
    accessLine({ ts: 1_720_000_000, pathHash: 'aabbccdd' }),
    accessLine({
      ts: 1_720_000_060,
      pathHash: 'aabbccdd',
      method: 'HEAD',
      status: 304,
    }),
    accessLine({ ts: 1_720_000_120, pathHash: '11223344', status: 404 }),
  ]);

  assert.deepEqual(summary, {
    ok: true,
    logger: LEGACY_UPLOAD_LOGGER,
    totalHits: 3,
    uniquePathHashes: 2,
    firstSeen: '2024-07-03T09:46:40.000Z',
    lastSeen: '2024-07-03T09:48:40.000Z',
    methods: { GET: 2, HEAD: 1 },
    statuses: { 200: 1, 304: 1, 404: 1 },
    malformedAccessLines: 0,
    ignoredLines: 2,
  });
  assert.equal(JSON.stringify(summary).includes('/uploads/'), false);
  assert.equal(JSON.stringify(summary).includes('remote_ip'), false);
});

test('marks an unredacted or incomplete access entry malformed', () => {
  const summary = summarizeLegacyUploadAccessLines([
    JSON.stringify({
      logger: LEGACY_UPLOAD_LOGGER,
      request: { method: 'GET' },
      status: 200,
      legacy_path: '/uploads/customer-name.jpg',
    }),
    JSON.stringify({
      logger: LEGACY_UPLOAD_LOGGER,
      request: { method: 'GET', uri: '/uploads/customer-name.jpg?token=raw' },
      status: 200,
      legacy_path: 'aabbccdd',
    }),
  ]);

  assert.equal(summary.ok, false);
  assert.equal(summary.totalHits, 0);
  assert.equal(summary.malformedAccessLines, 2);
});

test('rejects unsupported CLI arguments', () => {
  assert.deepEqual(parseAuditArgs(['--strict', '--fail-on-hits']), {
    strict: true,
    failOnHits: true,
  });
  assert.throws(
    () => parseAuditArgs(['--print-paths']),
    /Unsupported argument/,
  );
});

test('fail-on-hits exits non-zero without printing a raw path', () => {
  const result = spawnSync(
    process.execPath,
    [scriptPath, '--strict', '--fail-on-hits'],
    {
      encoding: 'utf8',
      input: `${accessLine({ ts: 1_720_000_000, pathHash: 'aabbccdd' })}\n`,
    },
  );

  assert.equal(result.status, 3);
  assert.match(result.stdout, /"totalHits": 1/);
  assert.equal(result.stdout.includes('/uploads/'), false);
  assert.equal(result.stderr, '');
});
