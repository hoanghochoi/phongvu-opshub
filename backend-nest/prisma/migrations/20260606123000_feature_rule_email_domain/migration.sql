ALTER TABLE "FeatureAccessRule" ADD COLUMN "emailDomain" TEXT;
CREATE INDEX "FeatureAccessRule_emailDomain_idx" ON "FeatureAccessRule"("emailDomain");