CREATE TABLE "HelpContentPage" (
    "id" TEXT NOT NULL,
    "key" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "fileName" TEXT NOT NULL,
    "parentKey" TEXT,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "markdown" TEXT NOT NULL,
    "isPublished" BOOLEAN NOT NULL DEFAULT true,
    "updatedByUserId" TEXT,
    "updatedByEmail" TEXT,
    "seededFromDocsAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "HelpContentPage_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "HelpContentPage_key_key" ON "HelpContentPage"("key");
CREATE INDEX "HelpContentPage_parentKey_sortOrder_key_idx" ON "HelpContentPage"("parentKey", "sortOrder", "key");
CREATE INDEX "HelpContentPage_isPublished_parentKey_sortOrder_idx" ON "HelpContentPage"("isPublished", "parentKey", "sortOrder");
