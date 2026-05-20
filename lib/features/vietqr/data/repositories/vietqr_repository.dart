import 'dart:convert';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/vietqr_transfer.dart';

class VietQrRepository {
  final ApiClient _apiClient;

  VietQrRepository(this._apiClient);

  Future<VietQrTransfer> createTransferQr({
    required int? amount,
    required String orderCode,
    required String storeCode,
  }) async {
    final response = await _apiClient.post(
      ApiConstants.vietQrEndpoint,
      body: {'amount': amount, 'orderCode': orderCode, 'storeCode': storeCode},
    );

    return VietQrTransfer.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}
