#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ANSI_ESCAPE = /\x1b\[[0-?]*[ -/]*[@-~]/g;
const REQUEST_ID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const TELEMETRY_HASH_PATTERN = /^[a-f0-9]{8}$/;
const RANGE_PATTERN = /^home_(1|7|30|90)d$/;
const ALLOWED_VARIANTS = new Set(["legacy", "daily_series"]);
const EXPECTED_GROUPS = [1, 7, 30, 90].flatMap((days) =>
  ["legacy", "daily_series"].map((variant) => `home_${days}d:${variant}`),
);

function finiteNumber(value) {
  if (value === null || value === undefined || value === "") return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : null;
}

function nonnegativeInteger(value) {
  const parsed = finiteNumber(value);
  return parsed !== null && Number.isInteger(parsed) ? parsed : null;
}

function percentile(sorted, fraction) {
  if (sorted.length === 0) return null;
  const position = (sorted.length - 1) * fraction;
  const lower = Math.floor(position);
  const upper = Math.ceil(position);
  if (lower === upper) return Number(sorted[lower].toFixed(3));
  const interpolated =
    sorted[lower] + (sorted[upper] - sorted[lower]) * (position - lower);
  return Number(interpolated.toFixed(3));
}

function distribution(values) {
  const sorted = values.filter(Number.isFinite).sort((a, b) => a - b);
  return {
    count: sorted.length,
    min: sorted.length === 0 ? null : Number(sorted[0].toFixed(3)),
    p50: percentile(sorted, 0.5),
    p95: percentile(sorted, 0.95),
    p99: percentile(sorted, 0.99),
    max: sorted.length === 0 ? null : Number(sorted.at(-1).toFixed(3)),
  };
}

export function parseCaddyTelemetry(input) {
  const rows = [];
  let rejected = 0;

  for (const line of String(input).split(/\r?\n/)) {
    if (!line.trim()) continue;
    try {
      const record = JSON.parse(line);
      const requestId = String(record.request_id || "").trim();
      const telemetryHash = String(record.telemetry_nonce_hash || "").trim();
      const range = String(record.load_range || "").trim();
      const variant = String(record.load_variant || "").trim();
      const totalSeconds = finiteNumber(record.duration);
      const reverseProxyMs = finiteNumber(record.reverse_proxy_duration_ms);
      const upstreamAttemptMs = finiteNumber(
        record.upstream_attempt_duration_ms,
      );
      const retries = nonnegativeInteger(record.reverse_proxy_retries);
      const status = nonnegativeInteger(record.status);
      if (
        !REQUEST_ID_PATTERN.test(requestId) ||
        !TELEMETRY_HASH_PATTERN.test(telemetryHash) ||
        !RANGE_PATTERN.test(range) ||
        !ALLOWED_VARIANTS.has(variant) ||
        totalSeconds === null ||
        reverseProxyMs === null ||
        upstreamAttemptMs === null ||
        retries === null ||
        status === null
      ) {
        rejected += 1;
        continue;
      }
      rows.push({
        requestId,
        telemetryHash,
        range,
        variant,
        status,
        totalMs: totalSeconds * 1000,
        reverseProxyMs,
        upstreamAttemptMs,
        retries,
      });
    } catch {
      rejected += 1;
    }
  }

  return { rows, rejected };
}

export function parseNestHttpRequests(input) {
  const rows = [];
  let rejected = 0;

  for (const rawLine of String(input).split(/\r?\n/)) {
    if (!rawLine.trim()) continue;
    const line = rawLine.replace(ANSI_ESCAPE, "");
    if (!line.includes("[HttpRequest]")) continue;
    const jsonStart = line.indexOf("{", line.indexOf("[HttpRequest]"));
    if (jsonStart < 0) {
      rejected += 1;
      continue;
    }
    try {
      const record = JSON.parse(line.slice(jsonStart));
      const requestId = String(record.requestId || "").trim();
      const durationMs = finiteNumber(record.durationMs);
      const status = nonnegativeInteger(record.statusCode);
      if (record.method !== "GET" || record.path !== "/home/summary") {
        continue;
      }
      if (
        !REQUEST_ID_PATTERN.test(requestId) ||
        durationMs === null ||
        status === null
      ) {
        rejected += 1;
        continue;
      }
      rows.push({ requestId, durationMs, status });
    } catch {
      rejected += 1;
    }
  }

  return { rows, rejected };
}

