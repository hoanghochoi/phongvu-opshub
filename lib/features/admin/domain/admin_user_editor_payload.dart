class AdminUserEditorPayload {
  AdminUserEditorPayload._();

  static Map<String, dynamic> build({
    required String email,
    required String firstName,
    required String lastName,
    required String status,
    required String workScopeType,
    required String role,
    required bool canEditRole,
    required bool canEditFeatures,
    required List<String> featureTreeCodes,
    String? departmentCode,
    String? jobRoleCode,
    String? organizationNodeId,
  }) {
    return {
      'email': email.trim(),
      'firstName': firstName.trim(),
      'lastName': lastName.trim(),
      'status': status,
      'departmentCode': departmentCode,
      'jobRoleCode': jobRoleCode,
      'workScopeType': workScopeType,
      'organizationNodeId': organizationNodeId,
      if (canEditRole) 'role': role,
      if (canEditFeatures) 'featureTreeCodes': featureTreeCodes,
    };
  }
}
