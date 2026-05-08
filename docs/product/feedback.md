# Feedback Contract

## Intent

Staff can submit feedback from the app so operations issues and improvement
ideas reach the backend.

## Current Shape

- Flutter feedback UI lives under `lib/features/feedback/`.
- NestJS feedback API lives under `backend-nest/src/feedback/`.

## Contract Notes

- Feedback payload validation should happen at API boundaries.
- If feedback becomes user-identifying or sensitive, update auth and privacy
  expectations before implementation.

## Expected Proof

- NestJS feedback service/controller tests.
- Flutter validation or UI-state tests when the submission flow changes.
- Manual smoke for successful and failed submissions when API behavior changes.
