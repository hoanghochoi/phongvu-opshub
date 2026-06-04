-- Stop instead of guessing if the deprecated scope is unexpectedly in use.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM "User" WHERE "workScopeType" = 'MULTI_STORE') THEN
    RAISE EXCEPTION 'Cannot migrate personnel scope: User.workScopeType=MULTI_STORE is still assigned';
  END IF;
END $$;

-- CreateTable
CREATE TABLE "RegionDefinition" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "displayName" TEXT NOT NULL,
    "abbreviation" TEXT NOT NULL,
    "description" TEXT,
    "isSystem" BOOLEAN NOT NULL DEFAULT false,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "RegionDefinition_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AreaDefinition" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "displayName" TEXT NOT NULL,
    "abbreviation" TEXT NOT NULL,
    "description" TEXT,
    "regionCode" TEXT NOT NULL,
    "isSystem" BOOLEAN NOT NULL DEFAULT false,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "AreaDefinition_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "FeatureDefinition" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "displayName" TEXT NOT NULL,
    "description" TEXT,
    "isSystem" BOOLEAN NOT NULL DEFAULT true,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "FeatureDefinition_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "FeatureAccessRule" (
    "id" TEXT NOT NULL,
    "featureCode" TEXT NOT NULL,
    "enabled" BOOLEAN NOT NULL,
    "systemRole" TEXT,
    "departmentCode" TEXT,
    "jobRoleCode" TEXT,
    "workScopeType" TEXT,
    "regionCode" TEXT,
    "areaCode" TEXT,
    "storeCode" TEXT,
    "userId" TEXT,
    "note" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "FeatureAccessRule_pkey" PRIMARY KEY ("id")
);

-- AlterTable
ALTER TABLE "DepartmentDefinition" ADD COLUMN "isActive" BOOLEAN NOT NULL DEFAULT true;

-- AlterTable
ALTER TABLE "JobRoleDefinition" ADD COLUMN "isActive" BOOLEAN NOT NULL DEFAULT true;

-- AlterTable
ALTER TABLE "Store" ADD COLUMN "areaCode" TEXT;

-- AlterTable
ALTER TABLE "User" ADD COLUMN "regionCode" TEXT,
ADD COLUMN "areaCode" TEXT;

