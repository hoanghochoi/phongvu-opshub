WITH display_source AS (
  SELECT
    cache."id",
    cache."orderCode",
    NULLIF(cache."sanitizedSnapshot"->>'createdFromSiteDisplayName', '') AS "displayName"
  FROM "SalesReportErpOrderCache" cache
  WHERE jsonb_typeof(cache."sanitizedSnapshot") = 'object'
),
resolved AS (
  SELECT
    display_source."id",
    display_source."orderCode",
    UPPER(
      COALESCE(
        substring(display_source."displayName" FROM '^\[([A-Za-z]{2,3}[0-9]{1,4})\]'),
        substring(display_source."displayName" FROM '^([A-Za-z]{2,3}[0-9]{1,4})($|[^A-Za-z0-9])')
      )
    ) AS "storeCode"
  FROM display_source
  WHERE display_source."displayName" IS NOT NULL
),
store_match AS (
  SELECT
    resolved."id",
    resolved."orderCode",
    store."storeId",
    store."storeName",
    store."organizationNodeId"
  FROM resolved
  JOIN "Store" store
    ON UPPER(store."storeId") = resolved."storeCode"
  WHERE resolved."storeCode" IS NOT NULL
)
UPDATE "SalesReportErpOrderCache" cache
SET
  "storeCode" = store_match."storeId",
  "storeName" = store_match."storeName",
  "organizationNodeId" = store_match."organizationNodeId"
FROM store_match
WHERE cache."id" = store_match."id"
  AND (
    cache."storeCode" IS DISTINCT FROM store_match."storeId"
    OR cache."storeName" IS DISTINCT FROM store_match."storeName"
    OR cache."organizationNodeId" IS DISTINCT FROM store_match."organizationNodeId"
  );

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
  AND (
    fact."storeCode" IS DISTINCT FROM cache."storeCode"
    OR fact."storeName" IS DISTINCT FROM cache."storeName"
    OR fact."organizationNodeId" IS DISTINCT FROM cache."organizationNodeId"
  );
