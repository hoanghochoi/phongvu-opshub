-- Feature assignments are the sole runtime gate for feature workspaces.
-- Remove only the seeded ADMIN rules that previously reopened feature routes;
-- explicit policy rows remain available for capability/data-scope evaluation.
DELETE FROM "AdminPolicyRule"
WHERE "isSystem" = true
  AND "systemRole" = 'ADMIN'
  AND "policyCode" IN ('BANK_STATEMENTS', 'OFFSET_ADJUSTMENTS');