-- Seed required system regions/areas before backfill and FKs.
INSERT INTO "RegionDefinition" ("id", "code", "displayName", "abbreviation", "description", "isSystem", "isActive", "createdAt", "updatedAt")
VALUES
  ('region-chua-gan', 'CHUA_GAN', 'Chưa gán', 'CHUA_GAN', 'Vùng/Miền mặc định cho dữ liệu cũ chưa phân loại', true, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('region-chatsale', 'CHATSALE', 'Chatsale', 'CHATSALE', 'Scope ảo tương đương cấp Miền cho đội Chatsale', true, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('region-telesale', 'TELESALE', 'Telesale', 'TELESALE', 'Scope ảo tương đương cấp Miền cho đội Telesale', true, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

INSERT INTO "AreaDefinition" ("id", "code", "displayName", "abbreviation", "description", "regionCode", "isSystem", "isActive", "createdAt", "updatedAt")
VALUES
  ('area-chua-gan', 'CHUA_GAN', 'Chưa gán', 'CHUA_GAN', 'Vùng mặc định cho dữ liệu cũ chưa phân loại', 'CHUA_GAN', true, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('area-chatsale', 'CHATSALE', 'Chatsale', 'CHATSALE', 'Vùng ảo tương ứng Chatsale', 'CHATSALE', true, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('area-telesale', 'TELESALE', 'Telesale', 'TELESALE', 'Vùng ảo tương ứng Telesale', 'TELESALE', true, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

-- Backfill existing stores and personnel scopes.
UPDATE "Store"
SET "areaCode" = 'CHUA_GAN'
WHERE "areaCode" IS NULL;

UPDATE "User"
SET "workScopeType" = CASE
    WHEN "role" IN ('SUPER_ADMIN', 'ADMIN') THEN 'NATIONAL'
    ELSE 'STORE'
END
WHERE "workScopeType" IS NULL;

UPDATE "User"
SET "workScopeType" = 'REGION',
    "regionCode" = 'CHATSALE',
    "areaCode" = 'CHATSALE'
WHERE "workScopeType" = 'ONLINE';

UPDATE "User"
SET "regionCode" = 'CHUA_GAN',
    "areaCode" = 'CHUA_GAN'
WHERE "workScopeType" IN ('STORE', 'AREA', 'REGION')
  AND "regionCode" IS NULL;

-- Rename operational job role only; system access role MANAGER stays unchanged.
UPDATE "JobRoleDefinition"
SET "code" = 'STORE_MANAGER',
    "displayName" = 'Store Manager',
    "description" = COALESCE("description", 'Quản lý SR/showroom')
WHERE "code" = 'MANAGER';

UPDATE "User"
SET "jobRoleCode" = 'STORE_MANAGER'
WHERE "jobRoleCode" = 'MANAGER';

UPDATE "JobRoleDefinition"
SET "code" = 'CHATSALE',
    "displayName" = 'Chatsale',
    "description" = COALESCE("description", 'Nhân sự chatsale')
WHERE "code" = 'SALE_ONLINE';

UPDATE "User"
SET "jobRoleCode" = 'CHATSALE'
WHERE "jobRoleCode" = 'SALE_ONLINE';

INSERT INTO "JobRoleDefinition" ("id", "code", "displayName", "description", "departmentCode", "isSystem", "isActive", "createdAt", "updatedAt")
VALUES ('job-role-telesale', 'TELESALE', 'Telesale', 'Nhân sự telesale', 'SALES', true, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT ("code") DO NOTHING;

-- CreateIndex
CREATE UNIQUE INDEX "RegionDefinition_code_key" ON "RegionDefinition"("code");
CREATE UNIQUE INDEX "AreaDefinition_code_key" ON "AreaDefinition"("code");
CREATE UNIQUE INDEX "FeatureDefinition_code_key" ON "FeatureDefinition"("code");
CREATE INDEX "AreaDefinition_regionCode_idx" ON "AreaDefinition"("regionCode");
CREATE INDEX "Store_areaCode_idx" ON "Store"("areaCode");
CREATE INDEX "User_regionCode_idx" ON "User"("regionCode");
CREATE INDEX "User_areaCode_idx" ON "User"("areaCode");
CREATE INDEX "FeatureAccessRule_featureCode_idx" ON "FeatureAccessRule"("featureCode");
CREATE INDEX "FeatureAccessRule_systemRole_idx" ON "FeatureAccessRule"("systemRole");
CREATE INDEX "FeatureAccessRule_departmentCode_idx" ON "FeatureAccessRule"("departmentCode");
CREATE INDEX "FeatureAccessRule_jobRoleCode_idx" ON "FeatureAccessRule"("jobRoleCode");
CREATE INDEX "FeatureAccessRule_workScopeType_idx" ON "FeatureAccessRule"("workScopeType");
CREATE INDEX "FeatureAccessRule_regionCode_idx" ON "FeatureAccessRule"("regionCode");
CREATE INDEX "FeatureAccessRule_areaCode_idx" ON "FeatureAccessRule"("areaCode");
CREATE INDEX "FeatureAccessRule_storeCode_idx" ON "FeatureAccessRule"("storeCode");
CREATE INDEX "FeatureAccessRule_userId_idx" ON "FeatureAccessRule"("userId");

-- AddForeignKey
ALTER TABLE "AreaDefinition" ADD CONSTRAINT "AreaDefinition_regionCode_fkey" FOREIGN KEY ("regionCode") REFERENCES "RegionDefinition"("code") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "Store" ADD CONSTRAINT "Store_areaCode_fkey" FOREIGN KEY ("areaCode") REFERENCES "AreaDefinition"("code") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "User" ADD CONSTRAINT "User_regionCode_fkey" FOREIGN KEY ("regionCode") REFERENCES "RegionDefinition"("code") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "User" ADD CONSTRAINT "User_areaCode_fkey" FOREIGN KEY ("areaCode") REFERENCES "AreaDefinition"("code") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "FeatureAccessRule" ADD CONSTRAINT "FeatureAccessRule_featureCode_fkey" FOREIGN KEY ("featureCode") REFERENCES "FeatureDefinition"("code") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "FeatureAccessRule" ADD CONSTRAINT "FeatureAccessRule_departmentCode_fkey" FOREIGN KEY ("departmentCode") REFERENCES "DepartmentDefinition"("code") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "FeatureAccessRule" ADD CONSTRAINT "FeatureAccessRule_jobRoleCode_fkey" FOREIGN KEY ("jobRoleCode") REFERENCES "JobRoleDefinition"("code") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "FeatureAccessRule" ADD CONSTRAINT "FeatureAccessRule_regionCode_fkey" FOREIGN KEY ("regionCode") REFERENCES "RegionDefinition"("code") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "FeatureAccessRule" ADD CONSTRAINT "FeatureAccessRule_areaCode_fkey" FOREIGN KEY ("areaCode") REFERENCES "AreaDefinition"("code") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "FeatureAccessRule" ADD CONSTRAINT "FeatureAccessRule_storeCode_fkey" FOREIGN KEY ("storeCode") REFERENCES "Store"("storeId") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "FeatureAccessRule" ADD CONSTRAINT "FeatureAccessRule_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
