#!/usr/bin/env node

import process from 'node:process';
import { pathToFileURL } from 'node:url';

export const LEGACY_UPLOAD_LOGGER = 'http.log.access.legacy_uploads';

function increment(counter, key) {
  counter.set(key, (counter.get(key) ?? 0) + 1);
}

function sortedRecord(counter) {
  return Object.fromEntries(
    [...counter.entries()].sort(([left], [right]) => left.localeCompare(right)),
  );
}

function toIsoTimestamp(value) {
  if (typeof value !== 'number' || !Number.isFinite(value)) return null;
  return new Date(value * 1000).toISOString();
}

export function summarizeLegacyUploadAccessLines(lines) {
  const pathHashes = new Set();
  const methods = new Map();
  const statuses = new Map();
  let totalHits = 0;
  let ignoredLines = 0;
  let malformedAccessLines = 0;
  let firstTimestamp = null;
  let lastTimestamp = null;

  for (const rawLine of lines) {
    const line = String(rawLine).trim();
    if (!line) continue;

    let entry;
    try {
      entry = JSON.parse(line);
    } catch {
      ignoredLines += 1;
      continue;
    }

    if (entry?.logger !== LEGACY_UPLOAD_LOGGER) {
      ignoredLines += 1;
      continue;
    }

    const pathHash = entry.legacy_path;
    const request = entry?.request;
    const method = request?.method;
    const status = entry.status;
    const requestKeys =
      request && typeof request === 'object' ? Object.keys(request) : [];
    const hasUnexpectedRequestField = requestKeys.some(
      (key) => key !== 'method',
    );
    const hasUnexpectedTopLevelField =
      Object.hasOwn(entry, 'resp_headers') || Object.hasOwn(entry, 'user_id');
    if (
      typeof pathHash !== 'string' ||
      !/^[a-f0-9]{8}$/i.test(pathHash) ||
      typeof method !== 'string' ||
      !Number.isInteger(status) ||
      hasUnexpectedRequestField ||
      hasUnexpectedTopLevelField
    ) {
      malformedAccessLines += 1;
      continue;
    }

    totalHits += 1;
    pathHashes.add(pathHash.toLowerCase());
    increment(methods, method.toUpperCase());
    increment(statuses, String(status));

    if (typeof entry.ts === 'number' && Number.isFinite(entry.ts)) {
      firstTimestamp =
        firstTimestamp === null ? entry.ts : Math.min(firstTimestamp, entry.ts);
      lastTimestamp =
        lastTimestamp === null ? entry.ts : Math.max(lastTimestamp, entry.ts);
    }
  }

  return {
    ok: malformedAccessLines === 0,
    logger: LEGACY_UPLOAD_LOGGER,
    totalHits,
    uniquePathHashes: pathHashes.size,
    firstSeen: toIsoTimestamp(firstTimestamp),
    lastSeen: toIsoTimestamp(lastTimestamp),
    methods: sortedRecord(methods),
    statuses: sortedRecord(statuses),
    malformedAccessLines,
    ignoredLines,
  };
}

export function parseAuditArgs(args) {
  const supported = new Set(['--strict', '--fail-on-hits']);
  for (const arg of args) {
    if (!supported.has(arg)) {
      throw new Error(`Unsupported argument: ${arg}`);
    }
  }
  return {
    strict: args.includes('--strict'),
    failOnHits: args.includes('--fail-on-hits'),
  };
}

async function readStdin() {
  let input = '';
  process.stdin.setEncoding('utf8');
  for await (const chunk of process.stdin) input += chunk;
  return input.split(/\r?\n/);
}

async function main() {
  const options = parseAuditArgs(process.argv.slice(2));
  const summary = summarizeLegacyUploadAccessLines(await readStdin());
  process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);

  if (options.strict && summary.malformedAccessLines > 0) {
    process.exitCode = 2;
    return;
  }
  if (options.failOnHits && summary.totalHits > 0) {
    process.exitCode = 3;
  }
}

const entryPoint = process.argv[1]
  ? pathToFileURL(process.argv[1]).href
  : undefined;
if (entryPoint === import.meta.url) {
  main().catch((error) => {
    process.stderr.write(
      `${error instanceof Error ? error.message : String(error)}\n`,
    );
    process.exitCode = 1;
  });
}
