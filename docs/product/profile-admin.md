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

- Admin menu visibility is resolved through backend feature gates; if no
  feature rule matches, existing authorization remains the fallback.
- The administration menu contains user management, role management, SR
  management, region/area management, personnel catalog management, feature
  management, and manual FIFO inventory import when the resolved feature map
  allows them.
- Admin users can list, add, and edit users inside their permitted scope.
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
- Feature management lets `SUPER_ADMIN` manage feature definitions and
  enabled/disabled rules by system role, department, job role, work scope,
  region, area, SR, and optional user override. API guards enforce these rules;
  Flutter only reflects the resolved state.
- `ADMIN` is scoped to users in the same store and cannot assign
  `SUPER_ADMIN`.
- `SUPER_ADMIN` can manage all users.
- `MANAGER` can open administration for their own showroom scope.
- `SUPER_ADMIN` can assign or change user roles and personnel scope after
  registration; users do not choose role, Region, Area, Chatsale, or Telesale
  during registration.
- Store administration can keep a VietinBank MAP username plus an encrypted MAP
  password for later transaction reconciliation. The API returns whether a MAP
  password exists, but never returns the password itself.

## Personnel Scope And Catalogs

- System access role remains separate from operational personnel assignment.
  `User.role` continues to control app/admin permissions.
- Admin user management can assign department, job role, and work scope for
  future task assignment.
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
