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
  `workScopeType`, and generated `personnelCode`.
- Store-scoped personnel codes include the SR code, for example `SALE_CP62`,
  `MANAGER_CP62`, and `WAREHOUSE_CP62`.
- Online sales keeps `SALE_ONLINE`.
- Branch selection is required only when the effective work scope is `STORE`
  and the user has no assigned store.
- Task assignment is explicitly out of scope for this story.

## Validation

- Prisma generate.
- Backend build and focused auth/user Jest tests.
- Flutter analyze and tests.
- Admin user form smoke for system role, department, job role, scope, and
  generated personnel code display.
