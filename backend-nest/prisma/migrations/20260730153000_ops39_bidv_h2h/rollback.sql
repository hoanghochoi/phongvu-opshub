-- OPS-39 uses a non-destructive application rollback. Keep additive tables,
-- columns, canonical receipts and immutable audit evidence in place.
UPDATE "BankConnectionControl"
SET "ingressEnabled" = false,
    "projectionEnabled" = false,
    "version" = "version" + 1,
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "bankCode" = 'BIDV';
