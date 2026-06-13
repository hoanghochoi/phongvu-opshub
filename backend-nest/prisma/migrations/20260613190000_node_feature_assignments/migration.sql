-- Node-group feature assignments. The preflight blocks unsafe migration from
-- per-user allowlists when a node group contains divergent feature sets.
-- Users that still have legacy per-user features but no active direct
-- organization node are reported by the audit script and skipped from backfill,
-- because runtime node-based feature access already denies them.

DO $$
DECLARE
  blocking_groups INTEGER := 0;
BEGIN
  WITH RECURSIVE ancestors AS (
    SELECT
      n."id" AS "nodeId",
      n."id" AS "ancestorId",
      n."parentId",
      n."type",
      0 AS "depth"
    FROM "OrganizationNode" n
    WHERE n."isActive" = true

    UNION ALL

    SELECT
      a."nodeId",
      p."id" AS "ancestorId",
      p."parentId",
      p."type",
      a."depth" + 1 AS "depth"
    FROM ancestors a
    JOIN "OrganizationNode" p ON p."id" = a."parentId"
    WHERE a."depth" < 50
      AND p."isActive" = true
  ),
  roots AS (
    SELECT DISTINCT ON ("nodeId")
      "nodeId",
      "ancestorId" AS "scopeRootNodeId"
    FROM ancestors
    WHERE "parentId" IS NULL OR upper("type") IN ('LV0_DOMAIN', 'ROOT_DOMAIN')
    ORDER BY "nodeId", "depth" DESC
  ),
  user_groups AS (
    SELECT
      u."id" AS "userId",
      roots."scopeRootNodeId",
      CASE upper(n."type")
        WHEN 'ROOT_DOMAIN' THEN 'LV0_DOMAIN'
        WHEN 'BLOCK' THEN 'LV1_BLOCK'
        WHEN 'DEPARTMENT' THEN 'LV2_DEPARTMENT'
        WHEN 'REGION' THEN 'LV2_REGION'
        WHEN 'AREA' THEN 'LV3_AREA'
        WHEN 'VIRTUAL_SCOPE' THEN 'LV3_UNIT'
        WHEN 'SHOWROOM' THEN 'LV4_STORE'
        WHEN 'JOB_ROLE' THEN 'LV5_POSITION'
        ELSE upper(n."type")
      END AS "nodeType",
      upper(coalesce(nullif(trim(n."businessCode"), ''), n."code")) AS "nodeKey"
    FROM "User" u
    JOIN "OrganizationNode" n ON n."id" = u."organizationNodeId"
    JOIN roots ON roots."nodeId" = n."id"
    WHERE upper(u."role") <> 'SUPER_ADMIN'
      AND n."isActive" = true
  ),
  feature_sets AS (
    SELECT
      ug."scopeRootNodeId",
      ug."nodeType",
      ug."nodeKey",
      ug."userId",
      coalesce(
        string_agg(ufa."featureCode", ',' ORDER BY ufa."featureCode")
          FILTER (WHERE ufa."featureCode" IS NOT NULL),
        ''
      ) AS "featureSet"
    FROM user_groups ug
    LEFT JOIN "UserFeatureAssignment" ufa
      ON ufa."userId" = ug."userId"
      AND ufa."enabled" = true
    GROUP BY ug."scopeRootNodeId", ug."nodeType", ug."nodeKey", ug."userId"
  ),
  divergent_groups AS (
    SELECT
      "scopeRootNodeId",
      "nodeType",
      "nodeKey"
    FROM feature_sets
    GROUP BY "scopeRootNodeId", "nodeType", "nodeKey"
    HAVING COUNT(DISTINCT "featureSet") > 1
  )
  SELECT COUNT(*)
  INTO blocking_groups
  FROM divergent_groups;

  IF blocking_groups > 0 THEN
    RAISE EXCEPTION 'NODE_FEATURE_ASSIGNMENT_PREFLIGHT_FAILED: % node groups contain divergent per-user feature sets. Run scripts/audit-node-feature-permissions.mjs for details.', blocking_groups;
  END IF;
END $$;

