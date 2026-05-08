# Sort Contract

## Intent

The sort workflow groups or organizes SKU information so staff can act on it
quickly during operations.

## Current Shape

- Flutter sort UI lives under `lib/features/sort/`.
- Sort requests and repository code live under `lib/features/sort/data/`.
- NestJS sort API behavior lives under `backend-nest/src/sort/`.

## Contract Notes

- SKU grouping rules are product behavior. Do not hide rule changes inside UI
  refactors.
- If API request/response shape changes, update Flutter models and backend tests
  in the same story.

## Expected Proof

- Focused unit tests for grouping or sorting rules.
- NestJS sort service/controller tests for API behavior.
- Flutter widget or provider tests when user-visible states change.
