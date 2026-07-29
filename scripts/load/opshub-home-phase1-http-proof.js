import http from "k6/http";
import { check } from "k6";
import exec from "k6/execution";
import { SharedArray } from "k6/data";
import { Counter, Rate, Trend } from "k6/metrics";
import {
  dailyHomeBodyMatchesContract,
  homeAggregateBodiesHaveParity,
  legacyHomeBodyMatchesContract,
} from "./opshub-home-phase1-contract.mjs";

const STAGING_BASE_URL = "https://opshub-staging.hoanghochoi.com/api";
const STAGING_APPROVAL = "OPSHUB_STAGING_HOME_PHASE1_HTTP_APPROVED";
const LOCAL_APPROVAL = "OPSHUB_LOCAL_HOME_PHASE1_HTTP_APPROVED";
const TARGET_VUS = 250;
const TARGET_REQUESTS = 2_000;
const TOKENS_FILE = String(__ENV.TOKENS_FILE || "");
const manifest = TOKENS_FILE ? JSON.parse(open(TOKENS_FILE)) : null;
const users = new SharedArray("phase 1 Home proof users", () =>
  Array.isArray(manifest?.users) ? manifest.users : [],
);
const baseUrl = String(__ENV.BASE_URL || "").replace(/\/$/, "");
const runId = String(__ENV.TEST_RUN_ID || "");
const configuredVus = Number(__ENV.TARGET_VUS || TARGET_VUS);
const configuredRequests = Number(__ENV.TARGET_REQUESTS || TARGET_REQUESTS);
const isStaging = baseUrl === STAGING_BASE_URL;
const isLocal =
  /^https?:\/\/(?:localhost|127\.0\.0\.1|\[::1\])(?::\d+)?\/api$/.test(baseUrl);
const requiredApproval = isStaging ? STAGING_APPROVAL : LOCAL_APPROVAL;

