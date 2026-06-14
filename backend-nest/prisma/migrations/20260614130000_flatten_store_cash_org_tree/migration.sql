-- Flatten active organization data to Lv0 -> Lv4 store -> Lv5 position.
-- Existing store users are assigned to the CASH Lv5 position of their own store
-- so payment-speaker access keeps working after legacy Lv1-Lv3 nodes are removed.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM "OrganizationNode"
    WHERE "code" = 'DOMAIN_ACARE_VN'
      AND "id" <> 'org-domain-acare-vn'
      AND EXISTS (
        SELECT 1 FROM "OrganizationNode" existing
        WHERE existing."id" = 'org-domain-acare-vn'
      )
  ) THEN
    RAISE EXCEPTION 'Cannot canonicalize acare.vn root because DOMAIN_ACARE_VN and org-domain-acare-vn are different existing nodes';
  END IF;
END $$;

UPDATE "OrganizationNode"
SET "id" = 'org-domain-acare-vn',
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "code" = 'DOMAIN_ACARE_VN'
  AND "id" <> 'org-domain-acare-vn'
  AND NOT EXISTS (
    SELECT 1 FROM "OrganizationNode" existing
    WHERE existing."id" = 'org-domain-acare-vn'
  );

INSERT INTO "OrganizationNode" (
  "id",
  "code",
  "displayName",
  "businessCode",
  "abbreviation",
  "description",
  "type",
  "parentId",
  "emailDomain",
  "loginAllowed",
  "isSystem",
  "isActive",
  "sortOrder",
  "createdAt",
  "updatedAt"
)
VALUES
  (
    'org-domain-phongvu-vn',
    'DOMAIN_PHONGVU_VN',
    'phongvu.vn',
    'phongvu.vn',
    'PV',
    'Domain dang nhap Phong Vu',
    'LV0_DOMAIN',
    NULL,
    'phongvu.vn',
    true,
    true,
    true,
    10,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  ),
  (
    'org-domain-acare-vn',
    'DOMAIN_ACARE_VN',
    'acare.vn',
    'ACARE_VN',
    'ACARE',
    'Domain dang nhap A Care',
    'LV0_DOMAIN',
    NULL,
    'acare.vn',
    true,
    true,
    true,
    20,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  )
ON CONFLICT ("id") DO UPDATE SET
  "code" = EXCLUDED."code",
  "displayName" = EXCLUDED."displayName",
  "businessCode" = EXCLUDED."businessCode",
  "abbreviation" = EXCLUDED."abbreviation",
  "description" = EXCLUDED."description",
  "type" = EXCLUDED."type",
  "parentId" = NULL,
  "emailDomain" = EXCLUDED."emailDomain",
  "loginAllowed" = true,
  "isSystem" = true,
  "isActive" = true,
  "sortOrder" = EXCLUDED."sortOrder",
  "updatedAt" = CURRENT_TIMESTAMP;

UPDATE "OrganizationNode"
SET "type" = CASE "type"
    WHEN 'ROOT_DOMAIN' THEN 'LV0_DOMAIN'
    WHEN 'SHOWROOM' THEN 'LV4_STORE'
    WHEN 'JOB_ROLE' THEN 'LV5_POSITION'
    ELSE "type"
  END,
  "updatedAt" = CURRENT_TIMESTAMP
WHERE "type" IN ('ROOT_DOMAIN', 'SHOWROOM', 'JOB_ROLE');

UPDATE "OrganizationNode" child
SET "parentId" = 'org-domain-acare-vn',
    "updatedAt" = CURRENT_TIMESTAMP
WHERE child."parentId" = 'org-domain-acaretek-vn'
  AND child."id" <> 'org-domain-acare-vn';

UPDATE "User"
SET "organizationNodeId" = 'org-domain-acare-vn',
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "organizationNodeId" = 'org-domain-acaretek-vn';

UPDATE "Store"
SET "organizationNodeId" = 'org-domain-acare-vn',
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "organizationNodeId" = 'org-domain-acaretek-vn';

