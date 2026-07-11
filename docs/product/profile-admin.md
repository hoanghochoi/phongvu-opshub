# Profile And Administration

OpsHub supports personal profile management, admin-assigned organization nodes,
and basic administration for privileged roles.

## Personal Profile

- Staff can view and update their display name.
- Staff can upload an avatar image.
- Staff do not choose a branch/store during registration or first login. If
  their account has no active organization assignment, the app shows the
  assignment pending screen and asks them to contact support.
- The backend rejects the retired self-service store-selection API with
  `410 Gone`.

## Store Account Data

- Store payment account data is stored in `data/store_account.csv`.
- The backend import command is:
  `npm run import:store-accounts -- ../data/store_account.csv`.
- Imported rows upsert `Store` records with transfer account number, account
  name, and bank name.
- VietQR generation prefers the selected store's transfer account when present.

## Admin Management

- Admin menu visibility is resolved through backend feature and policy maps.
  Runtime feature access uses node-group assignments from the user's direct
  active organization node: same root + node type + business code/code share the
  same active feature set. Policy rules still control capability and data
  scope, but they do not automatically open a feature that is not assigned to
  the user's direct node group.
- The administration menu contains user management, read-only system role
  management, Lv0-Lv5 organization tree management, personnel catalog
  management, feature management, policy management, and manual FIFO inventory
  import when the resolved feature map allows them. Legacy Region/Area/SR
  administration screens are not exposed; their data is maintained through the
  organization tree or runtime store flows.
- Admin users can list, add, and edit users inside their permitted scope.
  A user can be assigned to one or many active organization nodes/showrooms.
  `UserOrganizationAssignment` is the source of truth for those assignments;
  legacy `organizationNodeId`, `storeId`, personnel scope, Region, and Area
  fields are compatibility output during rollout.
- Only `SUPER_ADMIN` can create users or import nhân sự from an Excel file using
  the template headers `email`, `full_name`, `system_role`, and `lv0` through
  `lv5`; import can also use `store_ids` for semicolon/comma-separated showroom
  assignments. The backend matches `lv*` values to active organization node
  `code`/`businessCode`, assigns the deepest matched node, syncs every resolved
  assignment, creates passwordless users, and upserts existing users without
  changing their password. Import rejects the whole file before writing when
  any email has invalid syntax or a domain outside `AUTH_ALLOWED_EMAIL_DOMAINS`.
- New users created by `SUPER_ADMIN`, including import-created rows, receive a
  welcome email that points them to the in-app `Quên mật khẩu` first-password
  flow. SMTP failures do not roll back user creation; the UI reports the email
  failure count.
- `SUPER_ADMIN` can hard-delete a locked user only when the account has no
  business/history references. Active users, `SUPER_ADMIN` accounts, self-delete,
  and users tied to warranty, feedback, FIFO, VietQR, MAP order history, or node
  assignment history are blocked with an explicit reason.
- User management keeps name/email search and filters for domain, organization
  node, feature/screen, role, and status. List filters use dropdown/anchored
  menus, and dropdowns with more than 10 options include search. The
  feature/screen filter resolves through node-group feature assignments; the
  user editor does not assign per-user feature exceptions.
- System access roles are fixed to `SUPER_ADMIN`, `ADMIN`, and `USER`.
  `SUPER_ADMIN` can manage all roots. `ADMIN` is scoped by its assigned
  organization root, with email-domain fallback during rollout. `USER` has no
  administration surface by role alone.
- For user and store administration, an `ADMIN` assigned directly to a Lv5
  position under a Lv4 showroom manages the owning showroom subtree, not only
  that single Lv5 position. This lets a store-manager account with `ADMIN_USERS`
  see and manage the staff assigned to other Lv5 positions in the same
  showroom, while still excluding other showrooms.
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
  fields, MAP credentials, FIFO, and VietQR remain compatible.
- Organization tree administration is gated by feature/policy code
  `ADMIN_ORG_TREE` and appears as `Cơ cấu tổ chức`. Legacy feature codes
  `ADMIN_STORES` and `ADMIN_REGIONS` remain in the database only for
  history/backfill and are hidden from the user feature picker.
  `ADMIN_PERSONNEL` is exposed again as `Danh mục nhân sự` for maintaining
  department and job-role catalogs used by permissions, reports, and
  compatibility fields.
- Organization management lets `SUPER_ADMIN` maintain the source-of-truth tree:
  `LV0_DOMAIN`, `LV1_BLOCK`, `LV2_DEPARTMENT`, `LV2_REGION`, `LV3_AREA`,
  `LV3_UNIT`, `LV4_STORE`, and `LV5_POSITION`. Lv0 is the highest level and
  the only node without a parent; other nodes may attach to any active parent
  with a lower level, so skipped levels such as `Lv0 -> Lv2 -> Lv3` are valid.
  Subdomain nodes are retired from the active tree instead of hard-deleted.
  Nodes with children, users, SRs, or other references are blocked from
  deletion and the API returns the blocking counts/reasons.
- When an admin deactivates any organization node, default seeding and legacy
  sync jobs must preserve that inactive state. Deactivating a parent cascades
  inactive status to every descendant node, and the edit dialog warns
  `Nếu tắt node này thì các node con cũng sẽ tắt!` before saving.
