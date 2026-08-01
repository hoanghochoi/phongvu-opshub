class ApiConnectionSnapshot {
  const ApiConnectionSnapshot({
    required this.bankCode,
    required this.environment,
    required this.publicBaseUrl,
    required this.controls,
    required this.clients,
    required this.keys,
    required this.audits,
  });

  final String bankCode;
  final String environment;
  final String? publicBaseUrl;
  final ApiConnectionControls controls;
  final List<ApiClientCredential> clients;
  final List<ApiPgpKey> keys;
  final List<ApiConnectionAudit> audits;

  factory ApiConnectionSnapshot.fromJson(Map<String, dynamic> json) {
    return ApiConnectionSnapshot(
      bankCode: json['bankCode']?.toString() ?? 'BIDV',
      environment: json['environment']?.toString() ?? 'unknown',
      publicBaseUrl: _nullableText(json['publicBaseUrl']),
      controls: ApiConnectionControls.fromJson(_map(json['controls'])),
      clients: _list(json['clients'])
          .map((item) => ApiClientCredential.fromJson(_map(item)))
          .toList(growable: false),
      keys: _list(
        json['keys'],
      ).map((item) => ApiPgpKey.fromJson(_map(item))).toList(growable: false),
      audits: _list(json['audits'])
          .map((item) => ApiConnectionAudit.fromJson(_map(item)))
          .toList(growable: false),
    );
  }
}

class ApiConnectionControls {
  const ApiConnectionControls({
    required this.ingressRequested,
    required this.projectionRequested,
    required this.ingressMasterEnabled,
    required this.projectionMasterEnabled,
    required this.ingressEffective,
    required this.projectionEffective,
    required this.version,
    required this.updatedAt,
  });

  final bool ingressRequested;
  final bool projectionRequested;
  final bool ingressMasterEnabled;
  final bool projectionMasterEnabled;
  final bool ingressEffective;
  final bool projectionEffective;
  final int version;
  final DateTime? updatedAt;

  factory ApiConnectionControls.fromJson(Map<String, dynamic> json) {
    return ApiConnectionControls(
      ingressRequested: json['ingressRequested'] == true,
      projectionRequested: json['projectionRequested'] == true,
      ingressMasterEnabled: json['ingressMasterEnabled'] == true,
      projectionMasterEnabled: json['projectionMasterEnabled'] == true,
      ingressEffective: json['ingressEffective'] == true,
      projectionEffective: json['projectionEffective'] == true,
      version: int.tryParse(json['version']?.toString() ?? '') ?? 0,
      updatedAt: _date(json['updatedAt']),
    );
  }
}

class ApiClientCredential {
  const ApiClientCredential({
    required this.id,
    required this.displayName,
    required this.clientId,
    required this.scope,
    required this.status,
    required this.version,
    required this.activatedAt,
    required this.overlapExpiresAt,
    required this.revokedAt,
  });

  final String id;
  final String displayName;
  final String clientId;
  final String scope;
  final String status;
  final int version;
  final DateTime? activatedAt;
  final DateTime? overlapExpiresAt;
  final DateTime? revokedAt;

  bool get canRotate => status == 'ACTIVE';
  bool get canRevoke => status == 'ACTIVE' || status == 'OVERLAP';

  factory ApiClientCredential.fromJson(Map<String, dynamic> json) {
    return ApiClientCredential(
      id: json['id']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      clientId: json['clientId']?.toString() ?? '',
      scope: json['scope']?.toString() ?? '',
      status: json['status']?.toString() ?? 'UNKNOWN',
      version: int.tryParse(json['version']?.toString() ?? '') ?? 0,
      activatedAt: _date(json['activatedAt']),
      overlapExpiresAt: _date(json['overlapExpiresAt']),
      revokedAt: _date(json['revokedAt']),
    );
  }
}

class CreatedApiClientCredential {
  const CreatedApiClientCredential({
    required this.client,
    required this.clientSecret,
  });

  final ApiClientCredential client;
  final String clientSecret;

  factory CreatedApiClientCredential.fromJson(Map<String, dynamic> json) {
    return CreatedApiClientCredential(
      client: ApiClientCredential.fromJson(json),
      clientSecret: json['clientSecret']?.toString() ?? '',
    );
  }
}

class ApiPgpKey {
  const ApiPgpKey({
    required this.id,
    required this.displayName,
    required this.fingerprint,
    required this.algorithm,
    required this.status,
    required this.version,
    required this.activatedAt,
    required this.overlapExpiresAt,
  });

  final String id;
  final String displayName;
  final String fingerprint;
  final String algorithm;
  final String status;
  final int version;
  final DateTime? activatedAt;
  final DateTime? overlapExpiresAt;

  bool get canRotate => status == 'ACTIVE';
  bool get canRevoke => status == 'ACTIVE' || status == 'OVERLAP';

  factory ApiPgpKey.fromJson(Map<String, dynamic> json) {
    return ApiPgpKey(
      id: json['id']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      fingerprint: json['fingerprint']?.toString() ?? '',
      algorithm: json['algorithm']?.toString() ?? '',
      status: json['status']?.toString() ?? 'UNKNOWN',
      version: int.tryParse(json['version']?.toString() ?? '') ?? 0,
      activatedAt: _date(json['activatedAt']),
      overlapExpiresAt: _date(json['overlapExpiresAt']),
    );
  }
}

class ExportedApiPublicKey {
  const ExportedApiPublicKey({
    required this.id,
    required this.fingerprint,
    required this.publicKeyArmor,
    required this.fileName,
  });

  final String id;
  final String fingerprint;
  final String publicKeyArmor;
  final String fileName;

  factory ExportedApiPublicKey.fromJson(Map<String, dynamic> json) {
    return ExportedApiPublicKey(
      id: json['id']?.toString() ?? '',
      fingerprint: json['fingerprint']?.toString() ?? '',
      publicKeyArmor: json['publicKeyArmor']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? 'opshub-bidv-public.asc',
    );
  }
}

class ApiConnectionAudit {
  const ApiConnectionAudit({
    required this.id,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.createdAt,
  });

  final String id;
  final String action;
  final String targetType;
  final String targetId;
  final DateTime? createdAt;

  factory ApiConnectionAudit.fromJson(Map<String, dynamic> json) {
    return ApiConnectionAudit(
      id: json['id']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      targetType: json['targetType']?.toString() ?? '',
      targetId: json['targetId']?.toString() ?? '',
      createdAt: _date(json['createdAt']),
    );
  }
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map<String, dynamic> ? value : <String, dynamic>{};

List<dynamic> _list(dynamic value) => value is List ? value : const [];

String? _nullableText(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

DateTime? _date(dynamic value) => DateTime.tryParse(value?.toString() ?? '');
