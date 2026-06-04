# PERSONNEL-001 Role, Department, And Scope Foundation

## Scope

Add a personnel assignment layer beside system access roles so OpsHub can later
assign tasks by department, job role, work scope, and SR.

## Acceptance Criteria

- `User.role` remains the system access role used by existing authorization.
- Users can store department code, job role code, and work scope type.
- Backend seeds default department and job-role catalogs.
- Admin user management can assign department, job role, and work scope.
- Auth/profile/admin user responses include `departmentCode`, `jobRoleCode`,
  `workScopeType`, Region/Area fields, and generated `personnelCode`.
- Work scopes are ordered as `NATIONAL -> REGION -> AREA -> STORE`.
- Store-scoped personnel codes include SR, Area, and Region, for example
  `SALE_CP62_HCM_MN`, `STORE_MANAGER_CP62_HCM_MN`, and
  `WAREHOUSE_CP62_HCM_MN`.
- Region-scoped virtual channels use `CHATSALE` and `TELESALE`; legacy
  `ONLINE` is migration-only and maps to `REGION + CHATSALE`.
- `MULTI_STORE` is removed from the public contract and rejected after
  migration.
- Store-scoped users derive Region/Area from their assigned SR; self-service
  registration and first SR selection do not expose Region/Area choices.
- Branch selection is required only when the effective work scope is `STORE`
  and the user has no assigned store.
- Task assignment is explicitly out of scope for this story.

## Validation

- Prisma generate.
- Backend build and focused auth/user/feature Jest tests.
- Flutter analyze and personnel parsing tests.
- Admin user form smoke for system role, department, job role, scope, and
  generated personnel code display.
