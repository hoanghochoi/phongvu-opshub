import http from "k6/http";
import ws from "k6/ws";
import { check, sleep } from "k6";
import exec from "k6/execution";
import { SharedArray } from "k6/data";
import { Counter, Rate, Trend } from "k6/metrics";

const REQUIRED_BASE_URL = "https://opshub-staging.hoanghochoi.com/api";
const REQUIRED_WS_URL = "wss://opshub-staging.hoanghochoi.com/ws/v2";
const REQUIRED_APPROVAL = "OPSHUB_STAGING_HOME_100QPS_APPROVED";
const TOKENS_FILE = String(__ENV.TOKENS_FILE || "");
const manifest = TOKENS_FILE ? JSON.parse(open(TOKENS_FILE)) : null;
const users = new SharedArray(
  "staging load users",
  () => manifest?.users || [],
);
const baseUrl = String(__ENV.BASE_URL || "").replace(/\/$/, "");
const wsUrl = String(__ENV.WS_URL || "").replace(/\/$/, "");
const runId = String(__ENV.TEST_RUN_ID || "");
const targetRps = Number(__ENV.TARGET_RPS || 100);
const targetSockets = Number(__ENV.TARGET_SOCKETS || 60);
const HTTP_TIMEOUT = "10s";
const WS_SESSION_MS = 25 * 60 * 1000;
const WS_MIN_HOLD_MS = WS_SESSION_MS - 5_000;
// Reserve the observed ramp concurrency up front. Dynamic VU allocation can
// lag behind multi-second network outliers and otherwise report generator-side
// dropped iterations even when the API accepts every dispatched request.
const RAMP_PREALLOCATED_VUS = 300;

if (__ENV.LOAD_APPROVAL !== REQUIRED_APPROVAL) {
  throw new Error(`LOAD_APPROVAL must equal ${REQUIRED_APPROVAL}`);
}
if (baseUrl !== REQUIRED_BASE_URL || wsUrl !== REQUIRED_WS_URL) {
  throw new Error(
    "This profile is hard-gated to the OpsHub staging API and /ws/v2",
  );
}
if (!manifest || manifest.schemaVersion !== 1 || manifest.runId !== runId) {
  throw new Error("Token manifest schema/run id does not match TEST_RUN_ID");
}
if (!/^[a-z0-9](?:[a-z0-9-]{1,30}[a-z0-9])?$/.test(runId)) {
  throw new Error("TEST_RUN_ID is invalid");
}
if (!/^\d{4}-\d{2}-\d{2}$/.test(String(manifest.homeEndDate || ""))) {
  throw new Error("Token manifest has no verified COMPLETE Home end date");
}
const userTokens = users.map((item) => String(item?.token || "").trim());
if (
  users.length !== 60 ||
  userTokens.some((token) => !token) ||
  new Set(userTokens).size !== 60
) {
  throw new Error("Exactly 60 unique synthetic user tokens are required");
}
if (targetRps !== 100 || targetSockets !== 60) {
  throw new Error(
    "This release-proof profile is fixed at 100 QPS and 60 /ws/v2 sockets",
  );
}
if (
  (__ENV.PUBLIC_WS_ENABLED || "0") !== "0" ||
  (__ENV.LEGACY_WS_ENABLED || "0") !== "0"
) {
  throw new Error("Public and legacy sockets must remain disabled");
}

const httpSuccess = new Rate("opshub_http_success");
const http5xxOrTimeout = new Rate("opshub_http_5xx_or_timeout");
const unexpected429 = new Counter("opshub_unexpected_429");
const wsTicketAttempts = new Counter("opshub_ws_ticket_attempts");
const wsConnectionAttempts = new Counter("opshub_ws_connection_attempts");
const wsConnectSuccess = new Rate("opshub_ws_connect_success");
const wsSessionHeld = new Rate("opshub_ws_session_held");
const wsInvalidEnvelope = new Counter("opshub_ws_invalid_envelope");
const homeSummaryDuration = new Trend("opshub_home_summary_duration", true);

