CREATE TABLE "MediaObject" (
    "id" TEXT NOT NULL,
    "storageKey" TEXT NOT NULL,
    "ownerFeature" TEXT NOT NULL,
    "ownerRecordId" TEXT NOT NULL,
    "uploaderId" TEXT NOT NULL,
    "originalName" TEXT,
    "contentTypeVerified" TEXT NOT NULL,
    "sizeBytes" INTEGER NOT NULL,
    "checksumSha256" TEXT NOT NULL,
    "visibility" TEXT NOT NULL DEFAULT 'PRIVATE',
    "legacyUrl" TEXT,
    "expiresAt" TIMESTAMP(3),
    "deletedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "MediaObject_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "MediaObject_storageKey_key" ON "MediaObject"("storageKey");
CREATE UNIQUE INDEX "MediaObject_legacyUrl_ownerFeature_ownerRecordId_key"
    ON "MediaObject"("legacyUrl", "ownerFeature", "ownerRecordId");
CREATE INDEX "MediaObject_ownerFeature_ownerRecordId_deletedAt_idx"
    ON "MediaObject"("ownerFeature", "ownerRecordId", "deletedAt");
CREATE INDEX "MediaObject_uploaderId_createdAt_idx"
    ON "MediaObject"("uploaderId", "createdAt");
CREATE INDEX "MediaObject_checksumSha256_idx" ON "MediaObject"("checksumSha256");
