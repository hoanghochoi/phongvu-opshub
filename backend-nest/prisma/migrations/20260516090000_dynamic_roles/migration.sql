CREATE TABLE "RoleDefinition" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "displayName" TEXT NOT NULL,
    "description" TEXT,
    "isSystem" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "RoleDefinition_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "RoleDefinition_code_key" ON "RoleDefinition"("code");

INSERT INTO "RoleDefinition" ("id", "code", "displayName", "description", "isSystem", "updatedAt")
VALUES
  ('role-super-admin', 'SUPER_ADMIN', 'Super Admin', 'Toan quyen he thong', true, CURRENT_TIMESTAMP),
  ('role-admin', 'ADMIN', 'Admin', 'Quan ly user theo pham vi', true, CURRENT_TIMESTAMP),
  ('role-manager', 'MANAGER', 'Manager', 'Nhom quyen quan ly van hanh', true, CURRENT_TIMESTAMP),
  ('role-staff', 'STAFF', 'Staff', 'Quyen thao tac hang ngay', true, CURRENT_TIMESTAMP)
ON CONFLICT ("code") DO NOTHING;

ALTER TABLE "User" ALTER COLUMN "role" DROP DEFAULT;
ALTER TABLE "User" ALTER COLUMN "role" TYPE TEXT USING "role"::text;
ALTER TABLE "User" ALTER COLUMN "role" SET DEFAULT 'STAFF';

DROP TYPE IF EXISTS "Role";
