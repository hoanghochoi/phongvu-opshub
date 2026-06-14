-- Tree-only organization domain migration. Keeps legacy region/area/store columns as release shim.

ALTER TABLE "OrganizationNode" ADD COLUMN "businessCode" TEXT;
ALTER TABLE "OrganizationNode" ADD COLUMN "abbreviation" TEXT;
ALTER TABLE "OrganizationNode" ADD COLUMN "description" TEXT;

CREATE INDEX "OrganizationNode_businessCode_idx" ON "OrganizationNode"("businessCode");

ALTER TABLE "FeatureAccessRule" ADD COLUMN "organizationNodeId" TEXT;
CREATE INDEX "FeatureAccessRule_organizationNodeId_idx" ON "FeatureAccessRule"("organizationNodeId");
ALTER TABLE "FeatureAccessRule" ADD CONSTRAINT "FeatureAccessRule_organizationNodeId_fkey"
  FOREIGN KEY ("organizationNodeId") REFERENCES "OrganizationNode"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "AdminPolicyRule" ADD COLUMN "organizationNodeId" TEXT;
CREATE INDEX "AdminPolicyRule_organizationNodeId_idx" ON "AdminPolicyRule"("organizationNodeId");
ALTER TABLE "AdminPolicyRule" ADD CONSTRAINT "AdminPolicyRule_organizationNodeId_fkey"
  FOREIGN KEY ("organizationNodeId") REFERENCES "OrganizationNode"("id") ON DELETE SET NULL ON UPDATE CASCADE;

UPDATE "OrganizationNode"
SET
  "businessCode" = COALESCE("businessCode", replace("code", 'DOMAIN_', '')),
  "abbreviation" = COALESCE("abbreviation", "displayName"),
  "description" = COALESCE("description", "displayName"),
  "updatedAt" = CURRENT_TIMESTAMP
WHERE "type" IN ('ROOT_DOMAIN', 'SUBDOMAIN');

INSERT INTO "OrganizationNode" (
  "id", "code", "businessCode", "displayName", "abbreviation", "description", "type", "parentId",
  "emailDomain", "loginAllowed", "isSystem", "isActive", "sortOrder", "createdAt", "updatedAt"
)
VALUES (
  'org-subdomain-phongvu-vn',
  'SUBDOMAIN_PHONGVU_VN',
  'phongvu.vn',
  'Phong Vũ',
  'PV',
  'Legacy Phong Vũ operation tree bucket',
  'SUBDOMAIN',
  'org-domain-phongvu-vn',
  NULL,
  false,
  true,
  true,
  10000,
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
)
ON CONFLICT ("code") DO UPDATE SET
  "businessCode" = EXCLUDED."businessCode",
  "displayName" = EXCLUDED."displayName",
  "abbreviation" = EXCLUDED."abbreviation",
  "description" = EXCLUDED."description",
  "type" = 'SUBDOMAIN',
  "parentId" = EXCLUDED."parentId",
  "emailDomain" = NULL,
  "loginAllowed" = false,
  "isSystem" = true,
  "isActive" = true,
  "sortOrder" = EXCLUDED."sortOrder",
  "updatedAt" = CURRENT_TIMESTAMP;

INSERT INTO "OrganizationNode" (
  "id", "code", "businessCode", "displayName", "abbreviation", "description", "type", "parentId",
  "emailDomain", "loginAllowed", "isSystem", "isActive", "sortOrder", "createdAt", "updatedAt"
)
SELECT
  'org-region-phongvu-' || lower(regexp_replace(r."code", '[^A-Za-z0-9]+', '-', 'g')),
  'REGION_PHONGVU_' || regexp_replace(upper(r."code"), '[^A-Z0-9]+', '_', 'g'),
  r."code",
  r."displayName",
  r."abbreviation",
  r."description",
  'REGION',
  'org-subdomain-phongvu-vn',
  NULL,
  false,
  r."isSystem",
  r."isActive",
  10100,
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
FROM "RegionDefinition" r
ON CONFLICT ("code") DO UPDATE SET
  "businessCode" = EXCLUDED."businessCode",
  "displayName" = EXCLUDED."displayName",
  "abbreviation" = EXCLUDED."abbreviation",
  "description" = EXCLUDED."description",
  "type" = 'REGION',
  "parentId" = EXCLUDED."parentId",
  "isActive" = EXCLUDED."isActive",
  "updatedAt" = CURRENT_TIMESTAMP;

