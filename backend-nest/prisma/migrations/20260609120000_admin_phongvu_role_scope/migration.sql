-- Rename legacy ADMIN system role to ADMIN_PHONGVU and add super-admin feedback list feature.

UPDATE "RoleDefinition"
SET
  "code" = 'ADMIN_PHONGVU',
  "displayName" = 'Admin Phong Vũ',
  "description" = 'Quản lý user và SR thuộc Phong Vũ',
  "isSystem" = true,
  "updatedAt" = CURRENT_TIMESTAMP
WHERE "code" = 'ADMIN'
  AND NOT EXISTS (
    SELECT 1 FROM "RoleDefinition" WHERE "code" = 'ADMIN_PHONGVU'
  );

INSERT INTO "RoleDefinition" ("id", "code", "displayName", "description", "isSystem", "createdAt", "updatedAt")
VALUES (
  'role-admin-phongvu',
  'ADMIN_PHONGVU',
  'Admin Phong Vũ',
  'Quản lý user và SR thuộc Phong Vũ',
  true,
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
)
ON CONFLICT ("code") DO UPDATE SET
  "displayName" = EXCLUDED."displayName",
  "description" = EXCLUDED."description",
  "isSystem" = true,
  "updatedAt" = CURRENT_TIMESTAMP;

UPDATE "User"
SET "role" = 'ADMIN_PHONGVU'
WHERE "role" = 'ADMIN';

UPDATE "AdminPolicyRule"
SET "systemRole" = 'ADMIN_PHONGVU', "updatedAt" = CURRENT_TIMESTAMP
WHERE "systemRole" = 'ADMIN';

UPDATE "FeatureAccessRule"
SET "systemRole" = 'ADMIN_PHONGVU', "updatedAt" = CURRENT_TIMESTAMP
WHERE "systemRole" = 'ADMIN';

DELETE FROM "RoleDefinition"
WHERE "code" = 'ADMIN';

INSERT INTO "FeatureDefinition" (
  "id", "code", "displayName", "description", "parentCode", "sortOrder",
  "visibleInUserPicker", "isSystem", "isActive", "createdAt", "updatedAt"
)
VALUES (
  'feature-admin-feedback',
  'ADMIN_FEEDBACK',
  'Danh sách phản hồi',
  'Xem danh sách phản hồi nội bộ',
  'ADMIN',
  90,
  false,
  true,
  true,
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
)
ON CONFLICT ("code") DO UPDATE SET
  "displayName" = EXCLUDED."displayName",
  "description" = EXCLUDED."description",
  "parentCode" = EXCLUDED."parentCode",
  "sortOrder" = EXCLUDED."sortOrder",
  "visibleInUserPicker" = false,
  "isSystem" = true,
  "isActive" = true,
  "updatedAt" = CURRENT_TIMESTAMP;

INSERT INTO "AdminPolicyDefinition" (
  "id", "code", "displayName", "description", "category", "defaultAllowed", "isSystem", "isActive", "createdAt", "updatedAt"
)
VALUES (
  'policy-admin-feedback',
  'ADMIN_FEEDBACK',
  'Danh sách phản hồi',
  'Xem danh sách phản hồi nội bộ',
  'FEATURE',
  false,
  true,
  true,
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
)
ON CONFLICT ("code") DO UPDATE SET
  "displayName" = EXCLUDED."displayName",
  "description" = EXCLUDED."description",
  "category" = EXCLUDED."category",
  "defaultAllowed" = false,
  "isSystem" = true,
  "isActive" = true,
  "updatedAt" = CURRENT_TIMESTAMP;

INSERT INTO "AdminPolicyRule" (
  "id", "policyCode", "allowed", "systemRole", "note", "isSystem", "createdAt", "updatedAt"
)
VALUES (
  'rule-admin-feedback-super',
  'ADMIN_FEEDBACK',
  true,
  'SUPER_ADMIN',
  'Only SUPER_ADMIN may list feedback',
  true,
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
)
ON CONFLICT ("id") DO UPDATE SET
  "policyCode" = EXCLUDED."policyCode",
  "allowed" = true,
  "systemRole" = 'SUPER_ADMIN',
  "note" = EXCLUDED."note",
  "isSystem" = true,
  "updatedAt" = CURRENT_TIMESTAMP;

UPDATE "OrganizationNode"
SET "parentId" = 'org-domain-acaretek-vn', "updatedAt" = CURRENT_TIMESTAMP
WHERE "code" = 'STORE_AC001'
  AND EXISTS (
    SELECT 1 FROM "OrganizationNode" WHERE "id" = 'org-domain-acaretek-vn'
  );

UPDATE "Store" AS s
SET "organizationNodeId" = n."id", "updatedAt" = CURRENT_TIMESTAMP
FROM "OrganizationNode" AS n
WHERE s."storeId" = 'AC001'
  AND n."code" = 'STORE_AC001';