export const options = {
  discardResponseBodies: true,
  scenarios: {
    capacity_smoke: {
      executor: "ramping-vus",
      exec: "capacitySmoke",
      startVUs: 1,
      stages: [{ target: 5, duration: "30s" }],
      gracefulRampDown: "0s",
      gracefulStop: "0s",
    },
    capacity_25_qps: {
      executor: "constant-arrival-rate",
      exec: "capacityHttp",
      startTime: "30s",
      rate: 25,
      timeUnit: "1s",
      duration: "2m",
      preAllocatedVUs: 50,
      maxVUs: 300,
      gracefulStop: "30s",
    },
    capacity_50_qps: {
      executor: "constant-arrival-rate",
      exec: "capacityHttp",
      startTime: "2m30s",
      rate: 50,
      timeUnit: "1s",
      duration: "3m",
      preAllocatedVUs: 100,
      maxVUs: 500,
      gracefulStop: "30s",
    },
    capacity_ramp_to_100_qps: {
      executor: "ramping-arrival-rate",
      exec: "capacityHttp",
      startTime: "5m30s",
      startRate: 50,
      timeUnit: "1s",
      preAllocatedVUs: RAMP_PREALLOCATED_VUS,
      maxVUs: 1000,
      stages: [{ target: 100, duration: "3m" }],
      gracefulStop: "30s",
    },
    capacity_100_qps_hold: {
      executor: "constant-arrival-rate",
      exec: "capacityHttp",
      startTime: "8m30s",
      rate: 100,
      timeUnit: "1s",
      duration: "15m",
      preAllocatedVUs: 200,
      maxVUs: 1000,
      gracefulStop: "30s",
    },
    capacity_ramp_down: {
      executor: "ramping-arrival-rate",
      exec: "capacityHttp",
      startTime: "23m30s",
      startRate: 100,
      timeUnit: "1s",
      preAllocatedVUs: 100,
      maxVUs: 1000,
      stages: [{ target: 0, duration: "2m" }],
      gracefulStop: "30s",
    },
    realtime_v2: {
      executor: "per-vu-iterations",
      exec: "realtimeV2",
      startTime: "30s",
      vus: 60,
      iterations: 1,
      maxDuration: "25m30s",
      gracefulStop: "0s",
    },
  },
  summaryTrendStats: ["avg", "min", "med", "max", "p(90)", "p(95)", "p(99)"],
  thresholds: {
    opshub_http_success: ["rate>=0.999"],
    opshub_http_5xx_or_timeout: ["rate<=0.001"],
    opshub_unexpected_429: ["count==0"],
    http_req_duration: ["p(95)<=500", "p(99)<=1000"],
    opshub_home_summary_duration: ["p(95)<=500", "p(99)<=1000"],
    "opshub_home_summary_duration{range:home_1d}": [
      "p(95)<=500",
      "p(99)<=1000",
    ],
    "opshub_home_summary_duration{range:home_7d}": [
      "p(95)<=500",
      "p(99)<=1000",
    ],
    "opshub_home_summary_duration{range:home_30d}": [
      "p(95)<=500",
      "p(99)<=1000",
    ],
    "opshub_home_summary_duration{range:home_90d}": [
      "p(95)<=500",
      "p(99)<=1000",
    ],
    "opshub_home_summary_duration{phase:capacity_100_qps_hold}": [
      "p(95)<=500",
      "p(99)<=1000",
    ],
    "opshub_home_summary_duration{phase:capacity_100_qps_hold,range:home_1d}": [
      "p(95)<=500",
      "p(99)<=1000",
    ],
    "opshub_home_summary_duration{phase:capacity_100_qps_hold,range:home_7d}": [
      "p(95)<=500",
      "p(99)<=1000",
    ],
    "opshub_home_summary_duration{phase:capacity_100_qps_hold,range:home_30d}":
      ["p(95)<=500", "p(99)<=1000"],
    "opshub_home_summary_duration{phase:capacity_100_qps_hold,range:home_90d}":
      ["p(95)<=500", "p(99)<=1000"],
    "dropped_iterations{scenario:capacity_25_qps}": ["count==0"],
    "dropped_iterations{scenario:capacity_50_qps}": ["count==0"],
    "dropped_iterations{scenario:capacity_ramp_to_100_qps}": ["count==0"],
    "dropped_iterations{scenario:capacity_100_qps_hold}": ["count==0"],
    "dropped_iterations{scenario:capacity_ramp_down}": ["count==0"],
    opshub_ws_ticket_attempts: ["count==60"],
    opshub_ws_connection_attempts: ["count==60"],
    opshub_ws_connect_success: ["rate>=0.999"],
    opshub_ws_session_held: ["rate>=0.999"],
    opshub_ws_invalid_envelope: ["count==0"],
  },
};

function recordForIteration() {
  return users[exec.scenario.iterationInTest % users.length];
}

function authHeaders(token) {
  return {
    Authorization: `Bearer ${token}`,
    "X-OpsHub-Load-Test": runId,
  };
}

