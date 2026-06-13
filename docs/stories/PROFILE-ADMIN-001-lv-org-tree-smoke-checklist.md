# PROFILE-ADMIN-001 Lv Org Tree Smoke Checklist

Use this checklist after the staging build/deploy that includes the Lv0-Lv5
organization tree and fixed system-role rollout.

## Pre-Smoke

- [ ] Confirm the staging deployment completed successfully.
- [ ] Confirm Prisma migration `20260612180000_lv_org_tree_roles` applied.
- [ ] Confirm Prisma migration `20260613100000_admin_org_tree_feature` applied.
- [ ] Run `npm run audit:node-features` before migration/deploy; report is
  clean or every divergent node group has been fixed intentionally.
- [ ] Confirm Prisma migration `20260613190000_node_feature_assignments`
  applied after the preflight report is clean.
- [ ] Confirm backend health endpoint returns healthy.
- [ ] Confirm app build/version shown to the tester is the new staging build.
- [ ] Keep a rollback point ready: previous staging image/build and DB backup.

## Backend API Smoke

- [ ] `GET /admin/org-tree` returns active Lv0-Lv5 nodes and no active
  `SUBDOMAIN` nodes.
- [ ] Creating a node with skipped levels works, for example `Lv0 -> Lv2`.
- [ ] Creating a node under an equal or higher level parent is rejected.
- [ ] `GET /admin/regions` returns `410 Gone` with a clear tree-retired message.
- [ ] `GET /admin/areas` returns `410 Gone` with a clear tree-retired message.
- [ ] `GET /admin/stores` returns `410 Gone` with a clear tree-retired message.
- [ ] Runtime `GET /stores` still returns the existing selectable SR/store list.
- [ ] Role list returns only `SUPER_ADMIN`, `ADMIN`, and `USER`.
- [ ] Role create/update/delete requests are rejected with the fixed-role
  message.
- [ ] `POST /users/me/select-store` returns `410 Gone` with a clear retired
  self-selection message.
- [ ] `/admin/features/tree` shows `Cơ cấu tổ chức`/`ADMIN_ORG_TREE` and does
  not show legacy `ADMIN_STORES`, `ADMIN_REGIONS`, or `ADMIN_PERSONNEL`.
- [ ] `GET /admin/features/node-assignments` returns node-group assignments
  with impacted user counts.
- [ ] `POST /admin/features/node-assignments/batch` saves a selected node plus
  `featureTreeCodes`; `/features/me` changes only for users in the same direct
  node group.

## SUPER_ADMIN App Smoke

- [ ] Login as `SUPER_ADMIN`; admin menu is visible.
- [ ] Open `Co cau to chuc`; verify labels show Lv0-Lv5 and no subdomain type.
- [ ] Create/edit a Lv2 or Lv3 node under a skipped-level parent.
- [ ] Create/edit a Lv4 store node and confirm existing SR identity/payment
  fields are not changed unexpectedly.
- [ ] Expand a Lv4 store and confirm it has exactly five fixed Lv5 positions:
  `STORE_MANAGER`, `SA`, `TECHNICIAN`, `CASH`, and `WAREHOUSE`.
- [ ] Create a new Lv4 store test node and confirm the five fixed Lv5 positions
  are created automatically.
- [ ] Edit Lv4 MAP username/password fields only when intentionally testing MAP.
- [ ] Open user management; role dropdown has only `SUPER_ADMIN`, `ADMIN`,
  `USER`.
- [ ] Assign a user to Lv0, Lv2/Lv3, Lv4, and Lv5 nodes in separate tests; save
  succeeds and the selected node remains visible after reload.
- [ ] User edit dialog has no direct `Phòng ban` or `Chức danh` assignment rows;
  node picker supports search, type filter, full breadcrumb, level badge, and
  selected-state visibility.
- [ ] User edit dialog has no feature picker and does not send
  `featureTreeCodes`.
- [ ] Open feature management -> Node tab; assign a feature set to one Lv5
  group and verify impacted user count.
- [ ] Open `Cơ cấu tổ chức`, select a node, use `Tính năng`, save the same node
  group feature set, and verify the Node tab reflects it.
- [ ] Newly registered user lands on `/assignment-pending` with the exact
  support text, refresh button, and logout button.
- [ ] Save a feature rule with an organization tree node.
- [ ] Save a policy rule with an organization tree node.

## Scoped ADMIN App Smoke

- [ ] Login as scoped `ADMIN`; admin menu appears only for assigned features.
- [ ] `ADMIN` sees only users/nodes inside its organization scope.
- [ ] `ADMIN` cannot edit `SUPER_ADMIN` users.
- [ ] `ADMIN` can reset password only for an in-scope non-`SUPER_ADMIN` user.
- [ ] `ADMIN` can edit only MAP username/password for an in-scope Lv4 store.
- [ ] `ADMIN` cannot change SR code/name, bank, transfer account, Region, or
  Area fields.
- [ ] `ADMIN` cannot assign users to another root/domain.

## USER App Smoke

- [ ] Login as `USER`; admin menu is not visible unless the user's direct node
  group has the required active feature assignment.
- [ ] Existing daily flows still work for the assigned SR/store.
- [ ] Unassigned `USER` remains on the assignment-pending screen until a
  `SUPER_ADMIN` assigns an organization node, then refresh/login enters the app.

## Runtime Regression Smoke

- [ ] FIFO check works for an existing SR.
- [ ] Manual FIFO inventory import remains gated by admin import permission.
- [ ] VietQR generation still uses the existing SR transfer account data.
- [ ] MAP/payment monitor still reads existing store MAP configuration.
- [ ] Payment speaker ready/audio/ack works for Lv5 `STORE_MANAGER` or `CASH`.
- [ ] Payment speaker ready list is empty, and audio/ack is forbidden, for a
  non-speaker Lv5 position such as `WAREHOUSE`.
- [ ] Bank statement store filter still lists the expected SRs.
- [ ] Warranty list/detail remains scoped to the user's SR.

## Logging And Evidence

- [ ] Backend logs show org-node save start/success/failure context without
  secrets.
- [ ] Backend logs show legacy role alias normalization if old-role test data is
  used.
- [ ] Backend logs show old admin API `410` hits.
- [ ] Flutter `AppLogger` records org tree load/save/delete and user save with
  role/org node context.
- [ ] Flutter `AppLogger` records assignment-pending refresh success/failure and
  user save with role/org-node context.
- [ ] Attach screenshots or notes for every failed item before rollback or fix.

## Pass Criteria

- [ ] No SR identity/payment/MAP/FIFO/VietQR data changed unexpectedly.
- [ ] No active subdomain appears in the organization tree UI/API.
- [ ] Old admin Region/Area/SR APIs consistently return `410 Gone`.
- [ ] Role behavior matches `SUPER_ADMIN -> ADMIN -> USER`.
- [ ] All critical runtime flows above pass or have a named blocker.
