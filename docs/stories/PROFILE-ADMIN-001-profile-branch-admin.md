# PROFILE-ADMIN-001 Profile, Organization Assignment, And User Admin

## Scope

Add personal profile management, admin-assigned organization nodes, store payment
account import from CSV, and administration for privileged roles.

## Acceptance Criteria

- `data/store_account.csv` is present in the repo.
- Backend can import store account rows into `Store`.
- Newly registered users without an organization node authenticate into the
  assignment-pending screen and do not self-select an SR/store.
- Users can edit profile display names and upload an avatar.
- `SUPER_ADMIN` and scoped `ADMIN` users can open administration from the app
  when their resolved feature map allows it.
- `ADMIN` is scoped by its assigned organization root, with email-domain
  fallback during rollout. Legacy role aliases `ADMIN_PHONGVU`, `ADMIN_ACARE`,
  `MANAGER`, and `STAFF` are normalized to `ADMIN` or `USER`.
- Forbidden admin API responses do not log the user out; only unauthorized
  session responses clear the local session.
- Administration contains user management, read-only system role management,
  Lv0-Lv5 organization tree management, personnel catalog management, feature
  management, policy management, settings management, and manual inventory
  import when the resolved feature map allows them. Legacy Region/Area/SR admin
  screens are retired.
- System roles are fixed to `SUPER_ADMIN`, `ADMIN`, and `USER`; role create,
  update, and delete requests are rejected with a fixed-role message.
- Legacy admin APIs `/admin/regions`, `/admin/areas`, and `/admin/stores`
  return `410 Gone`. Runtime `/stores`, `Store`, payment/MAP fields, FIFO,
  and VietQR remain compatible.
- Organization tree administration uses feature/policy code `ADMIN_ORG_TREE`.
  Legacy `ADMIN_STORES`, `ADMIN_REGIONS`, and `ADMIN_PERSONNEL` are preserved
  only for history/backfill and are hidden from the feature picker.
- Lv4 store nodes in the organization tree are the admin surface for SR/store
  metadata. Tree saves sync the related `Store` row without overwriting existing
  SR identity, payment, transfer, or MAP fields unless those fields are
  explicitly edited in the Lv4 store editor.
- Store-scoped users derive Region/Area from their assigned SR and do not need
  a direct Region/Area assignment.
- Admin user editing uses the organization tree for assignment. The app sends
  `organizationNodeId`; legacy work scope, store, region, area, department, and
  job-role columns are backend-derived compatibility fields, not editor inputs.
- Organization management supports `LV0_DOMAIN`, `LV1_BLOCK`,
  `LV2_DEPARTMENT`, `LV2_REGION`, `LV3_AREA`, `LV3_UNIT`, `LV4_STORE`, and
  `LV5_POSITION`. Lv0 is the only parentless root. Other nodes can attach to
  any active parent with a lower level, including skipped-level paths such as
  `Lv0 -> Lv2 -> Lv3`. Subdomain nodes are retired from active responses, and
  delete is blocked with explicit reasons when a node has children, users, SRs,
  or other references.
- Runtime feature access is a strict per-user allowlist. `SUPER_ADMIN` can
  assign multiple active features from user management through the feature tree;
  the app sends `featureTreeCodes` and the backend saves selected descendants
  with their ancestors. Non-`SUPER_ADMIN` users cannot open unassigned features
  even when a policy rule would allow the capability. Legacy feature rules
  remain for reference and backfill.
- `SUPER_ADMIN` bypasses feature gates to avoid lockout.
- User management supports filters by name/email search, domain,
  organization node, feature/screen, role, and status.
- Policy management supports configurable policy definitions, detailed policy
  rules, and system settings for login domains, password policy, and OTP
  policies. App policy and feature rule editing uses organization tree nodes
  instead of legacy Region/Area/SR selectors, while the backend keeps legacy
  rule fields for compatibility/backfill. Policy rule matching uses the user's
  assigned organization node before the showroom fallback, so Lv5-specific
  policy rules work for tree-assigned users. Settings can save JSON object or
  array values.
- User assignment uses the fixed backend role catalog.
- `SUPER_ADMIN` can change user roles after registration; registration itself
  does not expose role, organization node, Region, or Area selection.
- Scoped `ADMIN` can manage users and Lv4 store MAP settings only inside their
  organization scope. Legacy `MANAGER` users normalize to `ADMIN` during
  rollout; new assignments should use `ADMIN` or `USER`.
- Store settings include VietinBank MAP username/password fields for future
  bank-web reconciliation. Passwords are encrypted at rest and are never sent
  back to the app. Scoped admins must not edit transfer account number/name,
  bank, BIN, SR code/name, or Region/Area through the MAP credential flow.
- VietQR uses the selected store's configured transfer account when available.

## Validation

- Backend build and Jest tests.
- Flutter analyze and tests.
- Local DB migration and store-account import smoke.
