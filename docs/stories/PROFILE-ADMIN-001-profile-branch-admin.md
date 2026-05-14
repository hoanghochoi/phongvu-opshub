# PROFILE-ADMIN-001 Profile, Branch Selection, And User Admin

## Scope

Add personal profile management, one-time branch selection on first login, store
payment account import from CSV, and user administration for privileged roles.

## Acceptance Criteria

- `data/store_account.csv` is present in the repo.
- Backend can import store account rows into `Store`.
- First-login users without a branch must choose one and see a lock warning.
- Users can edit profile display names and upload an avatar.
- `ADMIN` and `SUPER_ADMIN` can manage users from the app.
- User self-service branch changes are rejected after the first selection.
- VietQR uses the selected store's configured transfer account when available.

## Validation

- Backend build and Jest tests.
- Flutter analyze and tests.
- Local DB migration and store-account import smoke.
