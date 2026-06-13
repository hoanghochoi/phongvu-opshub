# Feedback Contract

## Intent

Staff can submit feedback from the app so operations issues and improvement
ideas reach the backend.

## Current Shape

- Flutter feedback submission UI lives under `lib/features/feedback/`.
- Flutter feedback administration UI lives under `lib/features/admin/` and is
  visible only to `SUPER_ADMIN`.
- NestJS feedback API lives under `backend-nest/src/feedback/`.

## Contract Notes

- Feedback payload validation should happen at API boundaries.
- Submitting feedback requires the `FEEDBACK` feature. Listing all feedback uses
  `/feedback/admin`, requires `ADMIN_FEEDBACK`, and the service still enforces
  `SUPER_ADMIN` even if a non-super user gets that feature by mistake.
- The admin feedback list should render uploaded feedback image URLs as inline
  thumbnails while keeping non-displayable image text visible as fallback.
- If feedback becomes user-identifying or sensitive, update auth and privacy
  expectations before implementation.

## Expected Proof

- NestJS feedback service/controller tests.
- Flutter validation or UI-state tests when the submission flow changes.
- Flutter admin feedback parser tests when display parsing changes.
- Manual smoke for successful and failed submissions when API behavior changes.
