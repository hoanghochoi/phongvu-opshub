CREATE TABLE "UserOrganizationAssignment" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "organizationNodeId" TEXT NOT NULL,
  "isPrimary" BOOLEAN NOT NULL DEFAULT false,
  "isActive" BOOLEAN NOT NULL DEFAULT true,
  "assignedById" TEXT,
  "note" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "UserOrganizationAssignment_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "UserOrganizationAssignment_userId_organizationNodeId_key"
ON "UserOrganizationAssignment"("userId", "organizationNodeId");

CREATE INDEX "UserOrganizationAssignment_userId_isActive_idx"
ON "UserOrganizationAssignment"("userId", "isActive");

CREATE INDEX "UserOrganizationAssignment_organizationNodeId_isActive_idx"
ON "UserOrganizationAssignment"("organizationNodeId", "isActive");

ALTER TABLE "UserOrganizationAssignment"
ADD CONSTRAINT "UserOrganizationAssignment_userId_fkey"
FOREIGN KEY ("userId") REFERENCES "User"("id")
ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "UserOrganizationAssignment"
ADD CONSTRAINT "UserOrganizationAssignment_organizationNodeId_fkey"
FOREIGN KEY ("organizationNodeId") REFERENCES "OrganizationNode"("id")
ON DELETE RESTRICT ON UPDATE CASCADE;

INSERT INTO "UserOrganizationAssignment" (
  "id",
  "userId",
  "organizationNodeId",
  "isPrimary",
  "isActive",
  "note",
  "createdAt",
  "updatedAt"
)
SELECT
  'uoa_' || md5(u."id" || ':' || COALESCE(u."organizationNodeId", s."organizationNodeId")),
  u."id",
  COALESCE(u."organizationNodeId", s."organizationNodeId"),
  true,
  true,
  'Backfilled from legacy user/store organization node',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
FROM "User" u
LEFT JOIN "Store" s ON s."id" = u."storeId"
WHERE COALESCE(u."organizationNodeId", s."organizationNodeId") IS NOT NULL
ON CONFLICT ("userId", "organizationNodeId") DO UPDATE
SET
  "isPrimary" = true,
  "isActive" = true,
  "updatedAt" = CURRENT_TIMESTAMP;
