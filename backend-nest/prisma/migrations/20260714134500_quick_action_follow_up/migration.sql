BEGIN;

INSERT INTO "FeatureDefinition" (
  "id", "code", "displayName", "description", "parentCode", "sortOrder",
  "visibleInUserPicker", "isSystem", "isActive", "createdAt", "updatedAt"
) VALUES (
  'feature-quick-action-follow-up',
  'QUICK_ACTION_FOLLOW_UP',
  'Thao tác nhanh - Chăm sóc lại',
  'Hiện lối tắt Chăm sóc lại',
  'QUICK_ACTIONS',
  725,
  TRUE,
  TRUE,
  TRUE,
  NOW(),
  NOW()
)
ON CONFLICT ("code") DO UPDATE SET
  "displayName" = EXCLUDED."displayName",
  "description" = EXCLUDED."description",
  "parentCode" = EXCLUDED."parentCode",
  "sortOrder" = EXCLUDED."sortOrder",
  "isSystem" = TRUE,
  "updatedAt" = NOW();

-- Backfill theo quyền mở màn hình hiện hữu; cấu hình đã có luôn được ưu tiên.
INSERT INTO "OrganizationNodeFeatureAssignment" (
  "id", "scopeRootNodeId", "nodeType", "nodeKey", "featureCode", "enabled",
  "assignedById", "note", "createdAt", "updatedAt"
)
SELECT
  gen_random_uuid()::text,
  a."scopeRootNodeId",
  a."nodeType",
  a."nodeKey",
  'QUICK_ACTION_FOLLOW_UP',
  BOOL_OR(a."enabled"),
  NULL,
  'Backfill Thao tác nhanh - Chăm sóc lại',
  NOW(),
  NOW()
FROM "OrganizationNodeFeatureAssignment" a
WHERE a."featureCode" IN ('SALES_REPORT', 'ADMIN_SALES_REPORTS')
GROUP BY a."scopeRootNodeId", a."nodeType", a."nodeKey"
ON CONFLICT ("scopeRootNodeId", "nodeType", "nodeKey", "featureCode") DO NOTHING;

INSERT INTO "UserFeatureAssignment" (
  "id", "userId", "featureCode", "enabled", "assignedById", "note",
  "createdAt", "updatedAt"
)
SELECT
  gen_random_uuid()::text,
  a."userId",
  'QUICK_ACTION_FOLLOW_UP',
  BOOL_OR(a."enabled"),
  NULL,
  'Backfill Thao tác nhanh - Chăm sóc lại',
  NOW(),
  NOW()
FROM "UserFeatureAssignment" a
WHERE a."featureCode" IN ('SALES_REPORT', 'ADMIN_SALES_REPORTS')
GROUP BY a."userId"
ON CONFLICT ("userId", "featureCode") DO NOTHING;

COMMIT;
