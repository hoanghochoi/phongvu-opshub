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
    required bool ingressEnabled,
    required bool projectionEnabled,
  }) async {
    final response = await _client.post(
      '${ApiConstants.adminBidvConnectionsEndpoint}/controls',
      body: {
        'ingressEnabled': ingressEnabled,
        'projectionEnabled': projectionEnabled,
      },
    );
    return ApiConnectionSnapshot.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}
