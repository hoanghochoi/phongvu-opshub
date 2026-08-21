import assert from "node:assert/strict";
import test from "node:test";

import {
  API_ONLY_STAGING_BASE_URL,
  HOME_PHASE1_STAGING_BASE_URLS,
  isApprovedHomePhase1StagingBaseUrl,
} from "./opshub-staging-targets.mjs";

test("allows only the staging API Home proof target", () => {
  assert.deepEqual(HOME_PHASE1_STAGING_BASE_URLS, [
    API_ONLY_STAGING_BASE_URL,
  ]);
  assert.equal(
    API_ONLY_STAGING_BASE_URL,
    "https://api-staging.phongvu.work/v1",
  );
  assert.equal(
    isApprovedHomePhase1StagingBaseUrl(
      "https://api-staging.phongvu.work/v1",
    ),
    true,
  );
});

test("rejects production, suffix confusion and non-API targets", () => {
  for (const value of [
    "https://api.phongvu.work/v1",
    "https://api-staging.phongvu.work.evil.example/v1",
    "https://api-staging.phongvu.work",
    "http://api-staging.phongvu.work/v1",
  ]) {
    assert.equal(isApprovedHomePhase1StagingBaseUrl(value), false, value);
  }
});
