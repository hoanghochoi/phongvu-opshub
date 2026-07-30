import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  analyzeHomeIngressTelemetry,
  parseCaddyTelemetry,
  parseNestHttpRequests,
} from "./analyze-home-ingress-telemetry.mjs";

const TELEMETRY_HASH = "0123abcd";
const OTHER_HASH = "89abcdef";
const groups = [1, 7, 30, 90].flatMap((days) =>
  ["legacy", "daily_series"].map((variant) => ({
    range: `home_${days}d`,
    variant,
  })),
);

function requestId(index) {
  return `00000000-0000-4000-8000-${String(index).padStart(12, "0")}`;
}

function fixture(perGroup = 1) {
  const caddy = [];
  const nest = [];
  let index = 1;
  for (const group of groups) {
    for (let item = 0; item < perGroup; item += 1) {
      const id = requestId(index++);
      caddy.push({
        duration: 0.12,
        status: 200,
        request_id: id,
        telemetry_nonce_hash: TELEMETRY_HASH,
        reverse_proxy_duration_ms: 110,
        upstream_attempt_duration_ms: 105,
        reverse_proxy_retries: 0,
        load_range: group.range,
        load_variant: group.variant,
      });
      nest.push(
        `[Nest] 7 - LOG [HttpRequest] {"requestId":"${id}","method":"GET","path":"/home/summary","statusCode":200,"durationMs":100}`,
      );
    }
  }
  return {
    caddy,
    nest,
    options: {
      telemetryHash: TELEMETRY_HASH,
      expectedCount: groups.length * perGroup,
      expectedPerGroup: perGroup,
    },
  };
}

function analyzeFixture(value) {
  return analyzeHomeIngressTelemetry(
    value.caddy.map((row) => JSON.stringify(row)).join("\n"),
    value.nest.join("\n"),
    value.options,
  );
}

test("passes only a complete correlated fixed-profile fixture", () => {
  const value = fixture();
  value.caddy.push({ ...value.caddy[0], telemetry_nonce_hash: OTHER_HASH });
  value.nest.push(
    `[HttpRequest] {"requestId":"${requestId(999)}","method":"GET","path":"/home/summary","statusCode":200,"durationMs":1}`,
  );

  const result = analyzeFixture(value);

  assert.equal(result.gate.passed, true);
  assert.deepEqual(result.gate.reasons, []);
  assert.equal(result.counts.correlated, 8);
  assert.equal(result.counts.caddyIgnoredOtherTelemetry, 1);
  assert.equal(result.counts.nestIgnoredOtherRequests, 1);
  assert.equal(result.overall.caddyTotalMs.p50, 120);
  assert.equal(result.overall.reverseProxyTotalMs.p50, 110);
  assert.equal(result.overall.upstreamAttemptMs.p50, 105);
  assert.equal(result.overall.nestMs.p50, 100);
  assert.equal(result.overall.caddyOutsideProxyMs.p50, 10);
  assert.equal(result.overall.reverseProxyMinusNestMs.p50, 10);
  assert.ok(!JSON.stringify(result).includes(requestId(1)));
  assert.deepEqual(Object.values(result.groupCounts), Array(8).fill(1));
});

