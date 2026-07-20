import 'entities/user.dart';

abstract final class RealtimeSessionIdentity {
  static String forUser(User user, {String? accessIdentity}) {
    final assignedStores = user.assignedStoreIds.toList()..sort();
    final organizationNodeIds = user.organizationNodeIds.toList()..sort();
    final features = user.featureAccess.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final policies = user.policyAccess.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final normalizedAccessIdentity = accessIdentity?.trim();
    final accessSignature = normalizedAccessIdentity?.isNotEmpty == true
        ? normalizedAccessIdentity!
        : [
            ...features.map((entry) => '${entry.key}:${entry.value}'),
            ...policies.map((entry) => '${entry.key}:${entry.value}'),
          ].join(',');
    return '${user.id ?? user.email}|${user.role ?? ''}|'
        '${user.organizationNodeId ?? ''}|${organizationNodeIds.join(',')}|'
        '${assignedStores.join(',')}|$accessSignature';
  }
}