function priorDate(endDate, days) {
  const date = new Date(`${endDate}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() - days);
  return date.toISOString().slice(0, 10);
}

function homePath(days) {
  const endDate = manifest.homeEndDate;
  const startDate = priorDate(endDate, days - 1);
  return `/home/summary?startDate=${startDate}&endDate=${endDate}`;
}

function routeForIteration() {
  const slot = exec.scenario.iterationInTest % 100;
  if (slot < 35) return { name: "home_1d", path: homePath(1) };
  if (slot < 55) return { name: "home_7d", path: homePath(7) };
  if (slot < 65) return { name: "home_30d", path: homePath(30) };
  if (slot < 70) return { name: "home_90d", path: homePath(90) };
  if (slot < 80) return { name: "home_scopes", path: "/home/summary/scopes" };
  if (slot < 90) return { name: "auth_bootstrap", path: "/auth/bootstrap" };
  return { name: "auth_me", path: "/auth/me" };
}

export function capacityHttp() {
  const record = recordForIteration();
  const route = routeForIteration();
  const response = http.get(`${baseUrl}${route.path}`, {
    headers: authHeaders(record.token),
    tags: { endpoint: route.name },
    timeout: HTTP_TIMEOUT,
    responseCallback: http.expectedStatuses(200),
  });
  const succeeded = response.status === 200;
  const transportFailure = response.status === 0 || response.status >= 500;
  if (
    route.name === "home_1d" ||
    route.name === "home_7d" ||
    route.name === "home_30d" ||
    route.name === "home_90d"
  ) {
    homeSummaryDuration.add(response.timings.duration, {
      phase: exec.scenario.name,
      range: route.name,
    });
  }
  httpSuccess.add(succeeded);
  http5xxOrTimeout.add(transportFailure);
  if (response.status === 429) unexpected429.add(1);
  check(response, { "capacity GET returned 200": () => succeeded });
}

export function capacitySmoke() {
  capacityHttp();
  sleep(1);
}

export function realtimeV2() {
  const record = recordForIteration();
  wsTicketAttempts.add(1);
  const ticketResponse = http.post(
    `${baseUrl}/auth/realtime-ticket`,
    JSON.stringify(record.storeCode ? { storeCode: record.storeCode } : {}),
    {
      headers: {
        ...authHeaders(record.token),
        "Content-Type": "application/json",
      },
      tags: { endpoint: "auth_realtime_ticket" },
      timeout: HTTP_TIMEOUT,
      responseCallback: http.expectedStatuses(200, 201),
      responseType: "text",
    },
  );
  if (ticketResponse.status === 429) unexpected429.add(1);
  const ticketSucceeded =
    ticketResponse.status === 200 || ticketResponse.status === 201;
  const ticketTransportFailure =
    ticketResponse.status === 0 || ticketResponse.status >= 500;
  httpSuccess.add(ticketSucceeded);
  http5xxOrTimeout.add(ticketTransportFailure);
  if (!ticketSucceeded) {
    wsConnectSuccess.add(false);
    wsSessionHeld.add(false);
    return;
  }
  let ticket = "";
  try {
    ticket = String(ticketResponse.json("ticket") || "");
  } catch (_) {
    wsConnectSuccess.add(false);
    wsSessionHeld.add(false);
    return;
  }
  if (!ticket) {
    wsConnectSuccess.add(false);
    wsSessionHeld.add(false);
    return;
  }

  wsConnectionAttempts.add(1);
  const connectedAt = Date.now();
  const response = ws.connect(
    `${wsUrl}?ticket=${encodeURIComponent(ticket)}`,
    {
      headers: { Origin: "https://opshub-staging.hoanghochoi.com" },
      tags: { endpoint: "ws_v2" },
    },
    (socket) => {
      socket.on("message", (message) => {
        try {
          const envelope = JSON.parse(message);
          if (
            envelope.v !== 2 ||
            typeof envelope.kind !== "string" ||
            typeof envelope.topic !== "string"
          ) {
            wsInvalidEnvelope.add(1);
          }
        } catch (_) {
          wsInvalidEnvelope.add(1);
        }
      });
      socket.setTimeout(() => socket.close(), WS_SESSION_MS);
    },
  );
  const connected = Boolean(response && response.status === 101);
  const heldForMs = Date.now() - connectedAt;
  wsConnectSuccess.add(connected);
  wsSessionHeld.add(connected && heldForMs >= WS_MIN_HOLD_MS);
  check(response, { "/ws/v2 upgraded": () => connected });
}
