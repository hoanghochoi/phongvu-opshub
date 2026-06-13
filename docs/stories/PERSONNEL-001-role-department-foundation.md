# PERSONNEL-001 Role, Department, And Scope Foundation

## Scope

Add a personnel assignment layer beside system access roles so OpsHub can later
assign tasks by department, job role, work scope, and SR.

## Acceptance Criteria

- `User.role` remains the system access role used by existing authorization and
  is fixed to `SUPER_ADMIN`, `ADMIN`, or `USER`.
- Users can store department code, job role code, and work scope type.
- Backend seeds default department and job-role catalogs.
- Admin user management assigns an active organization node. Department and job
  role compatibility fields are derived from the selected node. The editor sends
  `organizationNodeId` as the source of truth for staff placement.
- Auth/profile/admin user responses include `departmentCode`, `jobRoleCode`,
  `workScopeType`, Region/Area fields, and generated `personnelCode`.
- Organization nodes are ordered `Lv0 -> Lv5`: `LV0_DOMAIN`, `LV1_BLOCK`,
  `LV2_DEPARTMENT`/`LV2_REGION`, `LV3_AREA`/`LV3_UNIT`, `LV4_STORE`, and
  `LV5_POSITION`. Lv0 is highest, Lv5 is lowest, and parent links may skip
  levels as long as the parent level is lower than the child level.
- Every active Lv4 store owns five fixed Lv5 positions:
  `STORE_MANAGER`, `SA`, `TECHNICIAN`, `CASH`, and `WAREHOUSE`. New store nodes
  create these children automatically, and existing stores are backfilled during
  store/tree sync without changing SR identity or payment metadata.
- Payment speaker behavior is a runtime permission of Lv5 store positions:
  only `STORE_MANAGER` and `CASH` can poll, stream, or acknowledge payment
  audio.
- Legacy work scopes remain compatibility fields derived from the selected
  organization node: `NATIONAL -> REGION -> AREA -> STORE`.
- Store-scoped personnel codes include SR, Area, and Region, for example
  `SA_CP62_HCM_MN`, `STORE_MANAGER_CP62_HCM_MN`, and
  `WAREHOUSE_CP62_HCM_MN`.
- Region-scoped virtual channels use `CHATSALE` and `TELESALE`; legacy
  `ONLINE` is migration-only and maps to `REGION + CHATSALE`.
- `MULTI_STORE` is removed from the public contract and rejected after
  migration.
- Store-scoped users derive Region/Area from their assigned Lv4 store/SR.
- Registration does not expose SR/store, Region, Area, department, or job-role
  selection. Unassigned users stay on the assignment-pending screen until an
  admin assigns an organization node.
- Task assignment is explicitly out of scope for this story.

## Validation

- Prisma generate.
- Backend build and focused auth/user/feature Jest tests.
- Flutter analyze and personnel parsing tests.
- Admin user form smoke for system role, department, job role, scope, and
  generated personnel code display.
