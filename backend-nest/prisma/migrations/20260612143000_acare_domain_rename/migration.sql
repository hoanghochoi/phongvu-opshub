-- Rename the ACare operational email domain from acaretek.vn to acare.vn.
-- Keep stable ids/codes such as org-domain-acaretek-vn for existing references.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM "User" old_user
    JOIN "User" new_user
      ON lower(new_user."email") = regexp_replace(
        lower(old_user."email"),
        '@acaretek\.vn$',
        '@acare.vn'
      )
    WHERE lower(old_user."email") LIKE '%@acaretek.vn'
      AND old_user."id" <> new_user."id"
  ) THEN
    RAISE EXCEPTION 'Cannot rename acaretek.vn users because matching acare.vn emails already exist';
  END IF;
END $$;

UPDATE "User"
SET "email" = regexp_replace("email", '@acaretek\.vn$', '@acare.vn', 'i'),
    "updatedAt" = CURRENT_TIMESTAMP
WHERE lower("email") LIKE '%@acaretek.vn';

UPDATE "EmailVerificationCode"
SET "email" = regexp_replace("email", '@acaretek\.vn$', '@acare.vn', 'i')
WHERE lower("email") LIKE '%@acaretek.vn';

UPDATE "RoleDefinition"
SET "description" = replace("description", 'acaretek.vn', 'acare.vn'),
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "description" LIKE '%acaretek.vn%';

UPDATE "OrganizationNode"
SET "displayName" = replace("displayName", 'acaretek.vn', 'acare.vn'),
    "businessCode" = CASE
      WHEN lower(COALESCE("businessCode", '')) = 'acaretek.vn' THEN 'acare.vn'
      ELSE "businessCode"
    END,
    "emailDomain" = CASE
      WHEN lower(COALESCE("emailDomain", '')) = 'acaretek.vn' THEN 'acare.vn'
      ELSE "emailDomain"
    END,
    "updatedAt" = CURRENT_TIMESTAMP
WHERE lower(COALESCE("displayName", '')) LIKE '%acaretek.vn%'
   OR lower(COALESCE("businessCode", '')) = 'acaretek.vn'
   OR lower(COALESCE("emailDomain", '')) = 'acaretek.vn';

UPDATE "FeatureAccessRule"
SET "emailDomain" = 'acare.vn',
    "updatedAt" = CURRENT_TIMESTAMP
WHERE lower(COALESCE("emailDomain", '')) = 'acaretek.vn';

UPDATE "AdminPolicyRule"
SET "emailDomain" = 'acare.vn',
    "updatedAt" = CURRENT_TIMESTAMP
WHERE lower(COALESCE("emailDomain", '')) = 'acaretek.vn';

WITH normalized_domains AS (
  SELECT
    setting."id",
    item.ordinality,
    CASE
      WHEN lower(item.value) = 'acaretek.vn' THEN 'acare.vn'
      ELSE lower(item.value)
    END AS domain
  FROM "AdminSetting" setting,
    jsonb_array_elements_text(setting."value") WITH ORDINALITY AS item(value, ordinality)
  WHERE setting."key" = 'AUTH_ALLOWED_EMAIL_DOMAINS'
    AND jsonb_typeof(setting."value") = 'array'
), deduped_domains AS (
  SELECT "id", domain, min(ordinality) AS ordinality
  FROM normalized_domains
  WHERE domain <> ''
  GROUP BY "id", domain
), rebuilt_settings AS (
  SELECT "id", jsonb_agg(domain ORDER BY ordinality) AS "value"
  FROM deduped_domains
  GROUP BY "id"
)
UPDATE "AdminSetting" setting
SET "value" = rebuilt."value",
    "updatedAt" = CURRENT_TIMESTAMP
FROM rebuilt_settings rebuilt
WHERE setting."id" = rebuilt."id";