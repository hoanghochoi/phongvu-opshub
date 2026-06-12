-- Move organization administration to Lv0-Lv5 tree and canonical system roles.
-- Store/SR runtime data is preserved; legacy region/area/store columns remain as compatibility shims.

ALTER TABLE "User" ALTER COLUMN "role" SET DEFAULT 'USER';

INSERT INTO "RoleDefinition" ("id", "code", "displayName", "description", "isSystem", "createdAt", "updatedAt")
VALUES
  ('role-super-admin', 'SUPER_ADMIN', 'Super Admin', 'Toàn quyền hệ thống', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('role-admin', 'ADMIN', 'Admin', 'Quản trị theo phạm vi cây tổ chức', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('role-user', 'USER', 'User', 'Quyền thao tác hằng ngày', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT ("code") DO UPDATE SET
  "displayName" = EXCLUDED."displayName",
  "description" = EXCLUDED."description",
  "isSystem" = true,
  "updatedAt" = CURRENT_TIMESTAMP;

UPDATE "User"
SET "role" = CASE
    WHEN "role" = 'SUPER_ADMIN' THEN 'SUPER_ADMIN'
    WHEN "role" IN ('ADMIN', 'ADMIN_PHONGVU', 'ADMIN_ACARE', 'MANAGER') THEN 'ADMIN'
    ELSE 'USER'
  END,
  "updatedAt" = CURRENT_TIMESTAMP
WHERE "role" IS NULL
   OR "role" NOT IN ('SUPER_ADMIN', 'ADMIN', 'USER')
   OR "role" IN ('ADMIN_PHONGVU', 'ADMIN_ACARE', 'MANAGER', 'STAFF');

UPDATE "FeatureAccessRule"
SET "systemRole" = CASE
    WHEN "systemRole" = 'SUPER_ADMIN' THEN 'SUPER_ADMIN'
    WHEN "systemRole" IN ('ADMIN', 'ADMIN_PHONGVU', 'ADMIN_ACARE', 'MANAGER') THEN 'ADMIN'
    ELSE 'USER'
  END,
  "updatedAt" = CURRENT_TIMESTAMP
WHERE "systemRole" IS NOT NULL;

UPDATE "AdminPolicyRule"
SET "systemRole" = CASE
    WHEN "systemRole" = 'SUPER_ADMIN' THEN 'SUPER_ADMIN'
    WHEN "systemRole" IN ('ADMIN', 'ADMIN_PHONGVU', 'ADMIN_ACARE', 'MANAGER') THEN 'ADMIN'
    ELSE 'USER'
  END,
  "updatedAt" = CURRENT_TIMESTAMP
WHERE "systemRole" IS NOT NULL;

DELETE FROM "RoleDefinition"
WHERE "code" NOT IN ('SUPER_ADMIN', 'ADMIN', 'USER');

UPDATE "OrganizationNode"
SET "type" = CASE "type"
    WHEN 'ROOT_DOMAIN' THEN 'LV0_DOMAIN'
    WHEN 'BLOCK' THEN 'LV1_BLOCK'
    WHEN 'DEPARTMENT' THEN 'LV2_DEPARTMENT'
    WHEN 'REGION' THEN 'LV2_REGION'
    WHEN 'AREA' THEN 'LV3_AREA'
    WHEN 'VIRTUAL_SCOPE' THEN 'LV3_UNIT'
    WHEN 'SHOWROOM' THEN 'LV4_STORE'
    WHEN 'JOB_ROLE' THEN 'LV5_POSITION'
    ELSE "type"
  END,
  "updatedAt" = CURRENT_TIMESTAMP
WHERE "type" IN (
  'ROOT_DOMAIN',
  'BLOCK',
  'DEPARTMENT',
  'REGION',
  'AREA',
  'VIRTUAL_SCOPE',
  'SHOWROOM',
  'JOB_ROLE'
);

CREATE TEMP TABLE "__SubdomainRoot" AS
WITH RECURSIVE ancestors AS (
  SELECT
    child."id" AS "subdomainId",
    parent."id" AS "ancestorId",
    parent."parentId",
    parent."type",
    1 AS "depth"
  FROM "OrganizationNode" child
  LEFT JOIN "OrganizationNode" parent ON parent."id" = child."parentId"
  WHERE child."type" = 'SUBDOMAIN'
  UNION ALL
  SELECT
    ancestors."subdomainId",
    parent."id" AS "ancestorId",
    parent."parentId",
    parent."type",
    ancestors."depth" + 1
  FROM ancestors
  JOIN "OrganizationNode" parent ON parent."id" = ancestors."parentId"
  WHERE ancestors."depth" < 50
), nearest_root AS (
  SELECT DISTINCT ON ("subdomainId")
    "subdomainId",
    "ancestorId" AS "rootId"
  FROM ancestors
  WHERE "type" IN ('LV0_DOMAIN', 'ROOT_DOMAIN')
  ORDER BY "subdomainId", "depth" ASC
)
SELECT
  subdomain."id" AS "subdomainId",
  COALESCE(
    nearest_root."rootId",
    CASE
      WHEN lower(COALESCE(subdomain."emailDomain", '')) = 'acare.vn' THEN 'org-domain-acaretek-vn'
      ELSE 'org-domain-phongvu-vn'
    END
  ) AS "rootId"
FROM "OrganizationNode" subdomain
LEFT JOIN nearest_root ON nearest_root."subdomainId" = subdomain."id"
WHERE subdomain."type" = 'SUBDOMAIN';

UPDATE "OrganizationNode" child
SET "parentId" = subdomain_root."rootId",
    "updatedAt" = CURRENT_TIMESTAMP
FROM "__SubdomainRoot" subdomain_root
WHERE child."parentId" = subdomain_root."subdomainId"
  AND child."id" <> subdomain_root."rootId"
  AND EXISTS (
    SELECT 1 FROM "OrganizationNode" root WHERE root."id" = subdomain_root."rootId"
  );

UPDATE "User" item
SET "organizationNodeId" = subdomain_root."rootId",
    "updatedAt" = CURRENT_TIMESTAMP
FROM "__SubdomainRoot" subdomain_root
WHERE item."organizationNodeId" = subdomain_root."subdomainId"
  AND EXISTS (
    SELECT 1 FROM "OrganizationNode" root WHERE root."id" = subdomain_root."rootId"
  );

UPDATE "Store" item
SET "organizationNodeId" = subdomain_root."rootId",
    "updatedAt" = CURRENT_TIMESTAMP
FROM "__SubdomainRoot" subdomain_root
WHERE item."organizationNodeId" = subdomain_root."subdomainId"
  AND EXISTS (
    SELECT 1 FROM "OrganizationNode" root WHERE root."id" = subdomain_root."rootId"
  );

UPDATE "DepartmentDefinition" item
SET "organizationNodeId" = subdomain_root."rootId",
    "updatedAt" = CURRENT_TIMESTAMP
FROM "__SubdomainRoot" subdomain_root
WHERE item."organizationNodeId" = subdomain_root."subdomainId"
  AND EXISTS (
    SELECT 1 FROM "OrganizationNode" root WHERE root."id" = subdomain_root."rootId"
  );

UPDATE "JobRoleDefinition" item
SET "organizationNodeId" = subdomain_root."rootId",
    "updatedAt" = CURRENT_TIMESTAMP
FROM "__SubdomainRoot" subdomain_root
WHERE item."organizationNodeId" = subdomain_root."subdomainId"
  AND EXISTS (
    SELECT 1 FROM "OrganizationNode" root WHERE root."id" = subdomain_root."rootId"
  );

UPDATE "RegionDefinition" item
SET "organizationNodeId" = subdomain_root."rootId",
    "updatedAt" = CURRENT_TIMESTAMP
FROM "__SubdomainRoot" subdomain_root
WHERE item."organizationNodeId" = subdomain_root."subdomainId"
  AND EXISTS (
    SELECT 1 FROM "OrganizationNode" root WHERE root."id" = subdomain_root."rootId"
  );

UPDATE "AreaDefinition" item
SET "organizationNodeId" = subdomain_root."rootId",
    "updatedAt" = CURRENT_TIMESTAMP
FROM "__SubdomainRoot" subdomain_root
WHERE item."organizationNodeId" = subdomain_root."subdomainId"
  AND EXISTS (
    SELECT 1 FROM "OrganizationNode" root WHERE root."id" = subdomain_root."rootId"
  );

UPDATE "FeatureAccessRule" item
SET "organizationNodeId" = subdomain_root."rootId",
    "updatedAt" = CURRENT_TIMESTAMP
FROM "__SubdomainRoot" subdomain_root
WHERE item."organizationNodeId" = subdomain_root."subdomainId"
  AND EXISTS (
    SELECT 1 FROM "OrganizationNode" root WHERE root."id" = subdomain_root."rootId"
  );

UPDATE "AdminPolicyRule" item
SET "organizationNodeId" = subdomain_root."rootId",
    "updatedAt" = CURRENT_TIMESTAMP
FROM "__SubdomainRoot" subdomain_root
WHERE item."organizationNodeId" = subdomain_root."subdomainId"
  AND EXISTS (
    SELECT 1 FROM "OrganizationNode" root WHERE root."id" = subdomain_root."rootId"
  );

UPDATE "OrganizationNode" subdomain
SET "isActive" = false,
    "loginAllowed" = false,
    "metadata" = COALESCE(subdomain."metadata", '{}'::jsonb) ||
      jsonb_build_object(
        'retiredReason', 'subdomain_merged_to_lv0',
        'mergedIntoNodeId', subdomain_root."rootId",
        'retiredAt', CURRENT_TIMESTAMP
      ),
    "updatedAt" = CURRENT_TIMESTAMP
FROM "__SubdomainRoot" subdomain_root
WHERE subdomain."id" = subdomain_root."subdomainId";

DROP TABLE "__SubdomainRoot";

UPDATE "FeatureDefinition"
SET "displayName" = 'Cơ cấu tổ chức',
    "description" = 'Quản lý cây tổ chức Lv0-Lv5',
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "code" = 'ADMIN_REGIONS';