INSERT INTO "OrganizationNode" (
  "id", "code", "businessCode", "displayName", "abbreviation", "description", "type", "parentId",
  "emailDomain", "loginAllowed", "isSystem", "isActive", "sortOrder", "createdAt", "updatedAt"
)
SELECT
  'org-area-phongvu-' || lower(regexp_replace(a."code", '[^A-Za-z0-9]+', '-', 'g')),
  'AREA_PHONGVU_' || regexp_replace(upper(a."code"), '[^A-Z0-9]+', '_', 'g'),
  a."code",
  a."displayName",
  a."abbreviation",
  a."description",
  'AREA',
  rn."id",
  NULL,
  false,
  a."isSystem",
  a."isActive",
  10200,
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
FROM "AreaDefinition" a
JOIN "RegionDefinition" r ON r."code" = a."regionCode"
JOIN "OrganizationNode" rn ON rn."code" = 'REGION_PHONGVU_' || regexp_replace(upper(r."code"), '[^A-Z0-9]+', '_', 'g')
ON CONFLICT ("code") DO UPDATE SET
  "businessCode" = EXCLUDED."businessCode",
  "displayName" = EXCLUDED."displayName",
  "abbreviation" = EXCLUDED."abbreviation",
  "description" = EXCLUDED."description",
  "type" = 'AREA',
  "parentId" = EXCLUDED."parentId",
  "isActive" = EXCLUDED."isActive",
  "updatedAt" = CURRENT_TIMESTAMP;

INSERT INTO "OrganizationNode" (
  "id", "code", "businessCode", "displayName", "abbreviation", "description", "type", "parentId",
  "emailDomain", "loginAllowed", "isSystem", "isActive", "sortOrder", "createdAt", "updatedAt"
)
SELECT
  'org-region-acare-' || lower(regexp_replace(r."code", '[^A-Za-z0-9]+', '-', 'g')),
  'REGION_ACARE_' || regexp_replace(upper(r."code"), '[^A-Z0-9]+', '_', 'g'),
  r."code",
  r."displayName",
  r."abbreviation",
  r."description",
  'REGION',
  'org-domain-acaretek-vn',
  NULL,
  false,
  r."isSystem",
  r."isActive",
  20100,
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
FROM "RegionDefinition" r
WHERE EXISTS (
  SELECT 1
  FROM "AreaDefinition" a
  JOIN "Store" s ON s."areaCode" = a."code"
  WHERE a."regionCode" = r."code" AND upper(s."storeId") LIKE 'AC%'
)
ON CONFLICT ("code") DO UPDATE SET
  "businessCode" = EXCLUDED."businessCode",
  "displayName" = EXCLUDED."displayName",
  "abbreviation" = EXCLUDED."abbreviation",
  "description" = EXCLUDED."description",
  "type" = 'REGION',
  "parentId" = EXCLUDED."parentId",
  "isActive" = EXCLUDED."isActive",
  "updatedAt" = CURRENT_TIMESTAMP;

INSERT INTO "OrganizationNode" (
  "id", "code", "businessCode", "displayName", "abbreviation", "description", "type", "parentId",
  "emailDomain", "loginAllowed", "isSystem", "isActive", "sortOrder", "createdAt", "updatedAt"
)
SELECT DISTINCT
  'org-area-acare-' || lower(regexp_replace(a."code", '[^A-Za-z0-9]+', '-', 'g')),
  'AREA_ACARE_' || regexp_replace(upper(a."code"), '[^A-Z0-9]+', '_', 'g'),
  a."code",
  a."displayName",
  a."abbreviation",
  a."description",
  'AREA',
  rn."id",
  NULL,
  false,
  a."isSystem",
  a."isActive",
  20200,
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
FROM "AreaDefinition" a
JOIN "RegionDefinition" r ON r."code" = a."regionCode"
JOIN "OrganizationNode" rn ON rn."code" = 'REGION_ACARE_' || regexp_replace(upper(r."code"), '[^A-Z0-9]+', '_', 'g')
JOIN "Store" s ON s."areaCode" = a."code" AND upper(s."storeId") LIKE 'AC%'
ON CONFLICT ("code") DO UPDATE SET
  "businessCode" = EXCLUDED."businessCode",
  "displayName" = EXCLUDED."displayName",
  "abbreviation" = EXCLUDED."abbreviation",
  "description" = EXCLUDED."description",
  "type" = 'AREA',
  "parentId" = EXCLUDED."parentId",
  "isActive" = EXCLUDED."isActive",
  "updatedAt" = CURRENT_TIMESTAMP;

UPDATE "RegionDefinition" r
SET "organizationNodeId" = n."id", "updatedAt" = CURRENT_TIMESTAMP
FROM "OrganizationNode" n
WHERE n."code" = 'REGION_PHONGVU_' || regexp_replace(upper(r."code"), '[^A-Z0-9]+', '_', 'g');

UPDATE "AreaDefinition" a
SET "organizationNodeId" = n."id", "updatedAt" = CURRENT_TIMESTAMP
FROM "OrganizationNode" n
WHERE n."code" = 'AREA_PHONGVU_' || regexp_replace(upper(a."code"), '[^A-Z0-9]+', '_', 'g');

