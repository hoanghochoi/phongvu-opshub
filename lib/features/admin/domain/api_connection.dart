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

  ApiOperatingMode get operatingMode => controls.operatingMode;
  ApiOperatingMode get effectiveMode => controls.effectiveMode;
  ApiConnectionReadiness get readiness => controls.readiness;
  List<String> get blockers => controls.blockers;
  int get pendingProjectionCount => controls.pendingProjectionCount;

  factory ApiConnectionSnapshot.fromJson(Map<String, dynamic> json) {
    final controlsJson = <String, dynamic>{...json, ..._map(json['controls'])};
    return ApiConnectionSnapshot(
      bankCode: json['bankCode']?.toString() ?? 'BIDV',
      environment: json['environment']?.toString() ?? 'unknown',
      publicBaseUrl: _nullableText(json['publicBaseUrl']),
      controls: ApiConnectionControls.fromJson(controlsJson),
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
    this.operatingMode = ApiOperatingMode.stopped,
    this.effectiveMode = ApiOperatingMode.stopped,
    this.readiness = const ApiConnectionReadiness(),
    this.blockers = const <String>[],
    this.pendingProjectionCount = 0,
    this.emergencyDisabled = false,
  });

  final bool ingressRequested;
  final bool projectionRequested;
  final bool ingressMasterEnabled;
  final bool projectionMasterEnabled;
  final bool ingressEffective;
  final bool projectionEffective;
  final int version;
  final DateTime? updatedAt;
  final ApiOperatingMode operatingMode;
  final ApiOperatingMode effectiveMode;
  final ApiConnectionReadiness readiness;
  final List<String> blockers;
  final int pendingProjectionCount;
  final bool emergencyDisabled;

  bool get canEnableIngestOrLive => readiness.allReady;
  bool get hasPendingProjection => pendingProjectionCount > 0;

  factory ApiConnectionControls.fromJson(Map<String, dynamic> json) {
    final legacyIngress = json['ingressRequested'] == true;
    final legacyProjection = json['projectionRequested'] == true;
    final fallbackMode = ApiOperatingMode.fromJson(
      json['operatingMode'],
      legacyIngress: legacyIngress,
      legacyProjection: legacyProjection,
    );
    return ApiConnectionControls(
      ingressRequested: legacyIngress,
      projectionRequested: legacyProjection,
      ingressMasterEnabled: json['ingressMasterEnabled'] == true,
      projectionMasterEnabled: json['projectionMasterEnabled'] == true,
      ingressEffective: json['ingressEffective'] == true,
      projectionEffective: json['projectionEffective'] == true,
      version: int.tryParse(json['version']?.toString() ?? '') ?? 0,
      updatedAt: _date(json['updatedAt']),
      operatingMode: fallbackMode,
      effectiveMode: ApiOperatingMode.fromJson(
        json['effectiveMode'],
        legacyIngress: json['ingressEffective'] == true,
        legacyProjection: json['projectionEffective'] == true,
      ),
      readiness: ApiConnectionReadiness.fromJson(_map(json['readiness'])),
      blockers: _list(json['blockers'])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(growable: false),
      pendingProjectionCount:
          int.tryParse(json['pendingProjectionCount']?.toString() ?? '') ?? 0,
      emergencyDisabled: json['emergencyDisabled'] == true,
    );
  }
}

enum ApiOperatingMode {
  stopped('STOPPED', 'Dừng'),
  uatIngestOnly('UAT_INGEST_ONLY', 'UAT — Chỉ tiếp nhận'),
  live('LIVE', 'Vận hành chính thức');

  const ApiOperatingMode(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static ApiOperatingMode fromJson(
    dynamic value, {
    bool legacyIngress = false,
    bool legacyProjection = false,
  }) {
    switch (value?.toString()) {
      case 'LIVE':
        return ApiOperatingMode.live;
      case 'UAT_INGEST_ONLY':
        return ApiOperatingMode.uatIngestOnly;
      case 'STOPPED':
        return ApiOperatingMode.stopped;
      default:
        if (legacyProjection && legacyIngress) return ApiOperatingMode.live;
        if (legacyIngress) return ApiOperatingMode.uatIngestOnly;
        return ApiOperatingMode.stopped;
    }
  }
}

class ApiConnectionReadiness {
  const ApiConnectionReadiness({
    this.infrastructure = false,
    this.kek = false,
    this.client = false,
    this.openPgpKey = false,
  });

  final bool infrastructure;
  final bool kek;
  final bool client;
  final bool openPgpKey;

  bool get allReady => infrastructure && kek && client && openPgpKey;

  factory ApiConnectionReadiness.fromJson(Map<String, dynamic> json) {
    return ApiConnectionReadiness(
      infrastructure: json['infrastructure'] == true,
      kek: json['kek'] == true,
      client: json['client'] == true,
      openPgpKey: json['openPgpKey'] == true,
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
