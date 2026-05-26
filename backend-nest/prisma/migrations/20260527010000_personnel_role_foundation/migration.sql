-- CreateTable
CREATE TABLE "DepartmentDefinition" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "displayName" TEXT NOT NULL,
    "description" TEXT,
    "isSystem" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "DepartmentDefinition_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "JobRoleDefinition" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "displayName" TEXT NOT NULL,
    "description" TEXT,
    "departmentCode" TEXT,
    "isSystem" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "JobRoleDefinition_pkey" PRIMARY KEY ("id")
);

-- AlterTable
ALTER TABLE "User" ADD COLUMN "departmentCode" TEXT,
ADD COLUMN "jobRoleCode" TEXT,
ADD COLUMN "workScopeType" TEXT;

-- Preserve legacy branch-selection behavior for existing users.
UPDATE "User"
SET "workScopeType" = CASE
    WHEN "role" IN ('SUPER_ADMIN', 'ADMIN') THEN 'NATIONAL'
    ELSE 'STORE'
END
WHERE "workScopeType" IS NULL;

-- CreateIndex
CREATE UNIQUE INDEX "DepartmentDefinition_code_key" ON "DepartmentDefinition"("code");

-- CreateIndex
CREATE UNIQUE INDEX "JobRoleDefinition_code_key" ON "JobRoleDefinition"("code");

-- CreateIndex
CREATE INDEX "JobRoleDefinition_departmentCode_idx" ON "JobRoleDefinition"("departmentCode");

-- CreateIndex
CREATE INDEX "User_departmentCode_idx" ON "User"("departmentCode");

-- CreateIndex
CREATE INDEX "User_jobRoleCode_idx" ON "User"("jobRoleCode");

-- CreateIndex
CREATE INDEX "User_workScopeType_idx" ON "User"("workScopeType");

-- AddForeignKey
ALTER TABLE "User" ADD CONSTRAINT "User_departmentCode_fkey" FOREIGN KEY ("departmentCode") REFERENCES "DepartmentDefinition"("code") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "User" ADD CONSTRAINT "User_jobRoleCode_fkey" FOREIGN KEY ("jobRoleCode") REFERENCES "JobRoleDefinition"("code") ON DELETE SET NULL ON UPDATE CASCADE;