INSERT INTO "OrganizationNode" (
  "id", "code", "businessCode", "displayName", "abbreviation", "description", "type", "parentId",
  "emailDomain", "loginAllowed", "isSystem", "isActive", "sortOrder", "createdAt", "updatedAt"
)
SELECT
  'org-store-' || lower(regexp_replace(s."storeId", '[^A-Za-z0-9]+', '-', 'g')),
  'STORE_' || regexp_replace(upper(s."storeId"), '[^A-Z0-9]+', '_', 'g'),
  s."storeId",
  s."storeName",
  s."storeId",
  s."storeName",
  'SHOWROOM',
  COALESCE(an_acare."id", an_pv."id", 'org-subdomain-phongvu-vn'),
  NULL,
  false,
  false,
  true,
  CASE WHEN upper(s."storeId") LIKE 'AC%' THEN 20300 ELSE 10300 END,
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
FROM "Store" s
LEFT JOIN "AreaDefinition" a ON a."code" = s."areaCode"
LEFT JOIN "OrganizationNode" an_acare ON an_acare."code" = 'AREA_ACARE_' || regexp_replace(upper(a."code"), '[^A-Z0-9]+', '_', 'g')
LEFT JOIN "OrganizationNode" an_pv ON an_pv."code" = 'AREA_PHONGVU_' || regexp_replace(upper(a."code"), '[^A-Z0-9]+', '_', 'g')
ON CONFLICT ("code") DO UPDATE SET
  "businessCode" = EXCLUDED."businessCode",
  "displayName" = EXCLUDED."displayName",
  "abbreviation" = EXCLUDED."abbreviation",
  "description" = EXCLUDED."description",
  "type" = 'SHOWROOM',
  "parentId" = EXCLUDED."parentId",
  "isActive" = true,
  "updatedAt" = CURRENT_TIMESTAMP;

UPDATE "Store" s
SET "organizationNodeId" = n."id", "updatedAt" = CURRENT_TIMESTAMP
FROM "OrganizationNode" n
WHERE n."code" = 'STORE_' || regexp_replace(upper(s."storeId"), '[^A-Z0-9]+', '_', 'g');

UPDATE "User" u
SET "organizationNodeId" = s."organizationNodeId",
    "updatedAt" = CURRENT_TIMESTAMP
FROM "Store" s
WHERE u."storeId" = s."id"
  AND s."organizationNodeId" IS NOT NULL;

UPDATE "User" u
SET "organizationNodeId" = a."organizationNodeId",
    "updatedAt" = CURRENT_TIMESTAMP
FROM "AreaDefinition" a
WHERE u."storeId" IS NULL
  AND u."areaCode" = a."code"
  AND a."organizationNodeId" IS NOT NULL;

UPDATE "User" u
SET "organizationNodeId" = r."organizationNodeId",
    "updatedAt" = CURRENT_TIMESTAMP
FROM "RegionDefinition" r
WHERE u."storeId" IS NULL
  AND u."areaCode" IS NULL
  AND u."regionCode" = r."code"
  AND r."organizationNodeId" IS NOT NULL;

UPDATE "FeatureAccessRule" f
SET "organizationNodeId" = s."organizationNodeId",
    "updatedAt" = CURRENT_TIMESTAMP
FROM "Store" s
WHERE f."storeCode" = s."storeId"
  AND s."organizationNodeId" IS NOT NULL;

UPDATE "FeatureAccessRule" f
SET "organizationNodeId" = a."organizationNodeId",
    "updatedAt" = CURRENT_TIMESTAMP
FROM "AreaDefinition" a
WHERE f."storeCode" IS NULL
  AND f."areaCode" = a."code"
  AND a."organizationNodeId" IS NOT NULL;

UPDATE "FeatureAccessRule" f
SET "organizationNodeId" = r."organizationNodeId",
    "updatedAt" = CURRENT_TIMESTAMP
FROM "RegionDefinition" r
WHERE f."storeCode" IS NULL
  AND f."areaCode" IS NULL
  AND f."regionCode" = r."code"
  AND r."organizationNodeId" IS NOT NULL;

UPDATE "AdminPolicyRule" p
SET "organizationNodeId" = s."organizationNodeId",
    "updatedAt" = CURRENT_TIMESTAMP
FROM "Store" s
WHERE p."storeCode" = s."storeId"
  AND s."organizationNodeId" IS NOT NULL;

UPDATE "AdminPolicyRule" p
SET "organizationNodeId" = a."organizationNodeId",
    "updatedAt" = CURRENT_TIMESTAMP
FROM "AreaDefinition" a
WHERE p."storeCode" IS NULL
  AND p."areaCode" = a."code"
  AND a."organizationNodeId" IS NOT NULL;

UPDATE "AdminPolicyRule" p
SET "organizationNodeId" = r."organizationNodeId",
    "updatedAt" = CURRENT_TIMESTAMP
FROM "RegionDefinition" r
WHERE p."storeCode" IS NULL
  AND p."areaCode" IS NULL
  AND p."regionCode" = r."code"
  AND r."organizationNodeId" IS NOT NULL;
