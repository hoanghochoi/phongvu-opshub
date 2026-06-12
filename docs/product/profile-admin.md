# Profile And Administration

OpsHub supports personal profile management, one-time branch selection, and
basic administration for privileged roles.

## Personal Profile

- Staff can view and update their display name.
- Staff can upload an avatar image.
- Staff must choose a branch when first signing in if their account does not
  already have one.
- The app warns that branch information is locked after confirmation.
- The backend rejects self-service branch changes once a branch is assigned.

## Store Account Data

- Store payment account data is stored in `data/store_account.csv`.
- The backend import command is:
  `npm run import:store-accounts -- ../data/store_account.csv`.
- Imported rows upsert `Store` records with transfer account number, account
  name, and bank name.
- VietQR generation prefers the selected store's transfer account when present.

## Admin Management

- Admin menu visibility is resolved through backend feature and policy maps.
  Runtime feature access uses a strict per-user allowlist; non-`SUPER_ADMIN`
  users can open only active features explicitly assigned to them. Policy rules
  still control capability and data scope, but they do not automatically open a
  feature that is not assigned to the user.
- The administration menu contains user management, role management, SR
  management, organization tree management, region/area management, personnel
  catalog management, feature management, policy management, and manual FIFO
  inventory import when the resolved feature map allows them.
- Admin users can list, add, and edit users inside their permitted scope.
- User management keeps name/email search and adds filters for domain,
  organization node, feature/screen, role, and status. `SUPER_ADMIN` can assign
  multiple allowed features from the user edit dialog.
- `ADMIN_PHONGVU` manages users and SRs under the `phongvu.vn` organization
  root. `ADMIN_ACARE` manages users and SRs under the `acare.vn` root,
  including accounts whose email ends with `@acare.vn`.
- The backend migration renames the legacy system role `ADMIN` to
  `ADMIN_PHONGVU`, keeps `ADMIN_ACARE` separate, and repairs the known `AC001`
  store/org link when that data exists.
- Admin API `403 Forbidden` responses do not clear the local login session;
  only `401 Unauthorized` is treated as an auth failure.
- Role management lists roles from the backend role catalog.
- `SUPER_ADMIN` can add, edit, and delete custom roles.
- System roles are seeded by the backend and cannot be deleted from the app.
- Custom roles cannot be deleted while assigned to users.
- SR management lists store code, store name, transfer account configuration,
  and assigned area/region.
- `SUPER_ADMIN` can add, edit, and delete SR rows.
- SR rows cannot be deleted while assigned to users or feature rules.
- Region/area management lets `SUPER_ADMIN` maintain Region (`Mien`) and Area
  (`Vung`) catalogs with display name, abbreviation, active state, and delete
  constraints.
- Organization management lets `SUPER_ADMIN` maintain a tree with root domain,
  subdomain, block, department, area, showroom, job role, and virtual scope
  nodes. Default root domains are `phongvu.vn` and `acare.vn`; the app shows
  only root nodes by default and expands children on click. Nodes with children,
  users, SRs, or other references are blocked from deletion and the API returns
  the blocking counts/reasons.
- Feature management keeps feature definitions and legacy feature rules for
  reference/backfill, but the primary runtime gate is now the user feature
  assignment allowlist. `SUPER_ADMIN` bypasses feature gates to avoid lockout.
- Policy management lets `SUPER_ADMIN` manage admin policy definitions, policy
  rules, and system settings. Policy rules support the same detailed selectors
  as feature rules plus `scopeContains`, and batch creation supports multiple
  selected users, domains, roles, departments, job roles, scopes, Regions,
  Areas, SRs, and scope text values. Auth domain, password policy, and OTP
  policy settings are managed from the policy settings tab.
- `ADMIN_PHONGVU` and `ADMIN_ACARE` can reset passwords only for users inside
  their organization scope and cannot reset `SUPER_ADMIN`.
- `SUPER_ADMIN` can manage all users.
- `MANAGER` can open administration for their own showroom scope.
- `SUPER_ADMIN` can assign or change user roles and personnel scope after
  registration; users do not choose role, Region, Area, Chatsale, or Telesale
  during registration.
- Store administration can keep a VietinBank MAP username plus an encrypted MAP
  password for later transaction reconciliation. `ADMIN_PHONGVU` and
  `ADMIN_ACARE` may edit only those MAP credential fields for SRs in scope;
  they cannot edit transfer account number/name, bank, BIN, SR code/name, or
  Region/Area without separate privileges. The API returns whether a MAP
  password exists, but never returns the password itself.

## Personnel Scope And Catalogs

- System access role remains separate from operational personnel assignment.
  `User.role` continues to control app/admin permissions.
- Admin user management can assign department, job role, and work scope for
  future task assignment.
- User work-scope assignment uses the organization tree as the source of truth:
  `NATIONAL` selects a root domain unless `SUPER_ADMIN` is intentionally global,
  `STORE` selects a showroom node, and `REGION`/`AREA` select active tree nodes
  only when those node types exist. Legacy `storeId`, `regionCode`, and
  `areaCode` remain derived backend/runtime fields, not user-editor inputs.
- Default departments are management, sales, cashier, technical, warehouse,
  back office, and executive.
- Default job roles include `STORE_MANAGER`, `SALE`, `CHATSALE`, `TELESALE`,
  `CASHIER`, `TECHNICIAN`, `WAREHOUSE`, `AREA_MANAGER`, `REGIONAL_MANAGER`,
  back office, BOD, and CEO. The system access role code `MANAGER` is not
  renamed.
- Work scope values are `NATIONAL`, `REGION`, `AREA`, and `STORE`.
  `MULTI_STORE` is not accepted. Legacy `ONLINE` is migrated to
  `REGION + CHATSALE` and is not exposed in the public contract.
- SR-scoped users do not need a direct Region/Area assignment. When their SR
  has an Area, the backend derives the user's `areaCode` and `regionCode` from
  that SR during admin assignment and self-service first SR selection.
- `CHATSALE` and `TELESALE` are virtual Region-level scopes.
- The API returns a generated `personnelCode` for debugging and future task
  routing in the format `JOBROLE_SR_AREA_REGION`. Examples:
  `SALE_CP62_HCM_MN`, `STORE_MANAGER_CP62_HCM_MN`,
  `AREA_MANAGER_HCM_HCM_MN`, `CHATSALE_CHATSALE_CHATSALE_CHATSALE`, and
  `OPS_NATIONAL_NATIONAL_NATIONAL`.
- Task assignment itself is not implemented in this slice. This slice only
  prepares the data model, API contract, and admin UI needed for it.
