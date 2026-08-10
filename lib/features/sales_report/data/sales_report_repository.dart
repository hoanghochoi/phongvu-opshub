import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../domain/sales_report.dart';
import 'sales_report_file_reader.dart';

const _salesHistoryUploadChunkBytes = 4 * 1024 * 1024;

class SalesHistoryUploadCancelled implements Exception {
  const SalesHistoryUploadCancelled();
}

class SalesReportImportFile {
  final String name;
  final int size;
  final Uint8List? bytes;
  final String? path;
  final Stream<List<int>>? readStream;

  const SalesReportImportFile({
    required this.name,
    required this.size,
    this.bytes,
    this.path,
    this.readStream,
  });

  bool get hasContent =>
      bytes?.isNotEmpty == true ||
      path?.isNotEmpty == true ||
      readStream != null;
}

class SalesReportRepository {
  final ApiClient _apiClient;
  final Map<String, Completer<void>> _historyUploadAborts = {};

  SalesReportRepository(this._apiClient);

  Future<List<SalesReportCategoryGroup>> fetchCategories({
    bool admin = false,
  }) async {
    final response = await _apiClient.get(
      admin
          ? ApiConstants.salesReportsAdminCategoriesEndpoint
          : ApiConstants.salesReportsCategoriesEndpoint,
    );
    final data = jsonDecode(response.body);
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map(
          (item) => SalesReportCategoryGroup.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  Future<SalesReportOrderCheck> checkOrder(
    String orderCode, {
    String? followUpCaseId,
  }) async {
    final response = await _apiClient.post(
      followUpCaseId == null
          ? ApiConstants.salesReportsCheckOrderEndpoint
          : ApiConstants.salesReportFollowUpCaseCheckOrderEndpoint(
              followUpCaseId,
            ),
      body: {'orderCode': orderCode.trim()},
      timeout: const Duration(seconds: 45),
    );
    return SalesReportOrderCheck.fromJson(jsonDecode(response.body));
  }

  Future<SalesReportOrderCockpit> fetchOrders(
    SalesReportOrdersQuery query,
  ) async {
    final response = await _apiClient.get(
      ApiConstants.salesReportsOrdersEndpoint,
      queryParameters: query.toQueryParameters(),
    );
    return SalesReportOrderCockpit.fromJson(jsonDecode(response.body));
  }

  Future<Map<String, dynamic>> create(
    SalesReportInput input, {
    String? followUpCaseId,
  }) async {
    final response = await _apiClient.post(
      followUpCaseId == null
          ? ApiConstants.salesReportsEndpoint
          : ApiConstants.salesReportFollowUpCaseEntriesEndpoint(followUpCaseId),
      body: followUpCaseId == null
          ? input.toJson()
          : {'outcome': 'PURCHASED', 'purchasedReport': input.toJson()},
      timeout: const Duration(seconds: 60),
    );
    final data = jsonDecode(response.body);
    return data is Map<String, dynamic> ? data : {};
  }

  Future<SalesReportFollowUpPage> fetchFollowUpCases({
    String status = 'OPEN',
    String? search,
    String? storeCode,
    String? categoryGroupId,
    DateTime? startDate,
    DateTime? endDate,
    int page = 0,
    int limit = 20,
  }) async {
    final response = await _apiClient.get(
      ApiConstants.salesReportFollowUpCasesEndpoint,
      queryParameters: {
        'status': status,
        if ((search ?? '').trim().isNotEmpty) 'search': search!.trim(),
        if ((storeCode ?? '').trim().isNotEmpty) 'storeCode': storeCode!.trim(),
        if ((categoryGroupId ?? '').trim().isNotEmpty)
          'categoryGroupId': categoryGroupId!.trim(),
        if (startDate != null) 'startDate': _apiDate(startDate),
        if (endDate != null) 'endDate': _apiDate(endDate),
        'page': '$page',
        'limit': '$limit',
      },
    );
    return SalesReportFollowUpPage.fromJson(jsonDecode(response.body));
  }

  Future<Uint8List> exportFollowUpHistory({
    String? search,
    String? storeCode,
    String? categoryGroupId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final bytes = await _apiClient.getBytes(
      ApiConstants.salesReportFollowUpHistoryExportEndpoint,
      queryParameters: {
        if ((search ?? '').trim().isNotEmpty) 'search': search!.trim(),
        if ((storeCode ?? '').trim().isNotEmpty) 'storeCode': storeCode!.trim(),
        if ((categoryGroupId ?? '').trim().isNotEmpty)
          'categoryGroupId': categoryGroupId!.trim(),
        'startDate': _apiDate(startDate),
        'endDate': _apiDate(endDate),
      },
      timeout: const Duration(seconds: 60),
    );
    return Uint8List.fromList(bytes);
  }

  Future<SalesReportFollowUpCase> fetchFollowUpCase(String id) async {
    final response = await _apiClient.get(
      ApiConstants.salesReportFollowUpCaseEndpoint(id),
    );
    return SalesReportFollowUpCase.fromJson(jsonDecode(response.body));
  }

  Future<SalesReportFollowUpCase> createFollowUpEntry(
    String id, {
    required String outcome,
    String? reason,
    String? otherReason,
  }) async {
    final response = await _apiClient.post(
      ApiConstants.salesReportFollowUpCaseEntriesEndpoint(id),
      body: {
        'outcome': outcome,
        if ((reason ?? '').trim().isNotEmpty)
          'notPurchasedReason': reason!.trim(),
        if ((otherReason ?? '').trim().isNotEmpty)
          'notPurchasedOtherReason': otherReason!.trim(),
      },
    );
    return SalesReportFollowUpCase.fromJson(jsonDecode(response.body));
  }

  Future<SalesReportFollowUpCase> assignFollowUpCase(
    String id,
    String userId,
  ) async {
    final response = await _apiClient.patch(
      ApiConstants.salesReportFollowUpCaseAssigneeEndpoint(id),
      body: {'userId': userId},
    );
    return SalesReportFollowUpCase.fromJson(jsonDecode(response.body));
  }

  Future<SalesReportFollowUpCase> reopenFollowUpCase(String id) async {
    final response = await _apiClient.post(
      ApiConstants.salesReportFollowUpCaseReopenEndpoint(id),
      body: const {},
    );
    return SalesReportFollowUpCase.fromJson(jsonDecode(response.body));
  }

  Future<Map<String, dynamic>> fetchList(SalesReportQuery query) async {
    final response = await _apiClient.get(
      ApiConstants.salesReportsEndpoint,
      queryParameters: query.toQueryParameters(),
    );
    final data = jsonDecode(response.body);
    return data is Map<String, dynamic> ? data : {};
  }

  Future<Uint8List> exportXlsx(SalesReportQuery query) async {
    final bytes = await _apiClient.getBytes(
      ApiConstants.salesReportsExportEndpoint,
      queryParameters: query.toQueryParameters(),
      timeout: const Duration(seconds: 60),
    );
    return Uint8List.fromList(bytes);
  }

  Future<SalesReportImportPreview> previewImport(
    SalesReportImportFile file,
  ) async {
    final response = await _apiClient.postMultipart(
      ApiConstants.salesReportsImportPreviewEndpoint,
      fields: const {},
      files: [await _importFilePart(file)],
      timeout: ApiConstants.uploadTimeout,
    );
    return SalesReportImportPreview.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<SalesReportImportPreview> commitImport(
    SalesReportImportFile file, {
    required String expectedFileHash,
  }) async {
    final response = await _apiClient.postMultipart(
      ApiConstants.salesReportsImportCommitEndpoint,
      fields: {'expectedFileHash': expectedFileHash},
      files: [await _importFilePart(file)],
      timeout: ApiConstants.uploadTimeout,
    );
    return SalesReportImportPreview.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<SalesHistoryImportJob> enqueueHistoryImport(
    SalesReportImportFile file, {
    void Function(SalesHistoryImportJob job)? onJobChanged,
    bool Function()? isCancelled,
  }) async {
    final admittedResponse = await _apiClient.post(
      ApiConstants.salesHistoryImportJobsEndpoint,
      body: {'fileName': file.name, 'fileSize': file.size},
    );
    var job = SalesHistoryImportJob.fromJson(
      jsonDecode(admittedResponse.body) as Map<String, dynamic>,
    );
    onJobChanged?.call(job);
    final reader = _SalesHistoryUploadReader(file);
    final uploadAbort = Completer<void>();
    _historyUploadAborts[job.id] = uploadAbort;
    try {
      var offset = job.uploadedBytes;
      var transientFailures = 0;
      while (offset < file.size) {
        if (isCancelled?.call() == true) {
          await cancelHistoryImport(job.id).catchError((_) => job);
          throw const SalesHistoryUploadCancelled();
        }
        final length = (file.size - offset).clamp(
          0,
          _salesHistoryUploadChunkBytes,
        );
        final bytes = await reader.read(offset, length);
        if (bytes.isEmpty) {
          throw ArgumentError('Không đọc được phần tiếp theo của tệp CSV/TSV.');
        }
        try {
          final response = await _apiClient.postMultipart(
            ApiConstants.salesHistoryImportChunkEndpoint(job.id),
            fields: {'offset': '$offset'},
            files: [
              http.MultipartFile.fromBytes(
                'chunk',
                bytes,
                filename: 'history.part',
              ),
            ],
            timeout: const Duration(minutes: 2),
            abortTrigger: uploadAbort.future,
          );
          job = SalesHistoryImportJob.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>,
          );
          offset = job.uploadedBytes;
          transientFailures = 0;
          onJobChanged?.call(job);
        } catch (_) {
          if (isCancelled?.call() == true || uploadAbort.isCompleted) {
            throw const SalesHistoryUploadCancelled();
          }
          transientFailures += 1;
          job = await fetchHistoryImportJob(job.id);
          onJobChanged?.call(job);
          offset = job.uploadedBytes;
          if (job.status == 'CANCELLED') {
            throw const SalesHistoryUploadCancelled();
          }
          if (job.status != 'UPLOADING' || transientFailures >= 3) rethrow;
          await Future<void>.delayed(
            Duration(milliseconds: 250 * transientFailures),
          );
        }
      }
      if (isCancelled?.call() == true) {
        await cancelHistoryImport(job.id).catchError((_) => job);
        throw const SalesHistoryUploadCancelled();
      }
      final completed = await _apiClient.post(
        ApiConstants.salesHistoryImportCompleteEndpoint(job.id),
        body: const {},
      );
      job = SalesHistoryImportJob.fromJson(
        jsonDecode(completed.body) as Map<String, dynamic>,
      );
      onJobChanged?.call(job);
      return job;
    } finally {
      await reader.close();
      if (identical(_historyUploadAborts[job.id], uploadAbort)) {
        _historyUploadAborts.remove(job.id);
      }
    }
  }

  void abortHistoryImportUpload(String jobId) {
    final abort = _historyUploadAborts[jobId];
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  Future<SalesHistoryImportJob> fetchHistoryImportJob(String id) async {
    final response = await _apiClient.get(
      ApiConstants.salesHistoryImportJobEndpoint(id),
    );
    return SalesHistoryImportJob.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<SalesHistoryImportJob> cancelHistoryImport(String id) async {
    final response = await _apiClient.post(
      ApiConstants.salesHistoryImportCancelEndpoint(id),
      body: const {},
    );
    return SalesHistoryImportJob.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<List<SalesHistoryVersion>> fetchHistoryVersions() async {
    final response = await _apiClient.get(
      ApiConstants.salesHistoryVersionsEndpoint,
      queryParameters: const {'limit': '50'},
    );
    final data = jsonDecode(response.body);
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map(
          (value) =>
              SalesHistoryVersion.fromJson(Map<String, dynamic>.from(value)),
        )
        .toList(growable: false);
  }

  Future<void> activateHistoryVersion(String id) => _apiClient.post(
    ApiConstants.salesHistoryVersionActivateEndpoint(id),
    body: const {},
  );

  Future<void> rollbackHistoryVersion(String id) => _apiClient.post(
    ApiConstants.salesHistoryVersionRollbackEndpoint(id),
    body: const {},
  );

  Future<Uint8List> downloadHistoryQuarantine(String jobId) async =>
      Uint8List.fromList(
        await _apiClient.getBytes(
          ApiConstants.salesHistoryImportQuarantineEndpoint(jobId),
          timeout: const Duration(minutes: 2),
        ),
      );

  Future<http.MultipartFile> _importFilePart(SalesReportImportFile file) async {
    final bytes = file.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      return http.MultipartFile.fromBytes('file', bytes, filename: file.name);
    }
    final path = file.path;
    if (path != null && path.isNotEmpty) {
      return http.MultipartFile.fromPath('file', path, filename: file.name);
    }
    throw ArgumentError('File Excel chưa có dữ liệu để tải lên.');
  }

  String _apiDate(DateTime value) {
    String two(int part) => part.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }
}

class _SalesHistoryUploadReader {
  _SalesHistoryUploadReader(this.file)
    : _streamIterator = file.readStream == null
          ? null
          : StreamIterator<List<int>>(file.readStream!);

  final SalesReportImportFile file;
  final StreamIterator<List<int>>? _streamIterator;
  Uint8List? _streamPart;
  int _streamPartOffset = 0;
  int _streamCursor = 0;
  Uint8List? _currentChunk;
  int _currentChunkOffset = 0;

  Future<Uint8List> read(int offset, int length) async {
    final bytes = file.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      final end = (offset + length).clamp(0, bytes.length);
      if (offset >= end) return Uint8List(0);
      return Uint8List.sublistView(bytes, offset, end);
    }
    final path = file.path;
    if (path != null && path.isNotEmpty) {
      return readSalesReportFileChunk(path, offset, length);
    }
    if (_streamIterator == null) {
      throw ArgumentError('Tệp CSV/TSV chưa có dữ liệu để tải lên.');
    }
    return _readStream(offset, length);
  }

  Future<Uint8List> _readStream(int offset, int length) async {
    final iterator = _streamIterator;
    if (iterator == null) {
      throw ArgumentError('Tệp CSV/TSV chưa có luồng dữ liệu để tải lên.');
    }
    final current = _currentChunk;
    if (current != null) {
      final currentEnd = _currentChunkOffset + current.length;
      if (offset >= _currentChunkOffset && offset < currentEnd) {
        final start = offset - _currentChunkOffset;
        final end = (start + length).clamp(0, current.length);
        return Uint8List.sublistView(current, start, end);
      }
      if (offset == currentEnd) {
        _currentChunk = null;
      } else {
        throw StateError(
          'Không thể tiếp tục luồng tệp từ vị trí máy chủ yêu cầu.',
        );
      }
    }
    if (offset != _streamCursor) {
      throw StateError(
        'Không thể tiếp tục luồng tệp từ vị trí máy chủ yêu cầu.',
      );
    }

    final builder = BytesBuilder(copy: false);
    while (builder.length < length) {
      var part = _streamPart;
      if (part == null || _streamPartOffset >= part.length) {
        if (!await iterator.moveNext()) break;
        part = Uint8List.fromList(iterator.current);
        _streamPart = part;
        _streamPartOffset = 0;
        if (part.isEmpty) continue;
      }
      final remaining = length - builder.length;
      final take = (part.length - _streamPartOffset).clamp(0, remaining);
      builder.add(
        Uint8List.sublistView(
          part,
          _streamPartOffset,
          _streamPartOffset + take,
        ),
      );
      _streamPartOffset += take;
      _streamCursor += take;
    }
    final chunk = builder.takeBytes();
    _currentChunkOffset = offset;
    _currentChunk = chunk;
    return chunk;
  }

  Future<void> close() async {
    await _streamIterator?.cancel();
    _streamPart = null;
    _currentChunk = null;
  }
}
