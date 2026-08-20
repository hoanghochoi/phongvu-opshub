export const API_ONLY_STAGING_BASE_URL =
  "https://api-staging.phongvu.work/v1";

export const HOME_PHASE1_STAGING_BASE_URLS = Object.freeze([
  API_ONLY_STAGING_BASE_URL,
]);

export function isApprovedHomePhase1StagingBaseUrl(value) {
  return HOME_PHASE1_STAGING_BASE_URLS.includes(value);
}
