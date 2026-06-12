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
- The administration menu contains user management, read-only system role
  management, Lv0-Lv5 organization tree management, personnel catalog
  management, feature management, policy management, and manual FIFO inventory
  import when the resolved feature map allows them. Legacy Region/Area/SR
  administration screens are not exposed; their data is maintained through the
  organization tree or runtime store flows.
- Admin users can list, add, and edit users inside their permitted scope.
- User management keeps name/email search and adds filters for domain,
  organization node, feature/screen, role, and status. `SUPER_ADMIN` can assign
  multiple allowed features from the user edit dialog. User feature assignment
  is submitted as `featureTreeCodes`; the backend expands selected child nodes
  to include their feature-tree ancestors before saving `UserFeatureAssignment`
  rows.
- System access roles are fixed to `SUPER_ADMIN`, `ADMIN`, and `USER`.
  `SUPER_ADMIN` can manage all roots. `ADMIN` is scoped by its assigned
  organization root, with email-domain fallback during rollout. `USER` has no
  administration surface by role alone.
- The backend migration normalizes legacy role aliases during rollout:
  `ADMIN`, `ADMIN_PHONGVU`, `ADMIN_ACARE`, and `MANAGER` become `ADMIN`;
  `STAFF` becomes `USER`. Login, JWT, feature, and policy checks normalize
  aliases so old tokens/imports do not break immediately.
- Admin API `403 Forbidden` responses do not clear the local login session;
  only `401 Unauthorized` is treated as an auth failure.
- Role management lists the three fixed system roles from the backend role
  catalog. Role create, update, and delete requests are rejected with a fixed
  role message.
- Legacy admin APIs `/admin/regions`, `/admin/areas`, and `/admin/stores`
  return `410 Gone`. Runtime `/stores`, the `Store` table, payment account
  fields, MAP credentials, FIFO, VietQR, and store selection remain compatible.
- Organization management lets `SUPER_ADMIN` maintain the source-of-truth tree:
  `LV0_DOMAIN`, `LV1_BLOCK`, `LV2_DEPARTMENT`, `LV2_REGION`, `LV3_AREA`,
  `LV3_UNIT`, `LV4_STORE`, and `LV5_POSITION`. Lv0 is the highest level and
  the only node without a parent; other nodes may attach to any active parent
  with a lower level, so skipped levels such as `Lv0 -> Lv2 -> Lv3` are valid.
  Subdomain nodes are retired from the active tree instead of hard-deleted.
  Nodes with children, users, SRs, or other references are blocked from
  deletion and the API returns the blocking counts/reasons.
- Lv4 store nodes are the admin surface for SR/store metadata. Tree saves sync
  the related `Store` row without overwriting existing SR identity, payment,
  transfer, or MAP fields unless those fields are explicitly edited in the Lv4
  store editor.
- Feature management keeps feature definitions and legacy feature rules for
  reference/backfill, but the primary runtime gate is now the user feature
  assignment allowlist. Feature rule create/edit in the app uses organization
  tree nodes instead of legacy Region/Area/SR selectors. `SUPER_ADMIN` bypasses
  feature gates to avoid lockout.
- Policy management lets `SUPER_ADMIN` manage admin policy definitions, policy
  rules, and system settings. Policy rules support the same detailed selectors
  as feature rules plus `scopeContains`, and app rule create/edit uses
  organization tree nodes instead of legacy Region/Area/SR selectors. Auth
  domain, password policy, and OTP policy settings are managed from the policy
  settings tab and can store JSON object or array values.
- `ADMIN` can reset passwords only for users inside their organization scope
  and cannot reset `SUPER_ADMIN`.
- `SUPER_ADMIN` can manage all users.
- Legacy `MANAGER` users normalize to `ADMIN` during rollout; new system role
  assignment uses only `SUPER_ADMIN`, `ADMIN`, or `USER`.
- `SUPER_ADMIN` can assign or change user roles and personnel scope after
  registration; users do not choose role, organization node, Region, Area,
  Chatsale, or Telesale during registration.
- Store administration can keep a VietinBank MAP username plus an encrypted MAP
  password for later transaction reconciliation. Scoped `ADMIN` users may edit
  only those MAP credential fields for Lv4 stores in scope; they cannot edit
  transfer account number/name, bank, BIN, SR code/name, or Region/Area without
  separate privileges. The API returns whether a MAP password exists, but never
  returns the password itself.

## Personnel Scope And Catalogs

- System access role remains separate from operational personnel assignment.
  `User.role` continues to control app/admin permissions.
- Admin user management can assign department, job role, and organization node
  for future task assignment. The editor sends `organizationNodeId` as the
  primary assignment input.
- User work-scope assignment uses the organization tree as the source of truth:
  any active Lv0-Lv5 node can contain users/staff. Legacy `workScopeType`,
  `storeId`, `regionCode`, and `areaCode` remain derived backend/runtime fields,
  not user-editor inputs.
- Default departments are management, sales, cashier, technical, warehouse,
  back office, and executive.
- Default job roles include `STORE_MANAGER`, `SALE`, `CHATSALE`, `TELESALE`,
  `CASHIER`, `TECHNICIAN`, `WAREHOUSE`, `AREA_MANAGER`, `REGIONAL_MANAGER`,
  back office, BOD, and CEO. These are operational personnel roles, separate
  from the three fixed system access roles.
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
