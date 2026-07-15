# CLIENT-LOGS-001 Daily Activity Log Upload

## Goal

Help operators diagnose client-side failures such as missing payment audio by
receiving one sanitized activity summary from each authenticated client per day.

## Contract

- After an authenticated session is restored, created, or assigned a store, the
  client checks whether yesterday's activity summary has already been uploaded.
- The client uploads at most one summary per local day and retries on the next
  app start if the previous upload failed.
- The payload is a summary, not the raw `opshub.log` file. It includes counts by
  level/source/message, first and last timestamps, app/platform metadata, and a
  capped list of notable warn/error samples.
- Sanitization redacts tokens, passwords, secrets, authorization values, email
  addresses, and local Windows user profile names before upload.
- The upload uses the existing authenticated `/app-logs` pipeline so backend log
  retention and store authorization remain unchanged.
- Self-update network, HTTP, timeout and incomplete-download failures remain
  local warnings and are eligible for this daily summary. Contract/integrity,
  native-install and unexpected update failures use the existing immediate
  authenticated error-upload path instead. Both paths keep only stable
  code/stage, duration, platform/build, sanitized host and byte counts; they do
  not include URL query, token, payload or local file path.

## Validation

- Unit test the daily summary filter and sanitizer.
- Run Flutter static analysis and tests.
- Verify no raw log file upload or secret-bearing payload is introduced.
- Verify self-update warning classes enter the daily summary while critical
  classes follow the immediate authenticated upload policy exactly once.