UPDATE "DepartmentDefinition"
SET "organizationNodeId" = 'org-domain-acare-vn',
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "organizationNodeId" = 'org-domain-acaretek-vn';

UPDATE "JobRoleDefinition"
SET "organizationNodeId" = 'org-domain-acare-vn',
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "organizationNodeId" = 'org-domain-acaretek-vn';

WITH job_role_definitions("id", "code", "displayName", "description", "departmentCode") AS (
  VALUES
    ('job-role-store-manager', 'STORE_MANAGER', 'Store Manager', 'Quản lý SR hoặc bộ phận', 'MANAGEMENT'),
    ('job-role-sa', 'SA', 'Nhân viên Bán hàng', 'Vị trí bán hàng tại cửa hàng', 'SALES'),
    ('job-role-technician', 'TECHNICIAN', 'Technician', 'Nhân viên kỹ thuật', 'TECHNICAL'),
    ('job-role-cash', 'CASH', 'Nhân viên Thu ngân', 'Vị trí thu ngân tại cửa hàng', 'CASHIER'),
    ('job-role-warehouse', 'WAREHOUSE', 'Warehouse Staff', 'Nhân viên kho', 'WAREHOUSE')
)
INSERT INTO "JobRoleDefinition" (
  "id",
  "code",
  "displayName",
  "description",
  "departmentCode",
  "isSystem",
  "isActive",
  "createdAt",
  "updatedAt"
)
SELECT
  "id",
  "code",
  "displayName",
  "description",
  "departmentCode",
  true,
  true,
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
FROM job_role_definitions
ON CONFLICT ("code") DO UPDATE SET
  "displayName" = EXCLUDED."displayName",
  "description" = EXCLUDED."description",
  "departmentCode" = EXCLUDED."departmentCode",
  "isSystem" = true,
  "isActive" = true,
  "updatedAt" = CURRENT_TIMESTAMP;

UPDATE "RegionDefinition"
SET "organizationNodeId" = 'org-domain-acare-vn',
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "organizationNodeId" = 'org-domain-acaretek-vn';

UPDATE "AreaDefinition"
SET "organizationNodeId" = 'org-domain-acare-vn',
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "organizationNodeId" = 'org-domain-acaretek-vn';

UPDATE "FeatureAccessRule"
SET "organizationNodeId" = 'org-domain-acare-vn',
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "organizationNodeId" = 'org-domain-acaretek-vn';

UPDATE "AdminPolicyRule"
SET "organizationNodeId" = 'org-domain-acare-vn',
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "organizationNodeId" = 'org-domain-acaretek-vn';

DELETE FROM "OrganizationNodeFeatureAssignment" legacy_assignment
USING "OrganizationNodeFeatureAssignment" canonical_assignment
WHERE legacy_assignment."scopeRootNodeId" = 'org-domain-acaretek-vn'
  AND canonical_assignment."scopeRootNodeId" = 'org-domain-acare-vn'
  AND canonical_assignment."nodeType" = legacy_assignment."nodeType"
  AND canonical_assignment."nodeKey" = legacy_assignment."nodeKey"
  AND canonical_assignment."featureCode" = legacy_assignment."featureCode";

UPDATE "OrganizationNodeFeatureAssignment"
SET "scopeRootNodeId" = 'org-domain-acare-vn',
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "scopeRootNodeId" = 'org-domain-acaretek-vn';

DELETE FROM "OrganizationNode"
WHERE "id" = 'org-domain-acaretek-vn';

