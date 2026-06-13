class AdminUserEditorPayload {
  AdminUserEditorPayload._();

  static Map<String, dynamic> build({
    required String email,
    required String firstName,
    required String lastName,
    required String status,
    required String role,
    required bool canEditRole,
    String? organizationNodeId,
  }) {
    return {
      'email': email.trim(),
      'firstName': firstName.trim(),
      'lastName': lastName.trim(),
      'status': status,
      'organizationNodeId': organizationNodeId,
      if (canEditRole) 'role': role,
    };
  }
}