if (!isStaging && !isLocal) {
  throw new Error(
    "Phase 1 HTTP proof is restricted to the approved staging host or loopback",
  );
}
if (__ENV.LOAD_APPROVAL !== requiredApproval) {
  throw new Error(`LOAD_APPROVAL must equal ${requiredApproval}`);
}
if (configuredVus !== TARGET_VUS || configuredRequests !== TARGET_REQUESTS) {
  throw new Error(
    `This proof is fixed at ${TARGET_VUS} concurrent VUs and ${TARGET_REQUESTS} requests`,
  );
}
if (TARGET_REQUESTS % 2 !== 0) {
  throw new Error("TARGET_REQUESTS must be even for paired Home proof");
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
const minimumUsers = isStaging ? 60 : 1;
if (
  users.length < minimumUsers ||
  userTokens.some((token) => !token) ||
  new Set(userTokens).size !== users.length
) {
  throw new Error(
    `At least ${minimumUsers} unique synthetic user tokens are required`,
  );
}

const activeVus = new Counter("opshub_home_active_vus");
const homeRequests = new Counter("opshub_home_requests");
const homeSuccess = new Rate("opshub_home_success");
const homeErrors = new Rate("opshub_home_errors");
const homeContractValid = new Rate("opshub_home_contract_valid");
const unexpected429 = new Counter("opshub_home_unexpected_429");
const transportOr5xx = new Counter("opshub_home_transport_or_5xx");
const homeDuration = new Trend("opshub_home_duration", true);
let vuRecorded = false;

const rangeThresholds = {};
for (const range of ["home_1d", "home_7d", "home_30d", "home_90d"]) {
  rangeThresholds[`opshub_home_duration{range:${range}}`] = [
    "p(50)<=250",
    "p(95)<=500",
    "p(99)<=1000",
    "max<=3000",
  ];
}

export const options = {
  discardResponseBodies: true,
  scenarios: {
    home_250_concurrent_2000_total: {
      executor: "shared-iterations",
      exec: "homeProof",
      vus: TARGET_VUS,
      iterations: TARGET_REQUESTS / 2,
      maxDuration: "3m",
      gracefulStop: "0s",
    },
  },
  summaryTrendStats: [
    "count",
    "avg",
    "min",
    "p(50)",
    "max",
    "p(90)",
    "p(95)",
    "p(99)",
  ],
  thresholds: {
    opshub_home_active_vus: [`count==${TARGET_VUS}`],
    opshub_home_requests: [`count==${TARGET_REQUESTS}`],
    opshub_home_success: ["rate>0.999"],
    opshub_home_errors: ["rate<0.001"],
    opshub_home_contract_valid: ["rate==1"],
    opshub_home_unexpected_429: ["count==0"],
    opshub_home_transport_or_5xx: ["count==0"],
    opshub_home_duration: [
      "p(50)<=250",
      "p(95)<=500",
      "p(99)<=1000",
      "max<=3000",
    ],
    http_reqs: [`count==${TARGET_REQUESTS}`],
    checks: ["rate>0.999"],
    ...rangeThresholds,
  },
};

function priorDate(endDate, days) {
  const date = new Date(`${endDate}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() - days);
  return date.toISOString().slice(0, 10);
}

function routeForIteration() {
  const ranges = [1, 7, 30, 90];
  const days = ranges[exec.scenario.iterationInTest % ranges.length];
  const endDate = manifest.homeEndDate;
  const startDate = priorDate(endDate, days - 1);
  return {
    name: `home_${days}d`,
    days,
    startDate,
    endDate,
    legacyPath: `/home/summary?startDate=${startDate}&endDate=${endDate}`,
    dailyPath: `/home/summary?startDate=${startDate}&endDate=${endDate}&includeDailySeries=true`,
  };
}

function responseBody(response) {
  if (response.status !== 200) return null;
  try {
    return response.json();
  } catch (_) {
    return null;
  }
}

function requestHome(record, route, variant) {
  const path = variant === "legacy" ? route.legacyPath : route.dailyPath;
  return http.get(`${baseUrl}${path}`, {
    headers: {
      Authorization: `Bearer ${record.token}`,
      "X-OpsHub-Load-Test": runId,
    },
    tags: {
      endpoint: "home_summary",
      range: route.name,
      variant,
    },
    timeout: "10s",
    responseCallback: http.expectedStatuses(200),
    responseType: "text",
  });
}

function recordHomeResult(response, route, variant, contractValid) {
  const succeeded = response.status === 200;
  homeRequests.add(1);
  homeSuccess.add(succeeded);
  homeErrors.add(!succeeded);
  homeContractValid.add(contractValid);
  homeDuration.add(response.timings.duration, {
    range: route.name,
    variant,
  });
  if (response.status === 429) unexpected429.add(1);
  if (response.status === 0 || response.status >= 500) transportOr5xx.add(1);
}

export function homeProof() {
  if (!vuRecorded) {
    activeVus.add(1);
    vuRecorded = true;
  }
  const route = routeForIteration();
  const record = users[exec.scenario.iterationInTest % users.length];
  const legacyResponse = requestHome(record, route, "legacy");
  const dailyResponse = requestHome(record, route, "daily_series");
  const legacyBody = responseBody(legacyResponse);
  const dailyBody = responseBody(dailyResponse);
  const legacyValid = legacyHomeBodyMatchesContract(legacyBody);
  const dailyValid = dailyHomeBodyMatchesContract(dailyBody, route);
  const aggregateParity = homeAggregateBodiesHaveParity(legacyBody, dailyBody);
  const pairValid = legacyValid && dailyValid && aggregateParity;

  recordHomeResult(legacyResponse, route, "legacy", pairValid);
  recordHomeResult(dailyResponse, route, "daily_series", pairValid);
  check(
    { legacyResponse, dailyResponse },
    {
      "Home summary pair returned 200": ({ legacyResponse, dailyResponse }) =>
        legacyResponse.status === 200 && dailyResponse.status === 200,
      "Home summary pair matched legacy and daily contracts": () =>
        legacyValid && dailyValid,
      "Home summary aggregate parity matched across variants": () =>
        aggregateParity,
    },
  );
}