test("fails closed for empty, malformed, partial, duplicate and wrong-status evidence", async (t) => {
  await t.test("empty", () => {
    const result = analyzeHomeIngressTelemetry("", "", fixture().options);
    assert.equal(result.gate.passed, false);
    assert.ok(
      result.gate.reasons.some((reason) => reason.startsWith("selectedCaddy=")),
    );
  });

  await t.test("malformed", () => {
    const value = fixture();
    const result = analyzeHomeIngressTelemetry(
      `${value.caddy.map((row) => JSON.stringify(row)).join("\n")}\nnot-json`,
      value.nest.join("\n"),
      value.options,
    );
    assert.equal(result.gate.passed, false);
    assert.ok(result.gate.reasons.includes("caddyRejected=1"));
  });

  await t.test("missing Nest peer", () => {
    const value = fixture();
    value.nest.pop();
    const result = analyzeFixture(value);
    assert.equal(result.gate.passed, false);
    assert.ok(result.gate.reasons.includes("missingNest=1"));
  });

  await t.test("duplicate request id", () => {
    const value = fixture();
    value.caddy.push({ ...value.caddy[0] });
    const result = analyzeFixture(value);
    assert.equal(result.gate.passed, false);
    assert.ok(result.gate.reasons.includes("caddyDuplicates=1"));
  });

  await t.test("non-200 and status mismatch", () => {
    const value = fixture();
    value.caddy[0].status = 401;
    const result = analyzeFixture(value);
    assert.equal(result.gate.passed, false);
    assert.ok(result.gate.reasons.includes("unexpectedStatus=1"));
    assert.ok(result.gate.reasons.includes("statusMismatch=1"));
  });

  await t.test("negative timing delta", () => {
    const value = fixture();
    value.caddy[0].reverse_proxy_duration_ms = 90;
    value.caddy[0].upstream_attempt_duration_ms = 80;
    const result = analyzeFixture(value);
    assert.equal(result.gate.passed, false);
    assert.ok(result.gate.reasons.includes("negativeDelta=1"));
    assert.equal(result.overall.reverseProxyMinusNestMs.min, -10);
  });

  await t.test("missing range/variant group", () => {
    const value = fixture();
    value.caddy.at(-1).load_range = "home_1d";
    const result = analyzeFixture(value);
    assert.equal(result.gate.passed, false);
    assert.ok(
      result.gate.reasons.includes("home_90d:daily_series=0, expected=1"),
    );
  });

  await t.test("nonzero proxy retry", () => {
    const value = fixture();
    value.caddy[0].reverse_proxy_retries = 1;
    const result = analyzeFixture(value);
    assert.equal(result.gate.passed, false);
    assert.ok(result.gate.reasons.includes("nonzeroRetries=1"));
  });
});

test("rejects unbounded Caddy fields and preserves Nest status", () => {
  const valid = fixture().caddy[0];
  const input = [
    JSON.stringify(valid),
    JSON.stringify({ ...valid, load_range: "home_365d" }),
    JSON.stringify({ ...valid, request_id: "caller-controlled-secret" }),
    JSON.stringify({ ...valid, reverse_proxy_duration_ms: null }),
    "not-json",
  ].join("\n");
  const parsed = parseCaddyTelemetry(input);
  assert.equal(parsed.rows.length, 1);
  assert.equal(parsed.rejected, 4);

  const nest = parseNestHttpRequests(
    `[HttpRequest] {"requestId":"${requestId(1)}","method":"GET","path":"/home/summary","statusCode":503,"durationMs":12}`,
  );
  assert.deepEqual(nest, {
    rows: [{ requestId: requestId(1), durationMs: 12, status: 503 }],
    rejected: 0,
  });
});

test("CLI writes diagnostic output but exits nonzero when the strict gate fails", () => {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "ops31-telemetry-"));
  try {
    const caddyPath = path.join(temporary, "caddy.ndjson");
    const nestPath = path.join(temporary, "nest.log");
    const outputPath = path.join(temporary, "summary.json");
    fs.writeFileSync(caddyPath, "");
    fs.writeFileSync(nestPath, "");
    const scriptPath = fileURLToPath(
      new URL("./analyze-home-ingress-telemetry.mjs", import.meta.url),
    );
    const child = spawnSync(
      process.execPath,
      [
        scriptPath,
        "--caddy",
        caddyPath,
        "--nest",
        nestPath,
        "--telemetry-hash",
        TELEMETRY_HASH,
        "--expected-count",
        "8",
        "--expected-per-group",
        "1",
        "--output",
        outputPath,
      ],
      { encoding: "utf8" },
    );
    assert.equal(child.status, 2);
    assert.equal(
      JSON.parse(fs.readFileSync(outputPath, "utf8")).gate.passed,
      false,
    );
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true });
  }
});
