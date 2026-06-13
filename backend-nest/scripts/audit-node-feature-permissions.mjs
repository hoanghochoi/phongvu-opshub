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

  const result = {
    ok: orphanedUsers.length === 0 && divergentGroups.length === 0,
    generatedAt: new Date().toISOString(),
    orphanedUsers,
    divergentGroups,
    nextStep:
      orphanedUsers.length === 0 && divergentGroups.length === 0
        ? 'Safe to run the node feature assignment migration.'
        : 'Resolve these groups before running the node feature assignment migration.',
  };

  console.log(JSON.stringify(result, jsonReplacer, 2));
  if (!result.ok) process.exitCode = 2;
} finally {
  await close();
}