CREATE TEMP TABLE "__StoreOrgTarget" AS
SELECT
  store."id" AS "storeUuid",
  store."storeId" AS "storeCode",
  store."storeName" AS "storeName",
  regexp_replace(upper(trim(store."storeId")), '[^A-Z0-9]+', '_', 'g') AS "safeStoreCode",
  CASE
    WHEN upper(trim(store."storeId")) LIKE 'AC%'
      OR upper(trim(store."storeId")) LIKE 'AP%'
      OR upper(COALESCE(store."areaCode", '')) = 'ACARE'
      OR lower(COALESCE(store."storeName", '')) LIKE 'acare%'
      OR lower(COALESCE(area."code", '')) LIKE '%acare%'
      OR lower(COALESCE(area."displayName", '')) LIKE '%acare%'
      OR lower(COALESCE(region."code", '')) LIKE '%acare%'
      OR lower(COALESCE(region."displayName", '')) LIKE '%acare%'
      THEN 'org-domain-acare-vn'
    ELSE 'org-domain-phongvu-vn'
  END AS "rootId"
FROM "Store" store
LEFT JOIN "AreaDefinition" area ON area."code" = store."areaCode"
LEFT JOIN "RegionDefinition" region ON region."code" = area."regionCode"
WHERE trim(COALESCE(store."storeId", '')) <> '';

INSERT INTO "OrganizationNode" (
  "id",
  "code",
  "displayName",
  "businessCode",
  "abbreviation",
  "description",
  "type",
  "parentId",
  "emailDomain",
  "loginAllowed",
  "isSystem",
  "isActive",
  "sortOrder",
  "createdAt",
  "updatedAt"
)
SELECT
  'org-store-' || lower(replace(target."safeStoreCode", '_', '-')),
  'STORE_' || target."safeStoreCode",
  COALESCE(NULLIF(trim(target."storeName"), ''), target."storeCode"),
  target."storeCode",
  target."storeCode",
  COALESCE(NULLIF(trim(target."storeName"), ''), target."storeCode"),
  'LV4_STORE',
  target."rootId",
  NULL,
  false,
  false,
  true,
  CASE WHEN target."rootId" = 'org-domain-acare-vn' THEN 20300 ELSE 10300 END,
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
FROM "__StoreOrgTarget" target
ON CONFLICT ("code") DO UPDATE SET
  "displayName" = EXCLUDED."displayName",
  "businessCode" = EXCLUDED."businessCode",
  "abbreviation" = EXCLUDED."abbreviation",
  "description" = EXCLUDED."description",
  "type" = 'LV4_STORE',
  "parentId" = EXCLUDED."parentId",
  "emailDomain" = NULL,
  "loginAllowed" = false,
  "isSystem" = false,
  "isActive" = true,
  "sortOrder" = EXCLUDED."sortOrder",
  "updatedAt" = CURRENT_TIMESTAMP;

UPDATE "OrganizationNode" node
SET "parentId" = CASE
      WHEN upper(COALESCE(node."businessCode", node."code", '')) LIKE 'AC%'
        OR upper(COALESCE(node."businessCode", node."code", '')) LIKE 'AP%'
        THEN 'org-domain-acare-vn'
      ELSE 'org-domain-phongvu-vn'
    END,
    "type" = 'LV4_STORE',
    "updatedAt" = CURRENT_TIMESTAMP
WHERE node."type" IN ('LV4_STORE', 'SHOWROOM')
  AND node."parentId" NOT IN ('org-domain-phongvu-vn', 'org-domain-acare-vn');

UPDATE "Store" store
SET "organizationNodeId" = node."id",
    "updatedAt" = CURRENT_TIMESTAMP
FROM "__StoreOrgTarget" target
JOIN "OrganizationNode" node ON node."code" = 'STORE_' || target."safeStoreCode"
WHERE store."id" = target."storeUuid";

