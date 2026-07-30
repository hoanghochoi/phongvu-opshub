import assert from "node:assert/strict";
import test from "node:test";

import {
  API_ONLY_STAGING_BASE_URL,
  HOME_PHASE1_STAGING_BASE_URLS,
  isApprovedHomePhase1StagingBaseUrl,
} from "./opshub-staging-targets.mjs";

test("allows only the existing and API-only staging Home proof targets", () => {
  assert.deepEqual(HOME_PHASE1_STAGING_BASE_URLS, [
    "https://opshub-staging.hoanghochoi.com/api",
    API_ONLY_STAGING_BASE_URL,
  ]);
  assert.equal(
    API_ONLY_STAGING_BASE_URL,
    "https://api-opshub-staging.hoanghochoi.com/api",
  );
  assert.equal(
    isApprovedHomePhase1StagingBaseUrl(
      "https://opshub-staging.hoanghochoi.com/api",
    ),
    true,
  );
  assert.equal(
    isApprovedHomePhase1StagingBaseUrl(
      "https://api-opshub-staging.hoanghochoi.com/api",
    ),
    true,
  );
});

test("rejects production, suffix confusion and non-API targets", () => {
  for (const value of [
    "https://opshub.hoanghochoi.com/api",
    "https://api-opshub-staging.hoanghochoi.com.evil.example/api",
    "https://api-opshub-staging.hoanghochoi.com",
    "http://api-opshub-staging.hoanghochoi.com/api",
  ]) {
    assert.equal(isApprovedHomePhase1StagingBaseUrl(value), false, value);
  }
});