CREATE TABLE "OrganizationNodeFeatureAssignment" (
  "id" TEXT NOT NULL,
  "scopeRootNodeId" TEXT NOT NULL,
  "nodeType" TEXT NOT NULL,
  "nodeKey" TEXT NOT NULL,
  "featureCode" TEXT NOT NULL,
  "enabled" BOOLEAN NOT NULL DEFAULT true,
  "assignedById" TEXT,
  "note" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "OrganizationNodeFeatureAssignment_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "OrganizationNodeFeatureAssignment_scopeRootNodeId_nodeType_nodeKey_featureCode_key"
  ON "OrganizationNodeFeatureAssignment"("scopeRootNodeId", "nodeType", "nodeKey", "featureCode");
CREATE INDEX "OrganizationNodeFeatureAssignment_scopeRootNodeId_idx"
  ON "OrganizationNodeFeatureAssignment"("scopeRootNodeId");
CREATE INDEX "OrganizationNodeFeatureAssignment_nodeType_nodeKey_idx"
  ON "OrganizationNodeFeatureAssignment"("nodeType", "nodeKey");
CREATE INDEX "OrganizationNodeFeatureAssignment_featureCode_idx"
  ON "OrganizationNodeFeatureAssignment"("featureCode");
CREATE INDEX "OrganizationNodeFeatureAssignment_enabled_idx"
  ON "OrganizationNodeFeatureAssignment"("enabled");
CREATE INDEX "OrganizationNodeFeatureAssignment_assignedById_idx"
  ON "OrganizationNodeFeatureAssignment"("assignedById");

ALTER TABLE "OrganizationNodeFeatureAssignment" ADD CONSTRAINT "OrganizationNodeFeatureAssignment_scopeRootNodeId_fkey"
  FOREIGN KEY ("scopeRootNodeId") REFERENCES "OrganizationNode"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "OrganizationNodeFeatureAssignment" ADD CONSTRAINT "OrganizationNodeFeatureAssignment_featureCode_fkey"
  FOREIGN KEY ("featureCode") REFERENCES "FeatureDefinition"("code") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "OrganizationNodeFeatureAssignment" ADD CONSTRAINT "OrganizationNodeFeatureAssignment_assignedById_fkey"
  FOREIGN KEY ("assignedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

WITH RECURSIVE ancestors AS (
  SELECT
    n."id" AS "nodeId",
    n."id" AS "ancestorId",
    n."parentId",
    n."type",
    0 AS "depth"
  FROM "OrganizationNode" n
  WHERE n."isActive" = true

  UNION ALL

  SELECT
    a."nodeId",
    p."id" AS "ancestorId",
    p."parentId",
    p."type",
    a."depth" + 1 AS "depth"
  FROM ancestors a
  JOIN "OrganizationNode" p ON p."id" = a."parentId"
  WHERE a."depth" < 50
    AND p."isActive" = true
),
roots AS (
  SELECT DISTINCT ON ("nodeId")
    "nodeId",
    "ancestorId" AS "scopeRootNodeId"
  FROM ancestors
  WHERE "parentId" IS NULL OR upper("type") IN ('LV0_DOMAIN', 'ROOT_DOMAIN')
  ORDER BY "nodeId", "depth" DESC
),
node_features AS (
  SELECT DISTINCT
    roots."scopeRootNodeId",
    CASE upper(n."type")
      WHEN 'ROOT_DOMAIN' THEN 'LV0_DOMAIN'
      WHEN 'BLOCK' THEN 'LV1_BLOCK'
      WHEN 'DEPARTMENT' THEN 'LV2_DEPARTMENT'
      WHEN 'REGION' THEN 'LV2_REGION'
      WHEN 'AREA' THEN 'LV3_AREA'
      WHEN 'VIRTUAL_SCOPE' THEN 'LV3_UNIT'
      WHEN 'SHOWROOM' THEN 'LV4_STORE'
      WHEN 'JOB_ROLE' THEN 'LV5_POSITION'
      ELSE upper(n."type")
    END AS "nodeType",
    upper(coalesce(nullif(trim(n."businessCode"), ''), n."code")) AS "nodeKey",
    ufa."featureCode"
  FROM "User" u
  JOIN "OrganizationNode" n ON n."id" = u."organizationNodeId"
  JOIN roots ON roots."nodeId" = n."id"
  JOIN "UserFeatureAssignment" ufa ON ufa."userId" = u."id" AND ufa."enabled" = true
  WHERE upper(u."role") <> 'SUPER_ADMIN'
    AND n."isActive" = true
)
INSERT INTO "OrganizationNodeFeatureAssignment" (
  "id", "scopeRootNodeId", "nodeType", "nodeKey", "featureCode", "enabled",
  "assignedById", "note", "createdAt", "updatedAt"
)
SELECT
  'node-feature-' || md5("scopeRootNodeId" || ':' || "nodeType" || ':' || "nodeKey" || ':' || "featureCode"),
  "scopeRootNodeId",
  "nodeType",
  "nodeKey",
  "featureCode",
  true,
  NULL,
  'Backfilled from per-user feature assignments',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
FROM node_features
ON CONFLICT ("scopeRootNodeId", "nodeType", "nodeKey", "featureCode") DO UPDATE SET
  "enabled" = true,
  "updatedAt" = CURRENT_TIMESTAMP;
