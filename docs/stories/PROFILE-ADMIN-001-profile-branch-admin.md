# PROFILE-ADMIN-001 Profile, Organization Assignment, And User Admin

## Scope

Add personal profile management, admin-assigned organization nodes, store payment
account import from CSV, and administration for privileged roles.

## Acceptance Criteria

- `data/store_account.csv` is present in the repo.
- Backend can import store account rows into `Store`.
- Newly registered users without any active organization assignment authenticate
  into the assignment-pending screen and do not self-select an SR/store.
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
  Legacy `ADMIN_STORES` and `ADMIN_REGIONS` are preserved only for
  history/backfill and are hidden from the feature picker. `ADMIN_PERSONNEL`
  is exposed as `Danh mục nhân sự` for maintaining department and job-role
  catalogs.
- Lv4 store nodes in the organization tree are the admin surface for SR/store
  metadata. Tree saves sync the related `Store` row without overwriting existing
  SR identity, payment, transfer, or MAP fields unless those fields are
  explicitly edited in the Lv4 store editor.
- Store-scoped users derive Region/Area from their assigned SRs and do not need
  a direct Region/Area assignment.
- Admin user editing uses the organization tree for assignment. The app sends
  `organizationNodeIds`; legacy work scope, store, region, area, department,
  and job-role columns are backend-derived compatibility fields, not editor
  inputs.
- Organization management supports `LV0_DOMAIN`, `LV1_BLOCK`,
  `LV2_DEPARTMENT`, `LV2_REGION`, `LV3_AREA`, `LV3_UNIT`, `LV4_STORE`, and
  `LV5_POSITION`. Lv0 is the only parentless root. Other nodes can attach to
  any active parent with a lower level, including skipped-level paths such as
  `Lv0 -> Lv2 -> Lv3`. Subdomain nodes are retired from active responses, and
  delete is blocked with explicit reasons when a node has children, users, SRs,
  or other references.
- Runtime feature access is assigned by direct organization node group. A group
  is the selected root plus the user's direct node type and business code/code;
  there is no ancestor/descendant inheritance in v1. `SUPER_ADMIN` assigns
  features from feature management or the organization-tree node panel. The app
  sends `organizationNodeIds` plus `featureTreeCodes`; the backend expands
  selected descendants with ancestors and saves
  `OrganizationNodeFeatureAssignment` rows. Legacy per-user assignments and
  feature rules remain only for audit/rollback during rollout. Migration
  rollout blocks divergent node groups, while orphaned users without an active
  direct node are reported and skipped from backfill because runtime access
  already denies them.
- `SUPER_ADMIN` bypasses feature gates to avoid lockout.
- User management supports filters by name/email search, domain,
  organization node, feature/screen, role, and status. List filters use
  dropdown/anchored menus, and dropdowns with more than 10 options include
  search.
- User management supports Excel import through `ADMIN_USERS` using the
  `user_temp.xlsx` header contract. Imports match `lv0`-`lv5` values by active
  organization node `code`/`businessCode` or `store_ids`, sync every resolved
  active assignment, create passwordless users, and upsert existing users
  without changing their password; imported users set their first password
  through `Quên mật khẩu`.
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
