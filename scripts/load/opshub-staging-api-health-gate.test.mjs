import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const source = readFileSync(
  path.join(
    path.dirname(fileURLToPath(import.meta.url)),
    "opshub-staging-api-health-gate.js",
  ),
  "utf8",
);

test("health gate is a fixed 100-request concurrent API-only profile", () => {
  assert.match(source, /const TARGET_VUS = 100;/);
  assert.match(source, /const TARGET_REQUESTS = 100;/);
  assert.match(source, /executor: "per-vu-iterations"/);
  assert.match(source, /baseUrl !== API_ONLY_STAGING_BASE_URL/);
  assert.match(source, /OPSHUB_STAGING_API_HEALTH_GATE_APPROVED/);
});

test("health gate requires an exact Nest response and the 300 ms p95", () => {
  assert.match(source, /body\?\.status === "ok"/);
  assert.match(source, /body\?\.service === "backend-nest"/);
  assert.match(source, /opshub_api_health_success: \["rate==1"\]/);
  assert.match(source, /opshub_api_health_unexpected_status: \["count==0"\]/);
  assert.match(source, /"p\(95\)<300"/);
});
