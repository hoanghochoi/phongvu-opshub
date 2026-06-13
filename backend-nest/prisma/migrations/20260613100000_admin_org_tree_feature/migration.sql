INSERT INTO "FeatureDefinition" (
  "id", "code", "displayName", "description", "parentCode", "sortOrder",
  "visibleInUserPicker", "isSystem", "isActive", "createdAt", "updatedAt"
)
VALUES (
  'feature-admin-org-tree',
  'ADMIN_ORG_TREE',
  'Cơ cấu tổ chức',
  'Quản lý cây tổ chức Lv0-Lv5',
  'ADMIN',
  40,
  true,
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
  "visibleInUserPicker" = true,
  "isSystem" = true,
  "isActive" = true,
  "updatedAt" = CURRENT_TIMESTAMP;

UPDATE "FeatureDefinition"
SET "displayName" = CASE "code"
      WHEN 'ADMIN_STORES' THEN 'Legacy SR'
      WHEN 'ADMIN_REGIONS' THEN 'Legacy Vùng/Miền'
      WHEN 'ADMIN_PERSONNEL' THEN 'Legacy nhân sự'
      ELSE "displayName"
    END,
    "description" = CASE "code"
      WHEN 'ADMIN_STORES' THEN 'Legacy: đã thay bằng Cơ cấu tổ chức'
      WHEN 'ADMIN_REGIONS' THEN 'Legacy: đã thay bằng Cơ cấu tổ chức'
      WHEN 'ADMIN_PERSONNEL' THEN 'Legacy: phòng ban/chức danh được quản lý qua cây tổ chức'
      ELSE "description"
    END,
    "visibleInUserPicker" = false,
    "parentCode" = 'ADMIN',
    "sortOrder" = CASE "code"
      WHEN 'ADMIN_STORES' THEN 900
      WHEN 'ADMIN_REGIONS' THEN 901
      WHEN 'ADMIN_PERSONNEL' THEN 902
      ELSE "sortOrder"
    END,
    "isSystem" = true,
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "code" IN ('ADMIN_STORES', 'ADMIN_REGIONS', 'ADMIN_PERSONNEL');

INSERT INTO "AdminPolicyDefinition" (
  "id", "code", "displayName", "description", "category",
  "defaultAllowed", "isSystem", "isActive", "createdAt", "updatedAt"
)
VALUES (
  'policy-admin-org-tree',
  'ADMIN_ORG_TREE',
  'Cơ cấu tổ chức',
  'Quản lý cây tổ chức Lv0-Lv5',
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

UPDATE "AdminPolicyDefinition"
SET "displayName" = CASE "code"
      WHEN 'ADMIN_STORES' THEN 'Legacy SR'
      WHEN 'ADMIN_REGIONS' THEN 'Legacy Vùng/Miền'
      WHEN 'ADMIN_PERSONNEL' THEN 'Legacy nhân sự'
      ELSE "displayName"
    END,
    "description" = CASE "code"
      WHEN 'ADMIN_STORES' THEN 'Legacy: đã thay bằng Cơ cấu tổ chức'
      WHEN 'ADMIN_REGIONS' THEN 'Legacy: đã thay bằng Cơ cấu tổ chức'
      WHEN 'ADMIN_PERSONNEL' THEN 'Legacy: phòng ban/chức danh được quản lý qua cây tổ chức'
      ELSE "description"
    END,
    "isActive" = false,
    "isSystem" = true,
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "code" IN ('ADMIN_STORES', 'ADMIN_REGIONS', 'ADMIN_PERSONNEL');

INSERT INTO "UserFeatureAssignment" (
  "id", "userId", "featureCode", "enabled", "assignedById", "note",
  "createdAt", "updatedAt"
)
SELECT
  'user-feature-admin-org-tree-' || source."userId",
  source."userId",
  'ADMIN_ORG_TREE',
  true,
  source."assignedById",
  COALESCE(source."note", 'Backfill from ADMIN_REGIONS'),
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
FROM "UserFeatureAssignment" source
WHERE source."featureCode" = 'ADMIN_REGIONS'
  AND source."enabled" = true
ON CONFLICT ("userId", "featureCode") DO UPDATE SET
  "enabled" = true,
  "updatedAt" = CURRENT_TIMESTAMP;

INSERT INTO "FeatureAccessRule" (
  "id", "featureCode", "enabled", "emailDomain", "systemRole",
  "departmentCode", "jobRoleCode", "workScopeType", "regionCode", "areaCode",
  "organizationNodeId", "storeCode", "userId", "note", "createdAt", "updatedAt"
)
SELECT
  'feature-rule-admin-org-tree-' || source."id",
  'ADMIN_ORG_TREE',
  source."enabled",
  source."emailDomain",
  source."systemRole",
  source."departmentCode",
  source."jobRoleCode",
  source."workScopeType",
  source."regionCode",
  source."areaCode",
  source."organizationNodeId",
  source."storeCode",
  source."userId",
  COALESCE(source."note", 'Backfill from ADMIN_REGIONS'),
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
FROM "FeatureAccessRule" source
WHERE source."featureCode" = 'ADMIN_REGIONS'
  AND NOT EXISTS (
    SELECT 1
    FROM "FeatureAccessRule" existing
    WHERE existing."featureCode" = 'ADMIN_ORG_TREE'
      AND existing."emailDomain" IS NOT DISTINCT FROM source."emailDomain"
      AND existing."systemRole" IS NOT DISTINCT FROM source."systemRole"
      AND existing."departmentCode" IS NOT DISTINCT FROM source."departmentCode"
      AND existing."jobRoleCode" IS NOT DISTINCT FROM source."jobRoleCode"
      AND existing."workScopeType" IS NOT DISTINCT FROM source."workScopeType"
      AND existing."regionCode" IS NOT DISTINCT FROM source."regionCode"
      AND existing."areaCode" IS NOT DISTINCT FROM source."areaCode"
      AND existing."organizationNodeId" IS NOT DISTINCT FROM source."organizationNodeId"
      AND existing."storeCode" IS NOT DISTINCT FROM source."storeCode"
      AND existing."userId" IS NOT DISTINCT FROM source."userId"
  );

INSERT INTO "AdminPolicyRule" (
  "id", "policyCode", "allowed", "emailDomain", "systemRole",
  "departmentCode", "jobRoleCode", "workScopeType", "regionCode", "areaCode",
  "organizationNodeId", "storeCode", "userId", "scopeContains", "note",
  "isSystem", "createdAt", "updatedAt"
)
SELECT
  'policy-rule-admin-org-tree-' || source."id",
  'ADMIN_ORG_TREE',
  source."allowed",
  source."emailDomain",
  source."systemRole",
  source."departmentCode",
  source."jobRoleCode",
  source."workScopeType",
  source."regionCode",
  source."areaCode",
  source."organizationNodeId",
  source."storeCode",
  source."userId",
  source."scopeContains",
  COALESCE(source."note", 'Backfill from ADMIN_REGIONS'),
  source."isSystem",
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
FROM "AdminPolicyRule" source
WHERE source."policyCode" = 'ADMIN_REGIONS'
  AND NOT EXISTS (
    SELECT 1
    FROM "AdminPolicyRule" existing
    WHERE existing."policyCode" = 'ADMIN_ORG_TREE'
      AND existing."emailDomain" IS NOT DISTINCT FROM source."emailDomain"
      AND existing."systemRole" IS NOT DISTINCT FROM source."systemRole"
      AND existing."departmentCode" IS NOT DISTINCT FROM source."departmentCode"
      AND existing."jobRoleCode" IS NOT DISTINCT FROM source."jobRoleCode"
      AND existing."workScopeType" IS NOT DISTINCT FROM source."workScopeType"
      AND existing."regionCode" IS NOT DISTINCT FROM source."regionCode"
      AND existing."areaCode" IS NOT DISTINCT FROM source."areaCode"
      AND existing."organizationNodeId" IS NOT DISTINCT FROM source."organizationNodeId"
      AND existing."storeCode" IS NOT DISTINCT FROM source."storeCode"
      AND existing."userId" IS NOT DISTINCT FROM source."userId"
      AND existing."scopeContains" IS NOT DISTINCT FROM source."scopeContains"
  );

INSERT INTO "AdminPolicyRule" (
  "id", "policyCode", "allowed", "systemRole", "note", "isSystem",
  "createdAt", "updatedAt"
)
VALUES (
  'rule-admin-org-tree-admin-role',
  'ADMIN_ORG_TREE',
  true,
  'ADMIN',
  'Seed từ quyền Cơ cấu tổ chức',
  true,
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
)
ON CONFLICT ("id") DO UPDATE SET
  "allowed" = true,
  "updatedAt" = CURRENT_TIMESTAMP;
