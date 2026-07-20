UPDATE "MapVietinTransaction"
SET "incomeType" = 'PARTNER_INTERNAL'
WHERE "incomeTypeSource" = 'AUTO'
  AND regexp_replace(
    UPPER(COALESCE("content", '')),
    '[[:space:]]+',
    '',
    'g'
  ) LIKE 'TNG%';
