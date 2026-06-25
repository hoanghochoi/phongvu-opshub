import { createPrismaClient } from './prisma-local.mjs';

const { prisma, close } = createPrismaClient();

function jsonReplacer(_key, value) {
  return typeof value === 'bigint' ? Number(value) : value;
}

try {
  const orphanedUsers = await prisma.$queryRawUnsafe(`
    SELECT
      u."id" AS "userId",
      u."role",
      u."organizationNodeId",
      coalesce(
        string_agg(ufa."featureCode", ',' ORDER BY ufa."featureCode")
          FILTER (WHERE ufa."featureCode" IS NOT NULL),
        ''
      ) AS "featureSet"
    FROM "User" u
    JOIN "UserFeatureAssignment" ufa
      ON ufa."userId" = u."id"
      AND ufa."enabled" = true
    LEFT JOIN "OrganizationNode" n ON n."id" = u."organizationNodeId"
    WHERE upper(u."role") <> 'SUPER_ADMIN'
      AND (
        u."organizationNodeId" IS NULL
        OR n."id" IS NULL
        OR n."isActive" = false
      )
    GROUP BY u."id", u."role", u."organizationNodeId"
    ORDER BY u."role", u."id"
    LIMIT 200;
  `);

  const divergentGroups = await prisma.$queryRawUnsafe(`
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
        root."displayName" AS "scopeRootName",
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
      JOIN "OrganizationNode" root ON root."id" = roots."scopeRootNodeId"
      WHERE upper(u."role") <> 'SUPER_ADMIN'
        AND n."isActive" = true
    ),
    feature_sets AS (
      SELECT
        ug."scopeRootNodeId",
        ug."scopeRootName",
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
      GROUP BY
        ug."scopeRootNodeId",
        ug."scopeRootName",
        ug."nodeType",
        ug."nodeKey",
        ug."userId"
    ),
    feature_set_counts AS (
      SELECT
        "scopeRootNodeId",
        "scopeRootName",
        "nodeType",
        "nodeKey",
        "featureSet",
        COUNT(*) AS "userCount"
      FROM feature_sets
      GROUP BY
        "scopeRootNodeId",
        "scopeRootName",
        "nodeType",
        "nodeKey",
        "featureSet"
    ),
    divergent_groups AS (
      SELECT
        "scopeRootNodeId",
        "scopeRootName",
        "nodeType",
        "nodeKey",
        SUM("userCount") AS "totalUsers",
        COUNT(*) AS "featureSetCount",
        jsonb_agg(
          jsonb_build_object(
            'featureSet',
            "featureSet",
            'userCount',
            "userCount"
          )
          ORDER BY "userCount" DESC, "featureSet"
        ) AS "featureSets"
      FROM feature_set_counts
      GROUP BY
        "scopeRootNodeId",
        "scopeRootName",
        "nodeType",
        "nodeKey"
      HAVING COUNT(*) > 1
    )
    SELECT *
    FROM divergent_groups
    ORDER BY "totalUsers" DESC, "featureSetCount" DESC, "nodeType", "nodeKey"
    LIMIT 200;
  `);

  const ancestorGateViolations = await prisma.$queryRawUnsafe(`
    WITH RECURSIVE ancestors AS (
      SELECT
        n."id" AS "nodeId",
        n."id" AS "ancestorId",
        n."parentId",
        n."type",
        n."code",
        n."businessCode",
        0 AS "depth"
      FROM "OrganizationNode" n
      WHERE n."isActive" = true

      UNION ALL

      SELECT
        a."nodeId",
        p."id" AS "ancestorId",
        p."parentId",
        p."type",
        p."code",
        p."businessCode",
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
    normalized_nodes AS (
      SELECT
        n."id",
        n."displayName",
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
      FROM "OrganizationNode" n
      JOIN roots ON roots."nodeId" = n."id"
      WHERE n."isActive" = true
    ),
    enabled_assignments AS (
      SELECT
        a."id",
        a."scopeRootNodeId",
        a."nodeType",
        a."nodeKey",
        a."featureCode"
      FROM "OrganizationNodeFeatureAssignment" a
      WHERE a."enabled" = true
    ),
    assigned_concrete_nodes AS (
      SELECT
        a."id" AS "assignmentId",
        a."scopeRootNodeId",
        root."displayName" AS "scopeRootName",
        a."nodeType",
        a."nodeKey",
        a."featureCode",
        f."displayName" AS "featureName",
        n."id" AS "concreteNodeId",
        n."displayName" AS "concreteNodeName"
      FROM enabled_assignments a
      JOIN normalized_nodes nn
        ON nn."scopeRootNodeId" = a."scopeRootNodeId"
        AND nn."nodeType" = a."nodeType"
        AND nn."nodeKey" = a."nodeKey"
      JOIN "OrganizationNode" n ON n."id" = nn."id"
      JOIN "OrganizationNode" root ON root."id" = a."scopeRootNodeId"
      LEFT JOIN "FeatureDefinition" f ON f."code" = a."featureCode"
    ),
    required_parent_groups AS (
      SELECT
        acn."assignmentId",
        acn."scopeRootNodeId",
        acn."scopeRootName",
        acn."nodeType",
        acn."nodeKey",
        acn."featureCode",
        acn."featureName",
        acn."concreteNodeId",
        acn."concreteNodeName",
        pa."ancestorId" AS "missingParentNodeId",
        CASE upper(pa."type")
          WHEN 'ROOT_DOMAIN' THEN 'LV0_DOMAIN'
          WHEN 'BLOCK' THEN 'LV1_BLOCK'
          WHEN 'DEPARTMENT' THEN 'LV2_DEPARTMENT'
          WHEN 'REGION' THEN 'LV2_REGION'
          WHEN 'AREA' THEN 'LV3_AREA'
          WHEN 'VIRTUAL_SCOPE' THEN 'LV3_UNIT'
          WHEN 'SHOWROOM' THEN 'LV4_STORE'
          WHEN 'JOB_ROLE' THEN 'LV5_POSITION'
          ELSE upper(pa."type")
        END AS "missingParentNodeType",
        upper(coalesce(nullif(trim(pa."businessCode"), ''), pa."code")) AS "missingParentNodeKey"
      FROM assigned_concrete_nodes acn
      JOIN ancestors pa ON pa."nodeId" = acn."concreteNodeId"
      WHERE pa."depth" > 0
        AND CASE upper(pa."type")
          WHEN 'ROOT_DOMAIN' THEN 'LV0_DOMAIN'
          WHEN 'BLOCK' THEN 'LV1_BLOCK'
          WHEN 'DEPARTMENT' THEN 'LV2_DEPARTMENT'
          WHEN 'REGION' THEN 'LV2_REGION'
          WHEN 'AREA' THEN 'LV3_AREA'
          WHEN 'VIRTUAL_SCOPE' THEN 'LV3_UNIT'
          WHEN 'SHOWROOM' THEN 'LV4_STORE'
          WHEN 'JOB_ROLE' THEN 'LV5_POSITION'
          ELSE upper(pa."type")
        END <> 'LV0_DOMAIN'
    ),
    missing_parent_groups AS (
      SELECT rpg.*
      FROM required_parent_groups rpg
      LEFT JOIN enabled_assignments parent_assignment
        ON parent_assignment."scopeRootNodeId" = rpg."scopeRootNodeId"
        AND parent_assignment."nodeType" = rpg."missingParentNodeType"
        AND parent_assignment."nodeKey" = rpg."missingParentNodeKey"
        AND parent_assignment."featureCode" = rpg."featureCode"
      WHERE parent_assignment."id" IS NULL
    ),
    ranked_missing_parent_groups AS (
      SELECT
        mpg.*,
        row_number() OVER (
          PARTITION BY
            mpg."scopeRootNodeId",
            mpg."featureCode",
            mpg."nodeType",
            mpg."nodeKey",
            mpg."missingParentNodeType",
            mpg."missingParentNodeKey"
          ORDER BY mpg."concreteNodeName", mpg."concreteNodeId"
        ) AS "sampleRank"
      FROM missing_parent_groups mpg
    )
    SELECT
      mpg."scopeRootNodeId",
      mpg."scopeRootName",
      mpg."featureCode",
      coalesce(mpg."featureName", mpg."featureCode") AS "featureName",
      mpg."nodeType",
      mpg."nodeKey",
      mpg."missingParentNodeType",
      mpg."missingParentNodeKey",
      COUNT(DISTINCT mpg."concreteNodeId") AS "concreteNodeCount",
      COUNT(DISTINCT u."id") AS "impactedUserCount",
      jsonb_agg(
        DISTINCT jsonb_build_object(
          'nodeId', mpg."concreteNodeId",
          'nodeName', mpg."concreteNodeName",
          'missingParentNodeId', mpg."missingParentNodeId"
        )
      ) FILTER (WHERE mpg."sampleRank" <= 10) AS "sampleNodes"
    FROM ranked_missing_parent_groups mpg
    LEFT JOIN "User" u
      ON u."organizationNodeId" = mpg."concreteNodeId"
      AND upper(u."role") <> 'SUPER_ADMIN'
    GROUP BY
      mpg."scopeRootNodeId",
      mpg."scopeRootName",
      mpg."featureCode",
      mpg."featureName",
      mpg."nodeType",
      mpg."nodeKey",
      mpg."missingParentNodeType",
      mpg."missingParentNodeKey"
    ORDER BY "impactedUserCount" DESC, "featureCode", "nodeType", "nodeKey"
    LIMIT 500;
  `);

  const result = {
    ok: divergentGroups.length === 0 && ancestorGateViolations.length === 0,
    generatedAt: new Date().toISOString(),
    orphanedUsers,
    divergentGroups,
    ancestorGateViolations,
    nextStep:
      divergentGroups.length === 0
        ? ancestorGateViolations.length === 0
          ? orphanedUsers.length === 0
            ? 'Safe to run the node feature assignment migration and org parent feature veto rollout.'
            : 'Safe to run the migration and org parent feature veto rollout after reviewing orphaned users; they will be skipped from backfill until they regain an active direct organization node.'
          : 'Resolve ancestorGateViolations before deploying org parent feature veto; missing parent assignments will block child feature access.'
        : 'Resolve divergent node groups before running the node feature assignment migration.',
  };

  console.log(JSON.stringify(result, jsonReplacer, 2));
  if (divergentGroups.length > 0 || ancestorGateViolations.length > 0) {
    process.exitCode = 2;
  }
} finally {
  await close();
}
