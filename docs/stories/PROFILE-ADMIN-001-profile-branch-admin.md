# PROFILE-ADMIN-001 Profile, Branch Selection, And User Admin

## Scope

Add personal profile management, one-time branch selection on first login, store
payment account import from CSV, and administration for privileged roles.

## Acceptance Criteria

- `data/store_account.csv` is present in the repo.
- Backend can import store account rows into `Store`.
- First-login users without a branch must choose one and see a lock warning.
- Users can edit profile display names and upload an avatar.
- `ADMIN_PHONGVU`, `ADMIN_ACARE`, and `SUPER_ADMIN` can open administration
  from the app when their resolved feature map allows it.
- `ADMIN_PHONGVU` is scoped to the `phongvu.vn` organization root;
  `ADMIN_ACARE` is scoped to the `acare.vn` root and `@acare.vn` users.
- Forbidden admin API responses do not log the user out; only unauthorized
  session responses clear the local session.
- Administration contains user management, role management, SR management,
  organization tree management, Region/Area management, personnel catalog
  management, feature management, policy management, settings management, and
  manual inventory import when the resolved feature map allows them.
- Role management supports adding, editing, and deleting custom roles.
- System roles are protected from deletion.
- Store management supports adding, editing, and deleting stores for
  `SUPER_ADMIN`; `ADMIN_PHONGVU` and `ADMIN_ACARE` can edit only MAP username
  and MAP password for SRs inside their scope.
- Stores assigned to users are protected from deletion.
- SR management assigns each SR to an Area; Region is derived from Area.
- Store-scoped users derive Region/Area from their assigned SR and do not need
  a direct Region/Area assignment.
- Admin user editing uses the organization tree for work-scope assignment:
  root domain for `NATIONAL`, showroom node for `STORE`, and active
  `REGION`/`AREA` nodes only when those node types exist. Legacy store/region
  columns are backend-derived compatibility fields, not editor inputs.
- Organization management supports root domain, subdomain, block, department,
  area, showroom, job role, and virtual scope nodes. Default root domains are
  `phongvu.vn` and `acare.vn`; root nodes start collapsed in the app, and
  delete is blocked with explicit reasons when a node has children, users, SRs,
  or other references.
- Runtime feature access is a strict per-user allowlist. `SUPER_ADMIN` can
  assign multiple active features from user management; non-`SUPER_ADMIN` users
  cannot open unassigned features even when a policy rule would allow the
  capability. Legacy feature rules remain for reference and backfill.
- `SUPER_ADMIN` bypasses feature gates to avoid lockout.
- User management supports filters by name/email search, domain,
  organization node, feature/screen, role, and status.
- Policy management supports configurable policy definitions, detailed policy
  rules, and system settings for login domains, password policy, and OTP
  policies. Policy batch creation supports multiple selected users, email
  domains, system roles, departments, job roles, scopes, Regions, Areas, SRs,
  and scope text selectors.
- User assignment uses the backend role catalog.
- `SUPER_ADMIN` can change user roles after registration; registration itself
  does not expose role, Region, or Area selection.
- `MANAGER` can manage users and store settings only inside their assigned
  showroom.
- Store settings include VietinBank MAP username/password fields for future
  bank-web reconciliation. Passwords are encrypted at rest and are never sent
  back to the app. Scoped admins must not edit transfer account number/name,
  bank, BIN, SR code/name, or Region/Area through the MAP credential flow.
- User self-service branch changes are rejected after the first selection.
- VietQR uses the selected store's configured transfer account when available.

## Validation

- Backend build and Jest tests.
- Flutter analyze and tests.
- Local DB migration and store-account import smoke.
