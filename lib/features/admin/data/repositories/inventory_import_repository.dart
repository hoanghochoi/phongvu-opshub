import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';

class InventoryImportResult {
  final int importedRows;
  final int deactivatedRows;
  final int skippedRows;
  final int totalRows;
  final List<String> srCodes;

  const InventoryImportResult({
    required this.importedRows,
    required this.deactivatedRows,
    required this.skippedRows,
    required this.totalRows,
    required this.srCodes,
  });

  factory InventoryImportResult.fromJson(Map<String, dynamic> json) {
    return InventoryImportResult(
      importedRows: _toInt(json['importedRows']),
      deactivatedRows: _toInt(json['deactivatedRows']),
      skippedRows: _toInt(json['skippedRows']),
      totalRows: _toInt(json['totalRows']),
      srCodes: (json['srCodes'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
    );
  }

  static int _toInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class InventoryImportRepository {
  final ApiClient _apiClient;

  const InventoryImportRepository(this._apiClient);

  Future<InventoryImportResult> uploadInventoryFile(String path) async {
    final response = await _apiClient.postMultipart(
      ApiConstants.fifoInventoryImportEndpoint,
      fields: const {},
      files: [await http.MultipartFile.fromPath('file', path)],
      timeout: ApiConstants.uploadTimeout,
    );
    return InventoryImportResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}
