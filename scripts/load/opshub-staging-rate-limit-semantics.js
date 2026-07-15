import http from "k6/http";
import { check, sleep } from "k6";
import { SharedArray } from "k6/data";
import { Counter } from "k6/metrics";

const REQUIRED_BASE_URL = "https://opshub-staging.hoanghochoi.com/api";
const REQUIRED_APPROVAL = "OPSHUB_STAGING_RATE_LIMIT_SEMANTICS_APPROVED";
const TOKENS_FILE = String(__ENV.TOKENS_FILE || "");
const manifest = TOKENS_FILE ? JSON.parse(open(TOKENS_FILE)) : null;
const users = new SharedArray(
  "staging semantics users",
  () => manifest?.users || [],
);
const baseUrl = String(__ENV.BASE_URL || "").replace(/\/$/, "");
const runId = String(__ENV.TEST_RUN_ID || "");

if (__ENV.LOAD_APPROVAL !== REQUIRED_APPROVAL) {
  throw new Error(`LOAD_APPROVAL must equal ${REQUIRED_APPROVAL}`);
}
if (baseUrl !== REQUIRED_BASE_URL) {
  throw new Error(
    "This semantics proof is hard-gated to the OpsHub staging API",
  );
}
if (!manifest || manifest.schemaVersion !== 1 || manifest.runId !== runId) {
  throw new Error("Token manifest schema/run id does not match TEST_RUN_ID");
}
if (!/^[a-z0-9](?:[a-z0-9-]{1,30}[a-z0-9])?$/.test(runId)) {
  throw new Error("TEST_RUN_ID is invalid");
}
const userTokens = users.map((item) => String(item?.token || "").trim());
if (
  users.length !== 60 ||
  userTokens.some((token) => !token) ||
  new Set(userTokens).size !== 60
) {
  throw new Error(
    "The verified manifest must contain exactly 60 unique user tokens",
  );
}

const targetAccepted = new Counter("opshub_target_accepted");
const targetThrottled = new Counter("opshub_target_throttled");
const missingRetryAfter = new Counter("opshub_missing_retry_after");
const controlAccepted = new Counter("opshub_control_accepted");
const controlFailure = new Counter("opshub_control_failure");
const targetUnexpectedStatus = new Counter("opshub_target_unexpected_status");
const targetTransportFailure = new Counter("opshub_target_transport_failure");
const targetOrderingFailure = new Counter("opshub_target_ordering_failure");
let targetSawAccepted = false;

export const options = {
  discardResponseBodies: true,
  scenarios: {
    exceed_one_principal: {
      executor: "constant-arrival-rate",
      exec: "exceedOnePrincipal",
      rate: 4,
      timeUnit: "1s",
      duration: "45s",
      preAllocatedVUs: 1,
      maxVUs: 1,
    },
    same_ip_control: {
      executor: "constant-vus",
      exec: "sameIpControl",
      vus: 1,
      duration: "45s",
    },
  },
  thresholds: {
    opshub_target_accepted: ["count>0"],
    opshub_target_throttled: ["count>0"],
    opshub_missing_retry_after: ["count==0"],
    opshub_control_accepted: ["count>0"],
    opshub_control_failure: ["count==0"],
    opshub_target_unexpected_status: ["count==0"],
    opshub_target_transport_failure: ["count==0"],
    opshub_target_ordering_failure: ["count==0"],
    checks: ["rate==1"],
    http_req_failed: ["rate==0"],
    "dropped_iterations{scenario:exceed_one_principal}": ["count==0"],
  },
};

function headers(record) {
  return {
    Authorization: `Bearer ${record.token}`,
    "X-OpsHub-Load-Test": runId,
  };
}

export function exceedOnePrincipal() {
  const response = http.get(`${baseUrl}/auth/me`, {
    headers: headers(users[0]),
    tags: { endpoint: "rate_semantics_target" },
    timeout: "10s",
    responseCallback: http.expectedStatuses(200, 429),
  });
  const expectedStatus = response.status === 200 || response.status === 429;
  const transportFailure = response.status === 0 || response.status >= 500;
  if (!expectedStatus) targetUnexpectedStatus.add(1);
  if (transportFailure) targetTransportFailure.add(1);
  if (response.status === 200) {
    targetSawAccepted = true;
    targetAccepted.add(1);
  }
  if (response.status === 429) {
    if (!targetSawAccepted) targetOrderingFailure.add(1);
    targetThrottled.add(1);
    const retryAfter = String(response.headers["Retry-After"] || "").trim();
    if (!/^\d+$/.test(retryAfter) || Number(retryAfter) < 1) {
      missingRetryAfter.add(1);
    }
  }
  check(response, {
    "target is accepted or intentionally throttled": () => expectedStatus,
    "target has no timeout or server error": () => !transportFailure,
  });
}

export function sameIpControl() {
  const response = http.get(`${baseUrl}/auth/me`, {
    headers: headers(users[1]),
    tags: { endpoint: "rate_semantics_control" },
    timeout: "10s",
    responseCallback: http.expectedStatuses(200),
  });
  if (response.status === 200) controlAccepted.add(1);
  else controlFailure.add(1);
  check(response, {
    "control principal stays available": (res) => res.status === 200,
  });
  sleep(1);
}
