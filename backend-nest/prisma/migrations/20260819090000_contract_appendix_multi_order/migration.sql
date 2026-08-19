-- OPS-209 expand-only Contract Appendix provenance and ERP row totals.
-- Legacy parent/item columns remain populated so an older application can
-- continue reading snapshots while the new application reads these fields.

ALTER TABLE "contract_appendices"
ADD COLUMN "orderCodes" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];

ALTER TABLE "contract_appendix_items"
ADD COLUMN "erpRowTotal" BIGINT,
ADD COLUMN "sourceOrderCodes" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
ADD COLUMN "sourceLineIdentities" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];

CREATE TABLE "contract_appendix_source_orders" (
    "id" TEXT NOT NULL,
    "contractAppendixId" TEXT NOT NULL,
    "position" INTEGER NOT NULL,
    "orderCode" TEXT NOT NULL,
    "fetchedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "contract_appendix_source_orders_pkey" PRIMARY KEY ("id")
);

-- Backfill the single-order provenance that existed before OPS-209. Do not
-- rewrite any historical money; erpRowTotal mirrors the already persisted
-- lineAfterVat for those snapshots only.
UPDATE "contract_appendices"
SET "orderCodes" = ARRAY["orderCode"]
WHERE cardinality("orderCodes") = 0;

INSERT INTO "contract_appendix_source_orders" (
    "id", "contractAppendixId", "position", "orderCode", "fetchedAt"
)
SELECT
    md5(c."id" || ':0'), c."id", 0, c."orderCode", c."sourceOrderFetchedAt"
FROM "contract_appendices" AS c;

UPDATE "contract_appendix_items" AS i
SET
    "erpRowTotal" = i."lineAfterVat",
    "sourceOrderCodes" = ARRAY[c."orderCode"],
    "sourceLineIdentities" = ARRAY[i."sourceLineKey"]
FROM "contract_appendices" AS c
WHERE i."contractAppendixId" = c."id";

ALTER TABLE "contract_appendix_source_orders"
ADD CONSTRAINT "contract_appendix_source_orders_contractAppendixId_fkey"
FOREIGN KEY ("contractAppendixId") REFERENCES "contract_appendices"("id")
ON DELETE CASCADE ON UPDATE CASCADE;

CREATE UNIQUE INDEX "contract_appendix_source_orders_contractAppendixId_position_key"
ON "contract_appendix_source_orders"("contractAppendixId", "position");

CREATE INDEX "contract_appendix_source_orders_orderCode_idx"
ON "contract_appendix_source_orders"("orderCode");

ALTER TABLE "contract_appendix_items"
ADD CONSTRAINT "contract_appendix_items_erpRowTotal_check"
CHECK ("erpRowTotal" IS NULL OR "erpRowTotal" >= 0);