- Lv4 store nodes are the admin surface for SR/store metadata. Tree saves sync
  the related `Store` row without overwriting existing SR identity, payment,
  transfer, or MAP fields unless those fields are explicitly edited in the Lv4
  store editor. Legacy store sync must preserve a manually inactive Lv4 store
  node and must not reactivate it just because the linked `Store` row still
  exists; default Lv5 store positions also stay inactive when an admin has
  turned them off.
- Each active Lv4 store has five fixed Lv5 position children: `STORE_MANAGER`
  (`Quản lý Cửa hàng`), `SA` (`Nhân viên Bán hàng`), `TECHNICIAN` (`Kỹ thuật
  viên`), `CASH` (`Nhân viên Thu ngân`), and `WAREHOUSE` (`Nhân viên Kho`).
  New store nodes create these positions automatically; existing store nodes are
  backfilled when the store tree sync runs.
- Feature management keeps feature definitions and legacy feature rules for
  reference/rollback, but the primary runtime gate is now
  `OrganizationNodeFeatureAssignment`. `SUPER_ADMIN` assigns features from the
  feature-management Node tab or from the selected node in the organization
  tree. The backend expands selected feature-tree descendants to include their
  ancestors and stores one row per root + node type + node key + feature.
  The node-feature assignment dialog shows related policy reminders, for
  example `BANK_STATEMENTS` points admins to `BANK_STATEMENT_ALL_SCOPE` when
  national all-showroom statement access is intended; it does not create policy
  rules automatically.
  Migration audit still reports orphaned per-user feature rows, but rollout
  blocks only divergent node groups; users without an active direct node are
  skipped from backfill because runtime node-group access already denies them.
  `SUPER_ADMIN` bypasses feature gates to avoid lockout.
- Policy management lets `SUPER_ADMIN` manage admin policy definitions, policy
  rules, and system settings. New and edited policy rules require at least one
  organization tree node; legacy Department/JobRole/work-scope/Region/Area/SR/
  user/scope-contains selectors remain readable for historical rules but are
  rejected on create/update. Optional email-domain and system-role selectors
  can further narrow each selected node rule. Policy matching keeps the assigned
  organization node as the source of truth, so rules can target a user's exact
  Lv5 node or any ancestor node. Auth domain, password policy, and OTP policy
  settings are managed from the policy settings tab and can store JSON object
  or array values.
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
- Admin user management assigns only an organization node. Department/job-role
  compatibility columns are derived from that node by the backend and are not
  user-editor inputs.
- User work-scope assignment uses the organization tree as the source of truth:
  any active Lv0-Lv5 node can contain users/staff. Legacy `workScopeType`,
  `storeId`, `regionCode`, and `areaCode` remain derived backend/runtime fields,
  not user-editor inputs.
- Default departments are management, sales, cashier, technical, warehouse,
  back office, and executive.
- Default job roles include the fixed store positions `STORE_MANAGER`, `SA`,
  `TECHNICIAN`, `CASH`, and `WAREHOUSE`, plus rollout compatibility roles such
  as `CHATSALE`, `TELESALE`, `AREA_MANAGER`, `REGIONAL_MANAGER`, back office,
  BOD, and CEO. These are operational personnel roles, separate from the three
  fixed system access roles.
- Payment speaker ready-claim/audio/ack is controlled by the separate
  `PAYMENT_SPEAKER` (`Đọc loa`) feature assigned to the user's direct
  organization node group or any active assigned node group. `PAYMENT_MONITOR`
  opens the `Tiền vào` transaction view across the user's assigned showrooms,
  while `PAYMENT_SPEAKER` permits audio polling, audio download, and
  payment-notification ack only after the app has exactly one active showroom
  selected on a supported Windows PC. Mobile and other unsupported platforms do
  not enable the speaker path by default. The rollout backfills
  `PAYMENT_SPEAKER` only for Lv5 `STORE_MANAGER` and `CASH` node groups that
  already have `PAYMENT_MONITOR`, so current speaker users keep working without
  opening speaker access to every monitor user.
- Work scope values are `NATIONAL`, `REGION`, `AREA`, and `STORE`.
  `MULTI_STORE` is not accepted. Legacy `ONLINE` is migrated to
  `REGION + CHATSALE` and is not exposed in the public contract.
- SR-scoped users do not need a direct Region/Area assignment. When their SR
  has an Area, the backend derives the user's `areaCode` and `regionCode` from
  that SR during admin assignment.
- `CHATSALE` and `TELESALE` are virtual Region-level scopes.
- The API returns a generated `personnelCode` for debugging and future task
  routing in the format `JOBROLE_SR_AREA_REGION`. Examples:
  `SA_CP62_HCM_MN`, `STORE_MANAGER_CP62_HCM_MN`,
  `AREA_MANAGER_HCM_HCM_MN`, `CHATSALE_CHATSALE_CHATSALE_CHATSALE`, and
  `OPS_NATIONAL_NATIONAL_NATIONAL`.
- Task assignment itself is not implemented in this slice. This slice only
  prepares the data model, API contract, and admin UI needed for it.
