-- Scratch/staging rollback rehearsal only. Production application rollback
-- keeps these additive columns/tables so snapshots created by the new build
-- remain readable by the restored application.
DROP TABLE IF EXISTS "contract_appendix_source_orders";

ALTER TABLE "contract_appendix_items"
DROP CONSTRAINT IF EXISTS "contract_appendix_items_erpRowTotal_check",
DROP COLUMN IF EXISTS "sourceLineIdentities",
DROP COLUMN IF EXISTS "sourceOrderCodes",
DROP COLUMN IF EXISTS "erpRowTotal";

ALTER TABLE "contract_appendices"
DROP COLUMN IF EXISTS "orderCodes";
