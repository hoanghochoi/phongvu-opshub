ALTER TABLE "SalesReport"
  ADD COLUMN "customerType" TEXT,
  ADD COLUMN "customerIsStudent" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "promotionCodes" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  ADD COLUMN "installmentNeed" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "installmentApproved" BOOLEAN,
  ADD COLUMN "installmentLoanAmount" INTEGER,
  ADD COLUMN "installmentNoInstallmentReason" TEXT,
  ADD COLUMN "erpPaymentMethods" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  ADD COLUMN "erpCustomerType" TEXT;

ALTER TABLE "SalesReportOrderItem"
  ADD COLUMN "productGroupCode" TEXT;

CREATE INDEX "SalesReport_customerType_submittedAt_idx"
  ON "SalesReport"("customerType", "submittedAt");

CREATE INDEX "SalesReport_installmentNeed_submittedAt_idx"
  ON "SalesReport"("installmentNeed", "submittedAt");
