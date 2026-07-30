import { check } from "k6";
import http from "k6/http";
import { Counter, Rate, Trend } from "k6/metrics";

import { API_ONLY_STAGING_BASE_URL } from "./opshub-staging-targets.mjs";

const APPROVAL = "OPSHUB_STAGING_API_HEALTH_GATE_APPROVED";
const TARGET_VUS = 100;
const TARGET_REQUESTS = 100;
const baseUrl = String(__ENV.BASE_URL || "").replace(/\/$/, "");
const runId = String(__ENV.TEST_RUN_ID || "");

if (baseUrl !== API_ONLY_STAGING_BASE_URL) {
  throw new Error("Health gate is restricted to the API-only staging hostname");
}
if (__ENV.LOAD_APPROVAL !== APPROVAL) {
  throw new Error(`LOAD_APPROVAL must equal ${APPROVAL}`);
}
if (!/^[a-z0-9](?:[a-z0-9-]{1,30}[a-z0-9])?$/.test(runId)) {
  throw new Error("TEST_RUN_ID is invalid");
}

const healthRequests = new Counter("opshub_api_health_requests");
const healthSuccess = new Rate("opshub_api_health_success");
const unexpectedStatus = new Counter("opshub_api_health_unexpected_status");
const healthDuration = new Trend("opshub_api_health_duration", true);

export const options = {
  discardResponseBodies: true,
  scenarios: {
    api_health_gate: {
      executor: "per-vu-iterations",
      exec: "healthGate",
      vus: TARGET_VUS,
      iterations: TARGET_REQUESTS / TARGET_VUS,
      maxDuration: "30s",
      gracefulStop: "0s",
    },
  },
  summaryTrendStats: ["count", "avg", "min", "p(50)", "p(95)", "p(99)", "max"],
  thresholds: {
    opshub_api_health_requests: [`count==${TARGET_REQUESTS}`],
    opshub_api_health_success: ["rate==1"],
    opshub_api_health_unexpected_status: ["count==0"],
    opshub_api_health_duration: ["p(95)<300", "p(99)<1000", "max<3000"],
    http_req_failed: ["rate==0"],
    http_reqs: [`count==${TARGET_REQUESTS}`],
    checks: ["rate==1"],
  },
};

export function healthGate() {
  const response = http.get(`${baseUrl}/health`, {
    headers: {
      "X-OpsHub-Load-Test": runId,
    },
    tags: {
      endpoint: "api_health",
    },
    timeout: "10s",
    responseCallback: http.expectedStatuses(200),
    responseType: "text",
  });
  let body = null;
  try {
    body = response.json();
  } catch (_) {
    body = null;
  }
  const succeeded =
    response.status === 200 &&
    body?.status === "ok" &&
    body?.service === "backend-nest";

  healthRequests.add(1);
  healthSuccess.add(succeeded);
  healthDuration.add(response.timings.duration);
  if (!succeeded) unexpectedStatus.add(1);

  check(response, {
    "API-only staging health returned the Nest contract": () => succeeded,
  });
}
