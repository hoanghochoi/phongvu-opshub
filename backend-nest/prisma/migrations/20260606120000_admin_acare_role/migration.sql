INSERT INTO "RoleDefinition" ("id", "code", "displayName", "description", "isSystem", "updatedAt")
VALUES (
  'role-admin-acare',
  'ADMIN_ACARE',
  'Admin ACare',
  'Quan ly user thuoc domain acaretek.vn',
  true,
  CURRENT_TIMESTAMP
)
ON CONFLICT ("code") DO UPDATE
SET "displayName" = EXCLUDED."displayName",
    "description" = EXCLUDED."description",
    "isSystem" = true,
    "updatedAt" = CURRENT_TIMESTAMP;

UPDATE "User"
SET "role" = 'ADMIN_ACARE',
    "workScopeType" = 'NATIONAL',
    "regionCode" = NULL,
    "areaCode" = NULL
WHERE LOWER("email") = 'admin@acaretek.vn'
  AND "role" = 'ADMIN';

UPDATE "User"
SET "role" = 'ADMIN_ACARE',
    "workScopeType" = COALESCE(NULLIF("workScopeType", ''), 'NATIONAL')
WHERE LOWER("role") = 'admin_acare';