-- Organization tree and strict per-user feature allowlist foundation.

CREATE TABLE "OrganizationNode" (
  "id" TEXT NOT NULL,
  "code" TEXT NOT NULL,
  "displayName" TEXT NOT NULL,
  "type" TEXT NOT NULL,
  "parentId" TEXT,
  "emailDomain" TEXT,
  "loginAllowed" BOOLEAN NOT NULL DEFAULT false,
  "isSystem" BOOLEAN NOT NULL DEFAULT false,
  "isActive" BOOLEAN NOT NULL DEFAULT true,
  "sortOrder" INTEGER NOT NULL DEFAULT 0,
  "metadata" JSONB,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "OrganizationNode_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "OrganizationNode" ADD CONSTRAINT "OrganizationNode_parentId_fkey"
  FOREIGN KEY ("parentId") REFERENCES "OrganizationNode"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

CREATE UNIQUE INDEX "OrganizationNode_code_key" ON "OrganizationNode"("code");
CREATE INDEX "OrganizationNode_parentId_idx" ON "OrganizationNode"("parentId");
CREATE INDEX "OrganizationNode_type_idx" ON "OrganizationNode"("type");
CREATE INDEX "OrganizationNode_emailDomain_idx" ON "OrganizationNode"("emailDomain");
CREATE INDEX "OrganizationNode_isActive_idx" ON "OrganizationNode"("isActive");

ALTER TABLE "Store" ADD COLUMN "organizationNodeId" TEXT;
ALTER TABLE "User" ADD COLUMN "organizationNodeId" TEXT;
ALTER TABLE "DepartmentDefinition" ADD COLUMN "organizationNodeId" TEXT;
ALTER TABLE "JobRoleDefinition" ADD COLUMN "organizationNodeId" TEXT;
ALTER TABLE "RegionDefinition" ADD COLUMN "organizationNodeId" TEXT;
ALTER TABLE "AreaDefinition" ADD COLUMN "organizationNodeId" TEXT;

CREATE INDEX "Store_organizationNodeId_idx" ON "Store"("organizationNodeId");
CREATE INDEX "User_organizationNodeId_idx" ON "User"("organizationNodeId");
CREATE INDEX "DepartmentDefinition_organizationNodeId_idx" ON "DepartmentDefinition"("organizationNodeId");
CREATE INDEX "JobRoleDefinition_organizationNodeId_idx" ON "JobRoleDefinition"("organizationNodeId");
CREATE INDEX "RegionDefinition_organizationNodeId_idx" ON "RegionDefinition"("organizationNodeId");
CREATE INDEX "AreaDefinition_organizationNodeId_idx" ON "AreaDefinition"("organizationNodeId");

ALTER TABLE "Store" ADD CONSTRAINT "Store_organizationNodeId_fkey"
  FOREIGN KEY ("organizationNodeId") REFERENCES "OrganizationNode"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "User" ADD CONSTRAINT "User_organizationNodeId_fkey"
  FOREIGN KEY ("organizationNodeId") REFERENCES "OrganizationNode"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "DepartmentDefinition" ADD CONSTRAINT "DepartmentDefinition_organizationNodeId_fkey"
  FOREIGN KEY ("organizationNodeId") REFERENCES "OrganizationNode"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "JobRoleDefinition" ADD CONSTRAINT "JobRoleDefinition_organizationNodeId_fkey"
  FOREIGN KEY ("organizationNodeId") REFERENCES "OrganizationNode"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "RegionDefinition" ADD CONSTRAINT "RegionDefinition_organizationNodeId_fkey"
  FOREIGN KEY ("organizationNodeId") REFERENCES "OrganizationNode"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "AreaDefinition" ADD CONSTRAINT "AreaDefinition_organizationNodeId_fkey"
  FOREIGN KEY ("organizationNodeId") REFERENCES "OrganizationNode"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "FeatureDefinition" ADD COLUMN "parentCode" TEXT;
ALTER TABLE "FeatureDefinition" ADD COLUMN "sortOrder" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "FeatureDefinition" ADD COLUMN "visibleInUserPicker" BOOLEAN NOT NULL DEFAULT true;
CREATE INDEX "FeatureDefinition_parentCode_idx" ON "FeatureDefinition"("parentCode");
CREATE INDEX "FeatureDefinition_visibleInUserPicker_idx" ON "FeatureDefinition"("visibleInUserPicker");

CREATE TABLE "UserFeatureAssignment" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "featureCode" TEXT NOT NULL,
  "enabled" BOOLEAN NOT NULL DEFAULT true,
  "assignedById" TEXT,
  "note" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "UserFeatureAssignment_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "UserFeatureAssignment_userId_featureCode_key" ON "UserFeatureAssignment"("userId", "featureCode");
CREATE INDEX "UserFeatureAssignment_featureCode_idx" ON "UserFeatureAssignment"("featureCode");
CREATE INDEX "UserFeatureAssignment_assignedById_idx" ON "UserFeatureAssignment"("assignedById");
CREATE INDEX "UserFeatureAssignment_enabled_idx" ON "UserFeatureAssignment"("enabled");

ALTER TABLE "UserFeatureAssignment" ADD CONSTRAINT "UserFeatureAssignment_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "UserFeatureAssignment" ADD CONSTRAINT "UserFeatureAssignment_featureCode_fkey"
  FOREIGN KEY ("featureCode") REFERENCES "FeatureDefinition"("code") ON DELETE CASCADE ON UPDATE CASCADE;

INSERT INTO "OrganizationNode" ("id", "code", "displayName", "type", "emailDomain", "loginAllowed", "isSystem", "isActive", "sortOrder") VALUES
  ('org-domain-phongvu-vn', 'DOMAIN_PHONGVU_VN', 'phongvu.vn', 'ROOT_DOMAIN', 'phongvu.vn', true, true, true, 10),
  ('org-domain-acaretek-vn', 'DOMAIN_ACARETEK_VN', 'acaretek.vn', 'ROOT_DOMAIN', 'acaretek.vn', true, true, true, 20)
ON CONFLICT ("code") DO NOTHING;

WITH user_domains AS (
  SELECT DISTINCT lower(split_part("email", '@', 2)) AS domain
  FROM "User"
  WHERE "email" LIKE '%@%'
), setting_domains AS (
  SELECT DISTINCT lower(trim(both '"' from item.value::text)) AS domain
  FROM "AdminSetting" s, jsonb_array_elements(s."value") AS item(value)
  WHERE s."key" = 'AUTH_ALLOWED_EMAIL_DOMAINS' AND jsonb_typeof(s."value") = 'array'
), all_domains AS (
  SELECT domain, true AS has_user FROM user_domains WHERE domain IS NOT NULL AND domain <> ''
  UNION
  SELECT domain, false AS has_user FROM setting_domains WHERE domain IS NOT NULL AND domain <> ''
), folded AS (
  SELECT domain, bool_or(has_user) AS has_user
  FROM all_domains
  WHERE domain NOT IN ('phongvu.vn', 'acaretek.vn', 'hoanghochoi.com')
  GROUP BY domain
)
INSERT INTO "OrganizationNode" (
  "id", "code", "displayName", "type", "parentId", "emailDomain", "loginAllowed", "isSystem", "isActive", "sortOrder", "metadata"
)
SELECT
  'org-domain-' || regexp_replace(domain, '[^a-z0-9]+', '-', 'g') AS id,
  'DOMAIN_' || upper(regexp_replace(domain, '[^a-z0-9]+', '_', 'g')) AS code,
  domain AS "displayName",
  CASE WHEN domain LIKE 'phongvu-%' THEN 'SUBDOMAIN' ELSE 'ROOT_DOMAIN' END AS type,
  CASE WHEN domain LIKE 'phongvu-%' THEN 'org-domain-phongvu-vn' ELSE NULL END AS "parentId",
  domain AS "emailDomain",
  has_user AS "loginAllowed",
  false AS "isSystem",
  has_user AS "isActive",
  100 AS "sortOrder",
  jsonb_build_object('source', CASE WHEN has_user THEN 'existing-user-domain' ELSE 'legacy-setting-domain' END) AS "metadata"
FROM folded
ON CONFLICT ("code") DO NOTHING;

INSERT INTO "OrganizationNode" ("id", "code", "displayName", "type", "parentId", "isSystem", "isActive", "sortOrder")
SELECT
  'org-region-' || lower(regexp_replace("code", '[^a-zA-Z0-9]+', '-', 'g')),
  'REGION_' || upper(regexp_replace("code", '[^a-zA-Z0-9]+', '_', 'g')),
  "displayName",
  'VIRTUAL_SCOPE',
  'org-domain-phongvu-vn',
  "isSystem",
  "isActive",
  200
FROM "RegionDefinition"
ON CONFLICT ("code") DO NOTHING;

UPDATE "RegionDefinition" r
SET "organizationNodeId" = n."id"
FROM "OrganizationNode" n
WHERE n."code" = 'REGION_' || upper(regexp_replace(r."code", '[^a-zA-Z0-9]+', '_', 'g'));

INSERT INTO "OrganizationNode" ("id", "code", "displayName", "type", "parentId", "isSystem", "isActive", "sortOrder")
SELECT
  'org-area-' || lower(regexp_replace(a."code", '[^a-zA-Z0-9]+', '-', 'g')),
  'AREA_' || upper(regexp_replace(a."code", '[^a-zA-Z0-9]+', '_', 'g')),
  a."displayName",
  'AREA',
  r."organizationNodeId",
  a."isSystem",
  a."isActive",
  300
FROM "AreaDefinition" a
LEFT JOIN "RegionDefinition" r ON r."code" = a."regionCode"
ON CONFLICT ("code") DO NOTHING;

UPDATE "AreaDefinition" a
SET "organizationNodeId" = n."id"
FROM "OrganizationNode" n
WHERE n."code" = 'AREA_' || upper(regexp_replace(a."code", '[^a-zA-Z0-9]+', '_', 'g'));

INSERT INTO "OrganizationNode" ("id", "code", "displayName", "type", "parentId", "isSystem", "isActive", "sortOrder")
SELECT
  'org-store-' || lower(regexp_replace(s."storeId", '[^a-zA-Z0-9]+', '-', 'g')),
  'STORE_' || upper(regexp_replace(s."storeId", '[^a-zA-Z0-9]+', '_', 'g')),
  s."storeId" || ' - ' || s."storeName",
  'SHOWROOM',
  a."organizationNodeId",
  false,
  true,
  400
FROM "Store" s
LEFT JOIN "AreaDefinition" a ON a."code" = s."areaCode"
ON CONFLICT ("code") DO NOTHING;

UPDATE "Store" s
SET "organizationNodeId" = n."id"
FROM "OrganizationNode" n
WHERE n."code" = 'STORE_' || upper(regexp_replace(s."storeId", '[^a-zA-Z0-9]+', '_', 'g'));

INSERT INTO "OrganizationNode" ("id", "code", "displayName", "type", "parentId", "isSystem", "isActive", "sortOrder")
SELECT
  'org-department-' || lower(regexp_replace("code", '[^a-zA-Z0-9]+', '-', 'g')),
  'DEPARTMENT_' || upper(regexp_replace("code", '[^a-zA-Z0-9]+', '_', 'g')),
  "displayName",
  'DEPARTMENT',
  'org-domain-phongvu-vn',
  "isSystem",
  "isActive",
  500
FROM "DepartmentDefinition"
ON CONFLICT ("code") DO NOTHING;

UPDATE "DepartmentDefinition" d
SET "organizationNodeId" = n."id"
FROM "OrganizationNode" n
WHERE n."code" = 'DEPARTMENT_' || upper(regexp_replace(d."code", '[^a-zA-Z0-9]+', '_', 'g'));

INSERT INTO "OrganizationNode" ("id", "code", "displayName", "type", "parentId", "isSystem", "isActive", "sortOrder")
SELECT
  'org-job-role-' || lower(regexp_replace(j."code", '[^a-zA-Z0-9]+', '-', 'g')),
  'JOB_ROLE_' || upper(regexp_replace(j."code", '[^a-zA-Z0-9]+', '_', 'g')),
  j."displayName",
  'JOB_ROLE',
  d."organizationNodeId",
  j."isSystem",
  j."isActive",
  600
FROM "JobRoleDefinition" j
LEFT JOIN "DepartmentDefinition" d ON d."code" = j."departmentCode"
ON CONFLICT ("code") DO NOTHING;

UPDATE "JobRoleDefinition" j
SET "organizationNodeId" = n."id"
FROM "OrganizationNode" n
WHERE n."code" = 'JOB_ROLE_' || upper(regexp_replace(j."code", '[^a-zA-Z0-9]+', '_', 'g'));

UPDATE "User" u
SET "organizationNodeId" = COALESCE(
  (SELECT s."organizationNodeId" FROM "Store" s WHERE s."id" = u."storeId" LIMIT 1),
  (SELECT n."id" FROM "OrganizationNode" n WHERE n."emailDomain" = lower(split_part(u."email", '@', 2)) LIMIT 1)
);
