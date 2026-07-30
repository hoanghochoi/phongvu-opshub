export const API_ONLY_STAGING_BASE_URL =
  "https://api-opshub-staging.hoanghochoi.com/api";

export const HOME_PHASE1_STAGING_BASE_URLS = Object.freeze([
  "https://opshub-staging.hoanghochoi.com/api",
  API_ONLY_STAGING_BASE_URL,
]);

export function isApprovedHomePhase1StagingBaseUrl(value) {
  return HOME_PHASE1_STAGING_BASE_URLS.includes(value);
}
