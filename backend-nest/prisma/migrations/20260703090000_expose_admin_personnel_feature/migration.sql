UPDATE "FeatureDefinition"
SET
  "displayName" = 'Danh mục nhân sự',
  "description" = 'Quản lý phòng ban và chức danh',
  "parentCode" = 'ADMIN',
  "sortOrder" = 75,
  "visibleInUserPicker" = true,
  "isActive" = true,
  "updatedAt" = NOW()
WHERE "code" = 'ADMIN_PERSONNEL';
