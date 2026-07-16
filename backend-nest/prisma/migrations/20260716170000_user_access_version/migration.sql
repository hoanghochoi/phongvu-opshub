ALTER TABLE "User"
ADD COLUMN "accessVersion" INTEGER NOT NULL DEFAULT 0;

-- Access-context cache keys must change in the same transaction as the
-- permission/topology mutation. These triggers keep that invariant at the
-- database boundary, including bulk writes and code paths that do not use a
-- shared application transaction helper.
CREATE OR REPLACE FUNCTION opshub_bump_access_versions_for_users(
  p_user_ids TEXT[]
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_user_ids IS NULL OR cardinality(p_user_ids) = 0 THEN
    RETURN;
  END IF;

  UPDATE "User"
  SET "accessVersion" = "accessVersion" + 1
  WHERE "id" = ANY (p_user_ids);
END;
$$;

CREATE OR REPLACE FUNCTION opshub_bump_all_access_versions()
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE "User"
  SET "accessVersion" = "accessVersion" + 1
  WHERE "status" <> 'no';
END;
$$;

CREATE OR REPLACE FUNCTION opshub_bump_access_versions_for_node(
  p_node_id TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_node_id IS NULL OR btrim(p_node_id) = '' THEN
    PERFORM opshub_bump_all_access_versions();
    RETURN;
  END IF;

  WITH RECURSIVE subtree AS (
    SELECT "id"
    FROM "OrganizationNode"
    WHERE "id" = p_node_id

    UNION ALL

    SELECT child."id"
    FROM "OrganizationNode" child
    JOIN subtree parent ON child."parentId" = parent."id"
  )
  UPDATE "User" user_row
  SET "accessVersion" = "accessVersion" + 1
  WHERE user_row."status" <> 'no'
    AND (
      user_row."organizationNodeId" IN (SELECT "id" FROM subtree)
      OR EXISTS (
        SELECT 1
        FROM "UserOrganizationAssignment" assignment
        WHERE assignment."userId" = user_row."id"
          AND assignment."isActive" = TRUE
          AND assignment."organizationNodeId" IN (SELECT "id" FROM subtree)
      )
    );
END;
$$;

CREATE OR REPLACE FUNCTION opshub_access_version_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_TABLE_NAME = 'User' THEN
    IF TG_OP = 'UPDATE'
      AND NEW."email" IS NOT DISTINCT FROM OLD."email"
      AND NEW."firstName" IS NOT DISTINCT FROM OLD."firstName"
      AND NEW."lastName" IS NOT DISTINCT FROM OLD."lastName"
      AND NEW."avatarUrl" IS NOT DISTINCT FROM OLD."avatarUrl"
      AND NEW."tokenVersion" IS NOT DISTINCT FROM OLD."tokenVersion"
      AND NEW."status" IS NOT DISTINCT FROM OLD."status"
      AND NEW."role" IS NOT DISTINCT FROM OLD."role"
      AND NEW."storeId" IS NOT DISTINCT FROM OLD."storeId"
      AND NEW."departmentCode" IS NOT DISTINCT FROM OLD."departmentCode"
      AND NEW."jobRoleCode" IS NOT DISTINCT FROM OLD."jobRoleCode"
      AND NEW."workScopeType" IS NOT DISTINCT FROM OLD."workScopeType"
      AND NEW."regionCode" IS NOT DISTINCT FROM OLD."regionCode"
      AND NEW."areaCode" IS NOT DISTINCT FROM OLD."areaCode"
      AND NEW."organizationNodeId" IS NOT DISTINCT FROM OLD."organizationNodeId"
      AND NEW."profileCompletedAt" IS NOT DISTINCT FROM OLD."profileCompletedAt"
      AND NEW."branchLockedAt" IS NOT DISTINCT FROM OLD."branchLockedAt" THEN
      RETURN NEW;
    END IF;
    PERFORM opshub_bump_access_versions_for_users(
      ARRAY[CASE WHEN TG_OP = 'DELETE' THEN OLD."id" ELSE NEW."id" END]
    );
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  IF TG_TABLE_NAME IN ('UserFeatureAssignment', 'UserOrganizationAssignment') THEN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
      PERFORM opshub_bump_access_versions_for_users(
        ARRAY[OLD."userId"]
      );
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE')
      AND (TG_OP <> 'UPDATE' OR NEW."userId" IS DISTINCT FROM OLD."userId") THEN
      PERFORM opshub_bump_access_versions_for_users(
        ARRAY[NEW."userId"]
      );
    END IF;
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  IF TG_TABLE_NAME = 'UserPlatformSession' THEN
    IF TG_OP = 'UPDATE'
      AND NEW."userId" IS NOT DISTINCT FROM OLD."userId"
      AND NEW."sessionVersion" IS NOT DISTINCT FROM OLD."sessionVersion"
      AND NEW."revokedAt" IS NOT DISTINCT FROM OLD."revokedAt"
      AND NEW."expiresAt" IS NOT DISTINCT FROM OLD."expiresAt" THEN
      RETURN NEW;
    END IF;
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
      PERFORM opshub_bump_access_versions_for_users(ARRAY[OLD."userId"]);
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE')
      AND (TG_OP <> 'UPDATE' OR NEW."userId" IS DISTINCT FROM OLD."userId") THEN
      PERFORM opshub_bump_access_versions_for_users(ARRAY[NEW."userId"]);
    END IF;
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  IF TG_TABLE_NAME = 'OrganizationNodeFeatureAssignment' THEN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
      PERFORM opshub_bump_access_versions_for_node(OLD."scopeRootNodeId");
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE')
      AND (TG_OP <> 'UPDATE'
        OR NEW."scopeRootNodeId" IS DISTINCT FROM OLD."scopeRootNodeId") THEN
      PERFORM opshub_bump_access_versions_for_node(NEW."scopeRootNodeId");
    END IF;
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  IF TG_TABLE_NAME = 'AdminPolicyRule' THEN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
      IF OLD."organizationNodeId" IS NULL THEN
        PERFORM opshub_bump_all_access_versions();
      ELSE
        PERFORM opshub_bump_access_versions_for_node(OLD."organizationNodeId");
      END IF;
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE')
      AND (TG_OP <> 'UPDATE'
        OR NEW."organizationNodeId" IS DISTINCT FROM OLD."organizationNodeId") THEN
      IF NEW."organizationNodeId" IS NULL THEN
        PERFORM opshub_bump_all_access_versions();
      ELSE
        PERFORM opshub_bump_access_versions_for_node(NEW."organizationNodeId");
      END IF;
    END IF;
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  IF TG_TABLE_NAME = 'FeatureDefinition' THEN
    IF TG_OP = 'UPDATE'
      AND NEW."code" IS NOT DISTINCT FROM OLD."code"
      AND NEW."parentCode" IS NOT DISTINCT FROM OLD."parentCode"
      AND NEW."isActive" IS NOT DISTINCT FROM OLD."isActive" THEN
      RETURN NEW;
    END IF;
    PERFORM opshub_bump_all_access_versions();
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  IF TG_TABLE_NAME = 'AdminPolicyDefinition' THEN
    IF TG_OP = 'UPDATE'
      AND NEW."code" IS NOT DISTINCT FROM OLD."code"
      AND NEW."defaultAllowed" IS NOT DISTINCT FROM OLD."defaultAllowed"
      AND NEW."isActive" IS NOT DISTINCT FROM OLD."isActive" THEN
      RETURN NEW;
    END IF;
    PERFORM opshub_bump_all_access_versions();
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  IF TG_TABLE_NAME = 'DepartmentDefinition' THEN
    IF TG_OP = 'UPDATE'
      AND NEW."code" IS NOT DISTINCT FROM OLD."code"
      AND NEW."displayName" IS NOT DISTINCT FROM OLD."displayName"
      AND NEW."organizationNodeId" IS NOT DISTINCT FROM OLD."organizationNodeId"
      AND NEW."isActive" IS NOT DISTINCT FROM OLD."isActive" THEN
      RETURN NEW;
    END IF;
    PERFORM opshub_bump_all_access_versions();
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  IF TG_TABLE_NAME = 'JobRoleDefinition' THEN
    IF TG_OP = 'UPDATE'
      AND NEW."code" IS NOT DISTINCT FROM OLD."code"
      AND NEW."displayName" IS NOT DISTINCT FROM OLD."displayName"
      AND NEW."departmentCode" IS NOT DISTINCT FROM OLD."departmentCode"
      AND NEW."organizationNodeId" IS NOT DISTINCT FROM OLD."organizationNodeId"
      AND NEW."isActive" IS NOT DISTINCT FROM OLD."isActive" THEN
      RETURN NEW;
    END IF;
    PERFORM opshub_bump_all_access_versions();
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  IF TG_TABLE_NAME = 'RegionDefinition' THEN
    IF TG_OP = 'UPDATE'
      AND NEW."code" IS NOT DISTINCT FROM OLD."code"
      AND NEW."displayName" IS NOT DISTINCT FROM OLD."displayName"
      AND NEW."abbreviation" IS NOT DISTINCT FROM OLD."abbreviation"
      AND NEW."organizationNodeId" IS NOT DISTINCT FROM OLD."organizationNodeId"
      AND NEW."isActive" IS NOT DISTINCT FROM OLD."isActive" THEN
      RETURN NEW;
    END IF;
    PERFORM opshub_bump_all_access_versions();
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  IF TG_TABLE_NAME = 'AreaDefinition' THEN
    IF TG_OP = 'UPDATE'
      AND NEW."code" IS NOT DISTINCT FROM OLD."code"
      AND NEW."displayName" IS NOT DISTINCT FROM OLD."displayName"
      AND NEW."abbreviation" IS NOT DISTINCT FROM OLD."abbreviation"
      AND NEW."regionCode" IS NOT DISTINCT FROM OLD."regionCode"
      AND NEW."organizationNodeId" IS NOT DISTINCT FROM OLD."organizationNodeId"
      AND NEW."isActive" IS NOT DISTINCT FROM OLD."isActive" THEN
      RETURN NEW;
    END IF;
    PERFORM opshub_bump_all_access_versions();
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  IF TG_TABLE_NAME = 'OrganizationNode' THEN
    IF TG_OP = 'UPDATE'
      AND NEW."code" IS NOT DISTINCT FROM OLD."code"
      AND NEW."displayName" IS NOT DISTINCT FROM OLD."displayName"
      AND NEW."businessCode" IS NOT DISTINCT FROM OLD."businessCode"
      AND NEW."abbreviation" IS NOT DISTINCT FROM OLD."abbreviation"
      AND NEW."type" IS NOT DISTINCT FROM OLD."type"
      AND NEW."parentId" IS NOT DISTINCT FROM OLD."parentId"
      AND NEW."emailDomain" IS NOT DISTINCT FROM OLD."emailDomain"
      AND NEW."loginAllowed" IS NOT DISTINCT FROM OLD."loginAllowed"
      AND NEW."sortOrder" IS NOT DISTINCT FROM OLD."sortOrder"
      AND NEW."isActive" IS NOT DISTINCT FROM OLD."isActive" THEN
      RETURN NEW;
    END IF;
    PERFORM opshub_bump_all_access_versions();
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  IF TG_TABLE_NAME = 'Store' THEN
    IF TG_OP = 'UPDATE'
      AND NEW."storeId" IS NOT DISTINCT FROM OLD."storeId"
      AND NEW."storeName" IS NOT DISTINCT FROM OLD."storeName"
      AND NEW."areaCode" IS NOT DISTINCT FROM OLD."areaCode"
      AND NEW."organizationNodeId" IS NOT DISTINCT FROM OLD."organizationNodeId" THEN
      RETURN NEW;
    END IF;
    PERFORM opshub_bump_all_access_versions();
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  -- Definitions, broad rules and organization catalogs can match users by
  -- role/domain/personnel fields, so invalidate every active user atomically.
  PERFORM opshub_bump_all_access_versions();
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

CREATE TRIGGER "User_access_version"
AFTER UPDATE OF "email", "firstName", "lastName", "avatarUrl",
  "tokenVersion", "status", "role", "storeId",
  "departmentCode", "jobRoleCode", "workScopeType", "regionCode",
  "areaCode", "organizationNodeId", "profileCompletedAt", "branchLockedAt"
ON "User"
FOR EACH ROW
EXECUTE FUNCTION opshub_access_version_trigger();

CREATE TRIGGER "UserFeatureAssignment_access_version"
AFTER INSERT OR UPDATE OR DELETE ON "UserFeatureAssignment"
FOR EACH ROW
EXECUTE FUNCTION opshub_access_version_trigger();

CREATE TRIGGER "UserOrganizationAssignment_access_version"
AFTER INSERT OR UPDATE OR DELETE ON "UserOrganizationAssignment"
FOR EACH ROW
EXECUTE FUNCTION opshub_access_version_trigger();

CREATE TRIGGER "UserPlatformSession_access_version"
AFTER INSERT OR UPDATE OF "userId", "sessionVersion", "revokedAt", "expiresAt" OR DELETE
ON "UserPlatformSession"
FOR EACH ROW
EXECUTE FUNCTION opshub_access_version_trigger();

CREATE TRIGGER "FeatureDefinition_access_version"
AFTER INSERT OR UPDATE OF "code", "parentCode", "isActive" OR DELETE
ON "FeatureDefinition"
FOR EACH ROW
EXECUTE FUNCTION opshub_access_version_trigger();

CREATE TRIGGER "FeatureAccessRule_access_version"
AFTER INSERT OR UPDATE OR DELETE ON "FeatureAccessRule"
FOR EACH ROW
EXECUTE FUNCTION opshub_access_version_trigger();

CREATE TRIGGER "OrganizationNodeFeatureAssignment_access_version"
AFTER INSERT OR UPDATE OR DELETE ON "OrganizationNodeFeatureAssignment"
FOR EACH ROW
EXECUTE FUNCTION opshub_access_version_trigger();

CREATE TRIGGER "AdminPolicyDefinition_access_version"
AFTER INSERT OR UPDATE OF "code", "defaultAllowed", "isActive" OR DELETE
ON "AdminPolicyDefinition"
FOR EACH ROW
EXECUTE FUNCTION opshub_access_version_trigger();

CREATE TRIGGER "AdminPolicyRule_access_version"
AFTER INSERT OR UPDATE OR DELETE ON "AdminPolicyRule"
FOR EACH ROW
EXECUTE FUNCTION opshub_access_version_trigger();

CREATE TRIGGER "OrganizationNode_access_version"
AFTER INSERT OR UPDATE OF "code", "displayName", "businessCode",
  "abbreviation", "type", "parentId", "emailDomain", "loginAllowed",
  "sortOrder", "isActive" OR DELETE
ON "OrganizationNode"
FOR EACH ROW
EXECUTE FUNCTION opshub_access_version_trigger();

CREATE TRIGGER "Store_access_version"
AFTER INSERT OR UPDATE OF "storeId", "storeName", "areaCode",
  "organizationNodeId" OR DELETE
ON "Store"
FOR EACH ROW
EXECUTE FUNCTION opshub_access_version_trigger();

CREATE TRIGGER "DepartmentDefinition_access_version"
AFTER INSERT OR UPDATE OF "code", "displayName", "organizationNodeId",
  "isActive" OR DELETE
ON "DepartmentDefinition"
FOR EACH ROW
EXECUTE FUNCTION opshub_access_version_trigger();

CREATE TRIGGER "JobRoleDefinition_access_version"
AFTER INSERT OR UPDATE OF "code", "displayName", "departmentCode",
  "organizationNodeId", "isActive" OR DELETE
ON "JobRoleDefinition"
FOR EACH ROW
EXECUTE FUNCTION opshub_access_version_trigger();

CREATE TRIGGER "RegionDefinition_access_version"
AFTER INSERT OR UPDATE OF "code", "displayName", "abbreviation",
  "organizationNodeId", "isActive" OR DELETE
ON "RegionDefinition"
FOR EACH ROW
EXECUTE FUNCTION opshub_access_version_trigger();

CREATE TRIGGER "AreaDefinition_access_version"
AFTER INSERT OR UPDATE OF "code", "displayName", "abbreviation", "regionCode",
  "organizationNodeId", "isActive" OR DELETE
ON "AreaDefinition"
FOR EACH ROW
EXECUTE FUNCTION opshub_access_version_trigger();
