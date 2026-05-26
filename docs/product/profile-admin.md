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

- `SUPER_ADMIN` and `ADMIN` can open the administration menu.
- The administration menu contains user management, role management, and store
  management.
- Admin users can list, add, and edit users.
- Role management lists roles from the backend role catalog.
- `SUPER_ADMIN` can add, edit, and delete custom roles.
- System roles are seeded by the backend and cannot be deleted from the app.
- Custom roles cannot be deleted while assigned to users.
- Store management lists store code, store name, and transfer account
  configuration.
- `SUPER_ADMIN` can add, edit, and delete stores.
- Stores cannot be deleted while assigned to users.
- `ADMIN` is scoped to users in the same store and cannot assign
  `SUPER_ADMIN`.
- `SUPER_ADMIN` can manage all users.
- `MANAGER` can open administration for their own showroom scope.
- `SUPER_ADMIN` can assign or change user roles after registration; users do
  not choose roles during registration.
- Store administration can keep a VietinBank MAP username plus an encrypted MAP
  password for later transaction reconciliation. The API returns whether a MAP
  password exists, but never returns the password itself.

## Personnel Role Foundation

- System access role remains separate from operational personnel assignment.
  `User.role` continues to control app/admin permissions.
- Admin user management can assign department, job role, and work scope for
  future task assignment.
- Default departments are management, sales, cashier, technical, warehouse,
  back office, and executive.
- Default job roles include manager, sale, sale online, cashier, technician,
  warehouse, area manager, regional manager, back office, BOD, and CEO.
- Work scope values are `STORE`, `MULTI_STORE`, `REGION`, `NATIONAL`, and
  `ONLINE`.
- The API returns a generated `personnelCode` for debugging and future task
  routing. Store-scoped staff use codes such as `SALE_CP62`, `MANAGER_CP62`,
  and `WAREHOUSE_CP62`; online sales keeps `SALE_ONLINE`.
- Task assignment itself is not implemented in this slice. This slice only
  prepares the data model, API contract, and admin UI needed for it.