WITH position_definitions("suffix", "businessCode", "displayName", "description", "sortOrder") AS (
  VALUES
    ('STORE_MANAGER', 'STORE_MANAGER', 'Quản lý Cửa hàng', 'Vị trí quản lý cửa hàng', 10),
    ('SA', 'SA', 'Nhân viên Bán hàng', 'Vị trí bán hàng tại cửa hàng', 20),
    ('TECHNICIAN', 'TECHNICIAN', 'Kỹ thuật viên', 'Vị trí kỹ thuật tại cửa hàng', 30),
    ('CASH', 'CASH', 'Nhân viên Thu ngân', 'Vị trí thu ngân tại cửa hàng', 40),
    ('WAREHOUSE', 'WAREHOUSE', 'Nhân viên Kho', 'Vị trí kho tại cửa hàng', 50)
), store_nodes AS (
  SELECT
    node."id" AS "storeNodeId",
    regexp_replace(upper(trim(COALESCE(node."businessCode", replace(node."code", 'STORE_', '')))), '[^A-Z0-9]+', '_', 'g') AS "safeStoreCode",
    node."isActive" AS "storeIsActive"
  FROM "OrganizationNode" node
  WHERE node."type" = 'LV4_STORE'
    AND node."parentId" IN ('org-domain-phongvu-vn', 'org-domain-acare-vn')
)
INSERT INTO "OrganizationNode" (
  "id",
  "code",
  "displayName",
  "businessCode",
  "abbreviation",
  "description",
  "type",
  "parentId",
  "emailDomain",
  "loginAllowed",
  "isSystem",
  "isActive",
  "sortOrder",
  "createdAt",
  "updatedAt"
)
SELECT
  store_nodes."storeNodeId" || '-pos-' || lower(replace(position_definitions."suffix", '_', '-')),
  'STORE_' || store_nodes."safeStoreCode" || '_POS_' || position_definitions."suffix",
  position_definitions."displayName",
  position_definitions."businessCode",
  position_definitions."businessCode",
  position_definitions."description",
  'LV5_POSITION',
  store_nodes."storeNodeId",
  NULL,
  false,
  true,
  store_nodes."storeIsActive",
  position_definitions."sortOrder",
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
FROM store_nodes
CROSS JOIN position_definitions
ON CONFLICT ("code") DO UPDATE SET
  "displayName" = EXCLUDED."displayName",
  "businessCode" = EXCLUDED."businessCode",
  "abbreviation" = EXCLUDED."abbreviation",
  "description" = EXCLUDED."description",
  "type" = 'LV5_POSITION',
  "parentId" = EXCLUDED."parentId",
  "emailDomain" = NULL,
  "loginAllowed" = false,
  "isSystem" = true,
  "isActive" = EXCLUDED."isActive",
  "sortOrder" = EXCLUDED."sortOrder",
  "updatedAt" = CURRENT_TIMESTAMP;

WITH cash_feature_codes AS (
  SELECT DISTINCT
    target."rootId" AS "scopeRootNodeId",
    ufa."featureCode"
  FROM "User" user_item
  JOIN "Store" store ON store."id" = user_item."storeId"
  JOIN "__StoreOrgTarget" target ON target."storeUuid" = store."id"
  JOIN "UserFeatureAssignment" ufa
    ON ufa."userId" = user_item."id"
    AND ufa."enabled" = true
  JOIN "FeatureDefinition" feature
    ON feature."code" = ufa."featureCode"
    AND feature."isActive" = true
  WHERE upper(COALESCE(user_item."role", '')) <> 'SUPER_ADMIN'

  UNION

  SELECT DISTINCT
    target."rootId" AS "scopeRootNodeId",
    assignment."featureCode"
  FROM "__StoreOrgTarget" target
  JOIN "OrganizationNodeFeatureAssignment" assignment
    ON assignment."scopeRootNodeId" = target."rootId"
    AND assignment."nodeType" = 'LV4_STORE'
    AND assignment."nodeKey" = upper(trim(target."storeCode"))
    AND assignment."enabled" = true
  JOIN "FeatureDefinition" feature
    ON feature."code" = assignment."featureCode"
    AND feature."isActive" = true

  UNION

  SELECT DISTINCT
    assignment."scopeRootNodeId",
    assignment."featureCode"
  FROM "OrganizationNodeFeatureAssignment" assignment
  JOIN "FeatureDefinition" feature
    ON feature."code" = assignment."featureCode"
    AND feature."isActive" = true
  WHERE assignment."nodeType" = 'LV5_POSITION'
    AND assignment."nodeKey" = 'CASH'
    AND assignment."enabled" = true
    AND assignment."scopeRootNodeId" IN (
      'org-domain-phongvu-vn',
      'org-domain-acare-vn'
    )
)
INSERT INTO "OrganizationNodeFeatureAssignment" (
  "id",
  "scopeRootNodeId",
  "nodeType",
  "nodeKey",
  "featureCode",
  "enabled",
  "assignedById",
  "note",
  "createdAt",
  "updatedAt"
)
SELECT
  'node-feature-' || md5(
    cash_feature_codes."scopeRootNodeId" || ':LV5_POSITION:CASH:' || cash_feature_codes."featureCode"
  ),
  cash_feature_codes."scopeRootNodeId",
  'LV5_POSITION',
  'CASH',
  cash_feature_codes."featureCode",
  true,
  NULL,
  'Backfilled for store users moved to CASH during Lv4/Lv5 flattening',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
