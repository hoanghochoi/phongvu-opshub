CREATE TABLE "contract_appendices" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "orderCode" TEXT NOT NULL,
    "terminalCode" TEXT NOT NULL,
    "totalBeforeVat" BIGINT NOT NULL,
    "totalVatAmount" BIGINT NOT NULL,
    "totalAfterVat" BIGINT NOT NULL,
    "amountInWords" TEXT NOT NULL,
    "manualTaxItemCount" INTEGER NOT NULL DEFAULT 0,
    "sourceOrderFetchedAt" TIMESTAMP(3) NOT NULL,
    "quoteFingerprint" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiresAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "contract_appendices_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "contract_appendices_totals_check" CHECK (
      "totalBeforeVat" >= 0
      AND "totalVatAmount" >= 0
      AND "totalAfterVat" = "totalBeforeVat" + "totalVatAmount"
    )
);

CREATE TABLE "contract_appendix_items" (
    "id" TEXT NOT NULL,
    "contractAppendixId" TEXT NOT NULL,
    "position" INTEGER NOT NULL,
    "sourceLineKey" TEXT NOT NULL,
    "sku" TEXT NOT NULL,
    "sellerSku" TEXT,
    "productName" TEXT NOT NULL,
    "quantity" INTEGER NOT NULL,
    "unit" TEXT NOT NULL,
    "finalSellPrice" BIGINT NOT NULL,
    "unitPriceBeforeVat" BIGINT NOT NULL,
    "vatRateBps" INTEGER NOT NULL,
    "taxCode" TEXT,
    "taxLabel" TEXT,
    "taxSource" TEXT NOT NULL,
    "taxFetchedAt" TIMESTAMP(3),
    "lineBeforeVat" BIGINT NOT NULL,
    "lineVatAmount" BIGINT NOT NULL,
    "lineAfterVat" BIGINT NOT NULL,

    CONSTRAINT "contract_appendix_items_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "contract_appendix_items_values_check" CHECK (
      "position" > 0
      AND "quantity" > 0
      AND "finalSellPrice" >= 0
      AND "unitPriceBeforeVat" >= 0
      AND "vatRateBps" BETWEEN 0 AND 10000
      AND "lineBeforeVat" >= 0
      AND "lineVatAmount" >= 0
      AND "lineAfterVat" = "lineBeforeVat" + "lineVatAmount"
      AND "taxSource" IN ('ERP_PPM', 'MANUAL')
    )
);

CREATE INDEX "contract_appendices_userId_createdAt_idx"
ON "contract_appendices"("userId", "createdAt");

CREATE INDEX "contract_appendices_userId_orderCode_createdAt_idx"
ON "contract_appendices"("userId", "orderCode", "createdAt");

CREATE INDEX "contract_appendices_expiresAt_idx"
ON "contract_appendices"("expiresAt");

CREATE UNIQUE INDEX "contract_appendix_items_contractAppendixId_position_key"
ON "contract_appendix_items"("contractAppendixId", "position");

CREATE INDEX "contract_appendix_items_contractAppendixId_idx"
ON "contract_appendix_items"("contractAppendixId");

CREATE INDEX "contract_appendix_items_sku_idx"
ON "contract_appendix_items"("sku");

ALTER TABLE "contract_appendices"
ADD CONSTRAINT "contract_appendices_userId_fkey"
FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "contract_appendix_items"
ADD CONSTRAINT "contract_appendix_items_contractAppendixId_fkey"
FOREIGN KEY ("contractAppendixId") REFERENCES "contract_appendices"("id") ON DELETE CASCADE ON UPDATE CASCADE;
