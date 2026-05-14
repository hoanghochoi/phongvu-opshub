# Profile And User Administration

OpsHub supports personal profile management, one-time branch selection, and
basic user administration for privileged roles.

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

## Admin User Management

- `SUPER_ADMIN` and `ADMIN` can open the user administration screen.
- Admin users can list, add, and edit users.
- `ADMIN` is scoped to users in the same store and cannot assign
  `SUPER_ADMIN`.
- `SUPER_ADMIN` can manage all users.