function uniqueByRequestId(rows) {
  const result = new Map();
  let duplicates = 0;
  for (const row of rows) {
    if (result.has(row.requestId)) {
      duplicates += 1;
      continue;
    }
    result.set(row.requestId, row);
  }
  return { rows: result, duplicates };
}

function summarizeRows(rows) {
  return {
    caddyTotalMs: distribution(rows.map((row) => row.totalMs)),
    reverseProxyTotalMs: distribution(rows.map((row) => row.reverseProxyMs)),
    upstreamAttemptMs: distribution(rows.map((row) => row.upstreamAttemptMs)),
    nestMs: distribution(rows.map((row) => row.nestMs)),
    caddyOutsideProxyMs: distribution(
      rows.map((row) => row.totalMs - row.reverseProxyMs),
    ),
    reverseProxyMinusNestMs: distribution(
      rows.map((row) => row.reverseProxyMs - row.nestMs),
    ),
    upstreamAttemptMinusNestMs: distribution(
      rows.map((row) => row.upstreamAttemptMs - row.nestMs),
    ),
  };
}

function validateOptions(options) {
  const telemetryHash = String(options?.telemetryHash || "").trim();
  const expectedCount = Number(options?.expectedCount);
  const expectedPerGroup = Number(options?.expectedPerGroup);
  if (!TELEMETRY_HASH_PATTERN.test(telemetryHash)) {
    throw new Error(
      "telemetryHash must be the expected 8-character SHA-256 prefix",
    );
  }
  if (!Number.isInteger(expectedCount) || expectedCount <= 0) {
    throw new Error("expectedCount must be a positive integer");
  }
  if (!Number.isInteger(expectedPerGroup) || expectedPerGroup <= 0) {
    throw new Error("expectedPerGroup must be a positive integer");
  }
  if (expectedCount !== expectedPerGroup * EXPECTED_GROUPS.length) {
    throw new Error(
      `expectedCount must equal expectedPerGroup * ${EXPECTED_GROUPS.length}`,
    );
  }
  return { telemetryHash, expectedCount, expectedPerGroup };
}

