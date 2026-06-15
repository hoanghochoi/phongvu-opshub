INSERT INTO "FeatureDefinition" (
  "id", "code", "displayName", "description", "parentCode", "sortOrder",
  "visibleInUserPicker", "isSystem", "isActive", "createdAt", "updatedAt"
)
VALUES (
  'feature-payment-speaker',
  'PAYMENT_SPEAKER',
  'Đọc loa',
  'Đọc loa thông báo tiền vào trên thiết bị hỗ trợ',
  'PAYMENT_MONITOR',
  510,
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

INSERT INTO "OrganizationNodeFeatureAssignment" (
  "id", "scopeRootNodeId", "nodeType", "nodeKey", "featureCode", "enabled",
  "assignedById", "note", "createdAt", "updatedAt"
)
SELECT
  'node-feature-' || md5(
    monitor."scopeRootNodeId" || ':' ||
    monitor."nodeType" || ':' ||
    monitor."nodeKey" || ':PAYMENT_SPEAKER'
  ),
  monitor."scopeRootNodeId",
  monitor."nodeType",
  monitor."nodeKey",
  'PAYMENT_SPEAKER',
  true,
  NULL,
  'Backfilled from PAYMENT_MONITOR speaker-eligible node groups',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
FROM "OrganizationNodeFeatureAssignment" monitor
WHERE monitor."featureCode" = 'PAYMENT_MONITOR'
  AND monitor."enabled" = true
  AND monitor."nodeType" = 'LV5_POSITION'
  AND monitor."nodeKey" IN ('STORE_MANAGER', 'CASH')
ON CONFLICT ("scopeRootNodeId", "nodeType", "nodeKey", "featureCode") DO UPDATE SET
  "enabled" = true,
  "updatedAt" = CURRENT_TIMESTAMP;
