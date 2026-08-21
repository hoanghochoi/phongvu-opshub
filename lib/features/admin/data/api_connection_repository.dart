import 'dart:convert';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../domain/api_connection.dart';

class ApiConnectionRepository {
  ApiConnectionRepository(this._client);

  final ApiClient _client;

  Future<ApiConnectionSnapshot> fetchSnapshot() async {
    final response = await _client.get(
      ApiConstants.adminBidvConnectionsEndpoint,
    );
    return ApiConnectionSnapshot.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<CreatedApiClientCredential> createClient(String displayName) async {
    final response = await _client.post(
      '${ApiConstants.adminBidvConnectionsEndpoint}/clients',
      body: {'displayName': displayName},
    );
    return CreatedApiClientCredential.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<CreatedApiClientCredential> rotateClient(String id) async {
    final response = await _client.post(
      '${ApiConstants.adminBidvConnectionsEndpoint}/clients/$id/rotate',
      body: const {},
    );
    return CreatedApiClientCredential.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> revokeClient(String id) async {
    await _client.post(
      '${ApiConstants.adminBidvConnectionsEndpoint}/clients/$id/revoke',
      body: const {'recoveryOverride': false},
    );
  }

  Future<ApiPgpKey> generateKey(String displayName) async {
    final response = await _client.post(
      '${ApiConstants.adminBidvConnectionsEndpoint}/keys/generate',
      body: {'displayName': displayName},
      timeout: const Duration(seconds: 60),
    );
    return ApiPgpKey.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<ApiPgpKey> rotateKey(String id) async {
    final response = await _client.post(
      '${ApiConstants.adminBidvConnectionsEndpoint}/keys/$id/rotate',
      body: const {},
      timeout: const Duration(seconds: 60),
    );
    return ApiPgpKey.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> revokeKey(String id) async {
    await _client.post(
      '${ApiConstants.adminBidvConnectionsEndpoint}/keys/$id/revoke',
      body: const {'recoveryOverride': false},
    );
  }

  Future<ExportedApiPublicKey> exportPublicKey(String id) async {
    final response = await _client.get(
      '${ApiConstants.adminBidvConnectionsEndpoint}/keys/$id/public',
    );
    return ExportedApiPublicKey.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<ApiConnectionSnapshot> updateControls({
    ApiOperatingMode? operatingMode,
    int? expectedVersion,
    bool? ingressEnabled,
    bool? projectionEnabled,
  }) async {
    final body = <String, dynamic>{};
    if (operatingMode != null) {
      if (ingressEnabled != null || projectionEnabled != null) {
        throw ArgumentError(
          'Không gửi đồng thời trạng thái vận hành và công tắc tương thích.',
        );
      }
      if (expectedVersion == null) {
        throw ArgumentError(
          'Cần cung cấp expectedVersion khi thay đổi trạng thái vận hành.',
        );
      }
      body['operatingMode'] = operatingMode.wireValue;
      body['expectedVersion'] = expectedVersion;
    } else {
      if (ingressEnabled == null || projectionEnabled == null) {
        throw ArgumentError(
          'Cần cung cấp operatingMode hoặc cặp công tắc tương thích.',
        );
      }
      body
        ..['ingressEnabled'] = ingressEnabled
        ..['projectionEnabled'] = projectionEnabled;
    }
    final response = await _client.post(
      '${ApiConstants.adminBidvConnectionsEndpoint}/controls',
      body: body,
    );
    return ApiConnectionSnapshot.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<ApiConnectionSnapshot> updateOperatingMode({
    required ApiOperatingMode mode,
    required int expectedVersion,
  }) {
    return updateControls(
      operatingMode: mode,
      expectedVersion: expectedVersion,
    );
  }
}