FROM cash_feature_codes
ON CONFLICT ("scopeRootNodeId", "nodeType", "nodeKey", "featureCode") DO UPDATE SET
  "enabled" = true,
  "note" = EXCLUDED."note",
  "updatedAt" = CURRENT_TIMESTAMP;

DELETE FROM "OrganizationNodeFeatureAssignment"
WHERE upper("nodeType") IN (
  'SUBDOMAIN',
  'LV1_BLOCK',
  'LV2_DEPARTMENT',
  'LV2_REGION',
  'LV3_AREA',
  'LV3_UNIT',
  'BLOCK',
  'DEPARTMENT',
  'REGION',
  'AREA',
  'VIRTUAL_SCOPE'
);

WITH user_store_targets AS (
  SELECT
    user_item."id" AS "userId",
    target."safeStoreCode",
    1 AS "priority"
  FROM "User" user_item
  JOIN "Store" store ON store."id" = user_item."storeId"
  JOIN "__StoreOrgTarget" target ON target."storeUuid" = store."id"

  UNION ALL

  SELECT
    user_item."id" AS "userId",
    target."safeStoreCode",
    2 AS "priority"
  FROM "User" user_item
  JOIN "OrganizationNode" current_node
    ON current_node."id" = user_item."organizationNodeId"
  LEFT JOIN "OrganizationNode" parent_node
    ON parent_node."id" = current_node."parentId"
  JOIN "OrganizationNode" store_node
    ON store_node."id" = CASE
      WHEN current_node."type" IN ('LV4_STORE', 'SHOWROOM')
        THEN current_node."id"
      WHEN current_node."type" IN ('LV5_POSITION', 'JOB_ROLE')
        AND parent_node."type" IN ('LV4_STORE', 'SHOWROOM')
        THEN parent_node."id"
      ELSE NULL
    END
  JOIN "Store" store ON store."organizationNodeId" = store_node."id"
  JOIN "__StoreOrgTarget" target ON target."storeUuid" = store."id"
  WHERE user_item."storeId" IS NULL
), ranked_user_store_targets AS (
  SELECT DISTINCT ON ("userId")
    "userId",
    "safeStoreCode"
  FROM user_store_targets
  ORDER BY "userId", "priority"
)
UPDATE "User" user_item
SET "organizationNodeId" = cash_node."id",
    "jobRoleCode" = 'CASH',
    "workScopeType" = 'STORE',
    "regionCode" = NULL,
    "areaCode" = NULL,
    "updatedAt" = CURRENT_TIMESTAMP
FROM ranked_user_store_targets target
JOIN "OrganizationNode" cash_node
  ON cash_node."code" = 'STORE_' || target."safeStoreCode" || '_POS_CASH'
WHERE user_item."id" = target."userId";

