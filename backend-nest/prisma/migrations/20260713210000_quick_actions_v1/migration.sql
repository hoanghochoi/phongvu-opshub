CREATE TABLE "QuickActionLink" (
    "id" TEXT NOT NULL,
    "storeCode" TEXT NOT NULL,
    "actionCode" TEXT NOT NULL,
    "url" VARCHAR(2048) NOT NULL,
    "updatedById" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "QuickActionLink_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "QuickActionLink_storeCode_actionCode_key" ON "QuickActionLink"("storeCode", "actionCode");
CREATE INDEX "QuickActionLink_actionCode_idx" ON "QuickActionLink"("actionCode");
CREATE INDEX "QuickActionLink_updatedById_idx" ON "QuickActionLink"("updatedById");

ALTER TABLE "QuickActionLink" ADD CONSTRAINT "QuickActionLink_storeCode_fkey"
  FOREIGN KEY ("storeCode") REFERENCES "Store"("storeId") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "QuickActionLink" ADD CONSTRAINT "QuickActionLink_updatedById_fkey"
  FOREIGN KEY ("updatedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

INSERT INTO "FeatureDefinition" (
  "code", "displayName", "description", "parentCode", "sortOrder",
  "visibleInUserPicker", "isSystem", "isActive", "createdAt", "updatedAt"
) VALUES
  ('QUICK_ACTIONS', 'Thao tác nhanh', 'Nhóm thao tác nhanh trên thanh điều hướng và Trang chủ', NULL, 700, TRUE, TRUE, TRUE, NOW(), NOW()),
  ('QUICK_ACTION_FIFO', 'Thao tác nhanh - Kiểm tra FIFO', 'Hiện lối tắt Kiểm tra FIFO', 'QUICK_ACTIONS', 710, TRUE, TRUE, TRUE, NOW(), NOW()),
  ('QUICK_ACTION_VIETQR', 'Thao tác nhanh - VietQR', 'Hiện lối tắt VietQR', 'QUICK_ACTIONS', 720, TRUE, TRUE, TRUE, NOW(), NOW()),
  ('QUICK_ACTION_SALES_REPORT', 'Thao tác nhanh - Báo cáo bán hàng', 'Hiện lối tắt Báo cáo bán hàng', 'QUICK_ACTIONS', 730, TRUE, TRUE, TRUE, NOW(), NOW()),
  ('QUICK_ACTION_APP_DOWNLOAD', 'Thao tác nhanh - Tải app', 'Hiện mã QR tải ứng dụng của showroom', 'QUICK_ACTIONS', 740, TRUE, TRUE, TRUE, NOW(), NOW()),
  ('QUICK_ACTION_CHECK_IN', 'Thao tác nhanh - Check-in', 'Hiện mã QR check-in của showroom', 'QUICK_ACTIONS', 750, TRUE, TRUE, TRUE, NOW(), NOW()),
  ('QUICK_ACTION_ZALO_OA', 'Thao tác nhanh - Zalo OA', 'Hiện mã QR Zalo OA của showroom', 'QUICK_ACTIONS', 760, TRUE, TRUE, TRUE, NOW(), NOW()),
  ('QUICK_ACTION_GOOGLE_MAP', 'Thao tác nhanh - GG Map', 'Hiện mã QR Google Map của showroom', 'QUICK_ACTIONS', 770, TRUE, TRUE, TRUE, NOW(), NOW()),
  ('ADMIN_QUICK_ACTION_CODES', 'Quản lý mã thao tác nhanh', 'Cấu hình liên kết QR theo showroom', 'ADMIN', 97, TRUE, TRUE, TRUE, NOW(), NOW())
ON CONFLICT ("code") DO UPDATE SET
  "displayName" = EXCLUDED."displayName",
  "description" = EXCLUDED."description",
  "parentCode" = EXCLUDED."parentCode",
  "sortOrder" = EXCLUDED."sortOrder",
  "isSystem" = TRUE,
  "isActive" = TRUE,
  "updatedAt" = NOW();

-- Lối tắt nghiệp vụ kế thừa trạng thái hiện có tại từng node.
INSERT INTO "OrganizationNodeFeatureAssignment" (
  "id", "scopeRootNodeId", "nodeType", "nodeKey", "featureCode", "enabled",
  "assignedById", "note", "createdAt", "updatedAt"
)
SELECT gen_random_uuid()::text, a."scopeRootNodeId", a."nodeType", a."nodeKey", m."childCode",
       a."enabled", a."assignedById", 'Backfill Thao tác nhanh v1', NOW(), NOW()
FROM "OrganizationNodeFeatureAssignment" a
JOIN (VALUES
  ('FIFO', 'QUICK_ACTION_FIFO'),
  ('VIETQR', 'QUICK_ACTION_VIETQR'),
  ('SALES_REPORT', 'QUICK_ACTION_SALES_REPORT'),
  ('ADMIN', 'ADMIN_QUICK_ACTION_CODES')
) AS m("sourceCode", "childCode") ON a."featureCode" = m."sourceCode"
ON CONFLICT ("scopeRootNodeId", "nodeType", "nodeKey", "featureCode") DO NOTHING;

-- Root và bốn action QR được bật trên mọi target đang hoạt động trong cây quyền.
INSERT INTO "OrganizationNodeFeatureAssignment" (
  "id", "scopeRootNodeId", "nodeType", "nodeKey", "featureCode", "enabled",
  "assignedById", "note", "createdAt", "updatedAt"
)
SELECT gen_random_uuid()::text, targets."scopeRootNodeId", targets."nodeType", targets."nodeKey", codes."featureCode",
       TRUE, NULL, 'Backfill Thao tác nhanh v1', NOW(), NOW()
FROM (
  SELECT DISTINCT "scopeRootNodeId", "nodeType", "nodeKey"
  FROM "OrganizationNodeFeatureAssignment"
) targets
CROSS JOIN (VALUES
  ('QUICK_ACTIONS'),
  ('QUICK_ACTION_APP_DOWNLOAD'),
  ('QUICK_ACTION_CHECK_IN'),
  ('QUICK_ACTION_ZALO_OA'),
  ('QUICK_ACTION_GOOGLE_MAP')
) AS codes("featureCode")
ON CONFLICT ("scopeRootNodeId", "nodeType", "nodeKey", "featureCode") DO NOTHING;

-- Giữ tương thích cho các cài đặt quyền user/rule cũ ngoài cây node.
INSERT INTO "UserFeatureAssignment" (
  "id", "userId", "featureCode", "enabled", "assignedById", "note", "createdAt", "updatedAt"
)
SELECT gen_random_uuid()::text, a."userId", m."childCode", a."enabled", a."assignedById",
       'Backfill Thao tác nhanh v1', NOW(), NOW()
FROM "UserFeatureAssignment" a
JOIN (VALUES
  ('FIFO', 'QUICK_ACTION_FIFO'),
  ('VIETQR', 'QUICK_ACTION_VIETQR'),
  ('SALES_REPORT', 'QUICK_ACTION_SALES_REPORT')
) AS m("sourceCode", "childCode") ON a."featureCode" = m."sourceCode"
ON CONFLICT ("userId", "featureCode") DO NOTHING;
