-- Supporting indexes for the bounded admin list/read paths.
CREATE INDEX "User_createdAt_idx" ON "User"("createdAt");
CREATE INDEX "User_status_createdAt_idx" ON "User"("status", "createdAt");
CREATE INDEX "OrganizationNodeFeatureAssignment_featureCode_enabled_scopeRootNodeId_idx"
  ON "OrganizationNodeFeatureAssignment"("featureCode", "enabled", "scopeRootNodeId");
CREATE INDEX "AdminPolicyRule_policyCode_updatedAt_idx"
  ON "AdminPolicyRule"("policyCode", "updatedAt");
