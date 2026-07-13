UPDATE "SalesReportErpOrderCache" cache
SET
  "storeCode" = NULL,
  "storeName" = NULL,
  "organizationNodeId" = NULL
WHERE jsonb_typeof(cache."sanitizedSnapshot") = 'object'
  AND NULLIF(cache."sanitizedSnapshot"->>'createdFromSiteDisplayName', '') IS NULL
  AND (
    cache."storeCode" IS NOT NULL
    OR cache."storeName" IS NOT NULL
    OR cache."organizationNodeId" IS NOT NULL
  );

UPDATE "HomeSummaryOrderFact" fact
SET
  "storeCode" = cache."storeCode",
  "storeName" = cache."storeName",
  "organizationNodeId" = cache."organizationNodeId"
FROM "SalesReportErpOrderCache" cache
WHERE fact."orderCode" = cache."orderCode"
  AND jsonb_typeof(cache."sanitizedSnapshot") = 'object'
  AND NULLIF(cache."sanitizedSnapshot"->>'createdFromSiteDisplayName', '') IS NULL
  AND (
    fact."storeCode" IS DISTINCT FROM cache."storeCode"
    OR fact."storeName" IS DISTINCT FROM cache."storeName"
    OR fact."organizationNodeId" IS DISTINCT FROM cache."organizationNodeId"
  );
