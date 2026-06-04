# PROFILE-ADMIN-001 Profile, Branch Selection, And User Admin

## Scope

Add personal profile management, one-time branch selection on first login, store
payment account import from CSV, and administration for privileged roles.

## Acceptance Criteria

- `data/store_account.csv` is present in the repo.
- Backend can import store account rows into `Store`.
- First-login users without a branch must choose one and see a lock warning.
- Users can edit profile display names and upload an avatar.
- `ADMIN` and `SUPER_ADMIN` can open administration from the app.
- Administration contains user management, role management, SR management,
  Region/Area management, personnel catalog management, feature management,
  and manual inventory import when the resolved feature map allows them.
- Role management supports adding, editing, and deleting custom roles.
- System roles are protected from deletion.
- Store management supports adding, editing, and deleting stores.
- Stores assigned to users are protected from deletion.
- SR management assigns each SR to an Area; Region is derived from Area.
- Store-scoped users derive Region/Area from their assigned SR and do not need
  a direct Region/Area assignment.
- Feature management supports API-enforced enabled/disabled rules by feature,
  system role, department, job role, work scope, Region, Area, SR, and user
  override. `SUPER_ADMIN` bypasses feature gates to avoid lockout.
- User assignment uses the backend role catalog.
- `SUPER_ADMIN` can change user roles after registration; registration itself
  does not expose role, Region, or Area selection.
- `MANAGER` can manage users and store settings only inside their assigned
  showroom.
- Store settings include VietinBank MAP username/password fields for future
  bank-web reconciliation. Passwords are encrypted at rest and are never sent
  back to the app.
- User self-service branch changes are rejected after the first selection.
- VietQR uses the selected store's configured transfer account when available.

## Validation

- Backend build and Jest tests.
- Flutter analyze and tests.
- Local DB migration and store-account import smoke.