CREATE TEMP TABLE "__ResetOrganizationNodes" AS
SELECT node."id"
FROM "OrganizationNode" node
LEFT JOIN "OrganizationNode" parent ON parent."id" = node."parentId"
WHERE node."type" IN (
    'SUBDOMAIN',
    'LV1_BLOCK',
    'LV2_DEPARTMENT',
    'LV2_REGION',
    'LV3_AREA',
    'LV3_UNIT',
    'BLOCK',
    'DEPARTMENT',
    'REGION',
    'AREA',
    'VIRTUAL_SCOPE'
  )
  OR (
    node."type" IN ('LV5_POSITION', 'JOB_ROLE')
    AND COALESCE(parent."type", '') NOT IN ('LV4_STORE', 'SHOWROOM')
  );

UPDATE "OrganizationNode" child
SET "parentId" = CASE
      WHEN upper(COALESCE(child."businessCode", child."code", '')) LIKE 'AC%'
        OR upper(COALESCE(child."businessCode", child."code", '')) LIKE 'AP%'
        THEN 'org-domain-acare-vn'
      ELSE 'org-domain-phongvu-vn'
    END,
    "updatedAt" = CURRENT_TIMESTAMP
WHERE child."id" NOT IN (SELECT "id" FROM "__ResetOrganizationNodes")
  AND child."parentId" IN (SELECT "id" FROM "__ResetOrganizationNodes")
  AND child."type" = 'LV4_STORE';

UPDATE "User"
SET "organizationNodeId" = NULL,
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "organizationNodeId" IN (SELECT "id" FROM "__ResetOrganizationNodes");

UPDATE "Store"
SET "organizationNodeId" = NULL,
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "organizationNodeId" IN (SELECT "id" FROM "__ResetOrganizationNodes");

UPDATE "DepartmentDefinition"
SET "organizationNodeId" = NULL,
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "organizationNodeId" IN (SELECT "id" FROM "__ResetOrganizationNodes");

UPDATE "JobRoleDefinition"
SET "organizationNodeId" = NULL,
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "organizationNodeId" IN (SELECT "id" FROM "__ResetOrganizationNodes");

UPDATE "RegionDefinition"
SET "organizationNodeId" = NULL,
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "organizationNodeId" IN (SELECT "id" FROM "__ResetOrganizationNodes");

UPDATE "AreaDefinition"
SET "organizationNodeId" = NULL,
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "organizationNodeId" IN (SELECT "id" FROM "__ResetOrganizationNodes");

UPDATE "FeatureAccessRule"
SET "organizationNodeId" = NULL,
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "organizationNodeId" IN (SELECT "id" FROM "__ResetOrganizationNodes");

UPDATE "AdminPolicyRule"
SET "organizationNodeId" = NULL,
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "organizationNodeId" IN (SELECT "id" FROM "__ResetOrganizationNodes");

DELETE FROM "OrganizationNodeFeatureAssignment"
WHERE "scopeRootNodeId" IN (SELECT "id" FROM "__ResetOrganizationNodes");

DELETE FROM "OrganizationNode"
WHERE "id" IN (SELECT "id" FROM "__ResetOrganizationNodes")
  AND "type" IN ('LV5_POSITION', 'JOB_ROLE');

DELETE FROM "OrganizationNode"
WHERE "id" IN (SELECT "id" FROM "__ResetOrganizationNodes")
  AND "type" IN ('LV3_AREA', 'LV3_UNIT', 'AREA', 'VIRTUAL_SCOPE');

DELETE FROM "OrganizationNode"
WHERE "id" IN (SELECT "id" FROM "__ResetOrganizationNodes")
  AND "type" IN ('LV2_DEPARTMENT', 'LV2_REGION', 'DEPARTMENT', 'REGION');

DELETE FROM "OrganizationNode"
WHERE "id" IN (SELECT "id" FROM "__ResetOrganizationNodes")
  AND "type" IN ('LV1_BLOCK', 'BLOCK');

DELETE FROM "OrganizationNode"
WHERE "id" IN (SELECT "id" FROM "__ResetOrganizationNodes")
  AND "type" = 'SUBDOMAIN';

DROP TABLE "__ResetOrganizationNodes";
DROP TABLE "__StoreOrgTarget";
