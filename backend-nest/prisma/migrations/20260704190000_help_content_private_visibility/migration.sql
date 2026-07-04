ALTER TABLE "HelpContentPage"
ADD COLUMN "isAuthenticatedOnly" BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX "HelpContentPage_isPublished_isAuthenticatedOnly_parentKey_sortOrder_idx"
ON "HelpContentPage"("isPublished", "isAuthenticatedOnly", "parentKey", "sortOrder");