export function analyzeHomeIngressTelemetry(caddyInput, nestInput, options) {
  const expected = validateOptions(options);
  const caddy = parseCaddyTelemetry(caddyInput);
  const nest = parseNestHttpRequests(nestInput);
  const selectedCaddy = caddy.rows.filter(
    (row) => row.telemetryHash === expected.telemetryHash,
  );
  const caddyUnique = uniqueByRequestId(selectedCaddy);
  const selectedRequestIds = new Set(caddyUnique.rows.keys());
  const relevantNest = nest.rows.filter((row) =>
    selectedRequestIds.has(row.requestId),
  );
  const nestUnique = uniqueByRequestId(relevantNest);
  const correlated = [];
  let unexpectedStatus = 0;
  let statusMismatch = 0;
  let negativeDelta = 0;
  let nonzeroRetries = 0;

  for (const caddyRow of caddyUnique.rows.values()) {
    const nestRow = nestUnique.rows.get(caddyRow.requestId);
    if (!nestRow) continue;
    if (caddyRow.status !== 200 || nestRow.status !== 200)
      unexpectedStatus += 1;
    if (caddyRow.status !== nestRow.status) statusMismatch += 1;
    if (caddyRow.retries !== 0) nonzeroRetries += 1;
    const row = {
      ...caddyRow,
      nestMs: nestRow.durationMs,
    };
    if (
      row.totalMs - row.reverseProxyMs < 0 ||
      row.reverseProxyMs - row.nestMs < 0 ||
      row.upstreamAttemptMs - row.nestMs < 0
    ) {
      negativeDelta += 1;
    }
    correlated.push(row);
  }

  const groups = Object.fromEntries(EXPECTED_GROUPS.map((key) => [key, []]));
  for (const row of correlated) {
    groups[`${row.range}:${row.variant}`].push(row);
  }
  const groupCounts = Object.fromEntries(
    EXPECTED_GROUPS.map((key) => [key, groups[key].length]),
  );
  const reasons = [];
  const requireZero = (value, label) => {
    if (value !== 0) reasons.push(`${label}=${value}`);
  };

  requireZero(caddy.rejected, "caddyRejected");
  if (selectedCaddy.length !== expected.expectedCount) {
    reasons.push(
      `selectedCaddy=${selectedCaddy.length}, expected=${expected.expectedCount}`,
    );
  }
  requireZero(caddyUnique.duplicates, "caddyDuplicates");
  requireZero(nest.rejected, "nestRejected");
  requireZero(nestUnique.duplicates, "nestDuplicates");
  requireZero(caddyUnique.rows.size - correlated.length, "missingNest");
  requireZero(unexpectedStatus, "unexpectedStatus");
  requireZero(statusMismatch, "statusMismatch");
  requireZero(negativeDelta, "negativeDelta");
  requireZero(nonzeroRetries, "nonzeroRetries");
  if (correlated.length !== expected.expectedCount) {
    reasons.push(
      `correlated=${correlated.length}, expected=${expected.expectedCount}`,
    );
  }
  for (const key of EXPECTED_GROUPS) {
    if (groupCounts[key] !== expected.expectedPerGroup) {
      reasons.push(
        `${key}=${groupCounts[key]}, expected=${expected.expectedPerGroup}`,
      );
    }
  }

  return {
    gate: { passed: reasons.length === 0, reasons },
    counts: {
      caddyAccepted: caddy.rows.length,
      caddyIgnoredOtherTelemetry: caddy.rows.length - selectedCaddy.length,
      caddySelected: selectedCaddy.length,
      caddyRejected: caddy.rejected,
      caddyDuplicates: caddyUnique.duplicates,
      nestAccepted: nest.rows.length,
      nestIgnoredOtherRequests: nest.rows.length - relevantNest.length,
      nestRelevant: relevantNest.length,
      nestRejected: nest.rejected,
      nestDuplicates: nestUnique.duplicates,
      correlated: correlated.length,
      missingNest: caddyUnique.rows.size - correlated.length,
      unexpectedStatus,
      statusMismatch,
      negativeDelta,
      nonzeroRetries,
    },
    groupCounts,
    overall: summarizeRows(correlated),
    byRangeVariant: Object.fromEntries(
      EXPECTED_GROUPS.map((key) => [key, summarizeRows(groups[key])]),
    ),
  };
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key?.startsWith("--") || !value) {
      throw new Error(
        "Usage: --caddy <file> --nest <file> --telemetry-hash <8hex> --expected-count <n> --expected-per-group <n> [--output <file>]",
      );
    }
    args[key.slice(2)] = value;
  }
  for (const key of [
    "caddy",
    "nest",
    "telemetry-hash",
    "expected-count",
    "expected-per-group",
  ]) {
    if (!args[key]) throw new Error(`--${key} is required.`);
  }
  return args;
}

const isMain = process.argv[1]
  ? path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
  : false;

if (isMain) {
  try {
    const args = parseArgs(process.argv.slice(2));
    const result = analyzeHomeIngressTelemetry(
      fs.readFileSync(args.caddy, "utf8"),
      fs.readFileSync(args.nest, "utf8"),
      {
        telemetryHash: args["telemetry-hash"],
        expectedCount: args["expected-count"],
        expectedPerGroup: args["expected-per-group"],
      },
    );
    const output = `${JSON.stringify(result, null, 2)}\n`;
    if (args.output) {
      fs.writeFileSync(args.output, output, { mode: 0o600 });
      fs.chmodSync(args.output, 0o600);
    } else {
      process.stdout.write(output);
    }
    if (!result.gate.passed) process.exitCode = 2;
  } catch (error) {
    process.stderr.write(`${error instanceof Error ? error.message : error}\n`);
    process.exitCode = 1;
  }
}
