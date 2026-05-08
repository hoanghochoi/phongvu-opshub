# FIFO Contract

## Intent

Staff use OpsHub to check FIFO status, sort FIFO-related SKUs, and review FIFO
history where permitted.

## Current Shape

- Flutter screens live under `lib/features/fifo/`, `lib/features/sort/`, and
  related chat/sort widgets.
- NestJS owns inventory, sort, and FIFO log modules.
- Admin FIFO history is exposed through the app and backend service.

## Contract Notes

- FIFO behavior is operations-critical because wrong results can affect store or
  warehouse handling.
- Changes to sort rules, inventory freshness, or history visibility require
  story-level validation.
- API response changes must be coordinated with Flutter repositories/models.

## Expected Proof

- Unit tests for sort/FIFO rules.
- NestJS service tests for inventory, sort, and FIFO log behavior.
- Flutter tests for validators and user-visible states where practical.
- Manual app smoke for scanner-driven or device-specific flows.
