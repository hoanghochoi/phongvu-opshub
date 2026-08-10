import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/network/api_exception.dart';
import 'package:phongvu_opshub/features/sales_report/data/sales_report_repository.dart';

void main() {
  test(
    'web-style read stream uploads bounded chunks without retaining whole file',
    () async {
      const sourcePartBytes = 1024 * 1024;
      const uploadChunkBytes = 4 * sourcePartBytes;
      final fileSize = uploadChunkBytes + 3;
      var streamListenCount = 0;
      var emittedBytes = 0;
      final emittedAtChunkRequest = <int>[];

      Stream<List<int>> source() async* {
        streamListenCount += 1;
        for (var offset = 0; offset < fileSize; offset += sourcePartBytes) {
          final length = (fileSize - offset).clamp(0, sourcePartBytes);
          emittedBytes += length;
          yield Uint8List(length);
        }
      }

      final client = ApiClient.test(
        MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/history-import/jobs') &&
              request.method == 'POST') {
            return _jsonResponse({
              'id': 'job-stream',
              'status': 'UPLOADING',
              'uploadedBytes': 0,
              'expectedBytes': fileSize,
            });
          }
          if (path.contains('/history-import/jobs/job-stream/chunks')) {
            emittedAtChunkRequest.add(emittedBytes);
            final uploadedBytes = emittedAtChunkRequest.length == 1
                ? uploadChunkBytes
                : fileSize;
            return _jsonResponse({
              'id': 'job-stream',
              'status': 'UPLOADING',
              'uploadedBytes': uploadedBytes,
              'expectedBytes': fileSize,
            });
          }
          if (path.contains('/history-import/jobs/job-stream/complete')) {
            return _jsonResponse({
              'id': 'job-stream',
              'status': 'QUEUED',
              'uploadedBytes': fileSize,
              'expectedBytes': fileSize,
            });
          }
          return http.Response('Not found', 404);
        }),
      );
      addTearDown(client.dispose);

      final job = await SalesReportRepository(client).enqueueHistoryImport(
        SalesReportImportFile(
          name: 'history.csv',
          size: fileSize,
          readStream: source(),
        ),
      );

      expect(job.status, 'QUEUED');
      expect(streamListenCount, 1);
      expect(emittedAtChunkRequest, [uploadChunkBytes, fileSize]);
    },
  );

  test(
    'historical CSV upload resumes from the server acknowledged offset',
    () async {
      const chunkBytes = 4 * 1024 * 1024;
      final fileBytes = Uint8List(chunkBytes + 3);
      var chunkRequests = 0;
      final observedOffsets = <int>[];
      final client = ApiClient.test(
        MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/history-import/jobs') &&
              request.method == 'POST') {
            return _jsonResponse({
              'id': 'job-1',
              'status': 'UPLOADING',
              'uploadedBytes': 0,
              'expectedBytes': fileBytes.length,
            });
          }
          if (path.contains('/history-import/jobs/job-1/chunks')) {
            chunkRequests += 1;
            if (chunkRequests == 1) {
              throw const SocketException('response lost after server commit');
            }
            return _jsonResponse({
              'id': 'job-1',
              'status': 'UPLOADING',
              'uploadedBytes': fileBytes.length,
              'expectedBytes': fileBytes.length,
            });
          }
          if (path.contains('/history-import/jobs/job-1') &&
              request.method == 'GET') {
            return _jsonResponse({
              'id': 'job-1',
              'status': 'UPLOADING',
              'uploadedBytes': chunkBytes,
              'expectedBytes': fileBytes.length,
            });
          }
          if (path.contains('/history-import/jobs/job-1/complete')) {
            return _jsonResponse({
              'id': 'job-1',
              'status': 'QUEUED',
              'uploadedBytes': fileBytes.length,
              'expectedBytes': fileBytes.length,
            });
          }
          return http.Response('Not found', 404);
        }),
      );
      addTearDown(client.dispose);
      final repository = SalesReportRepository(client);

      final job = await repository.enqueueHistoryImport(
        SalesReportImportFile(
          name: 'history.csv',
          size: fileBytes.length,
          bytes: fileBytes,
        ),
        onJobChanged: (job) => observedOffsets.add(job.uploadedBytes),
      );

      expect(job.status, 'QUEUED');
      expect(chunkRequests, 2);
      expect(observedOffsets, [
        0,
        chunkBytes,
        fileBytes.length,
        fileBytes.length,
      ]);
    },
  );

  test(
    'three committed chunks with lost responses resume without destructive cleanup',
    () async {
      const chunkBytes = 4 * 1024 * 1024;
      final fileBytes = Uint8List(3 * chunkBytes);
      var serverAcknowledgedBytes = 0;
      var chunkRequests = 0;
      var cancelRequests = 0;
      var completeRequests = 0;
      final fetchedOffsets = <int>[];
      final client = ApiClient.test(
        MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/history-import/jobs') &&
              request.method == 'POST') {
            return _jsonResponse({
              'id': 'job-response-losses',
              'status': 'UPLOADING',
              'uploadedBytes': 0,
              'expectedBytes': fileBytes.length,
            });
          }
          if (path.endsWith(
            '/history-import/jobs/job-response-losses/chunks',
          )) {
            chunkRequests += 1;
            serverAcknowledgedBytes += chunkBytes;
            throw const SocketException('response lost after server commit');
          }
          if (path.endsWith('/history-import/jobs/job-response-losses') &&
              request.method == 'GET') {
            fetchedOffsets.add(serverAcknowledgedBytes);
            return _jsonResponse({
              'id': 'job-response-losses',
              'status': 'UPLOADING',
              'uploadedBytes': serverAcknowledgedBytes,
              'expectedBytes': fileBytes.length,
            });
          }
          if (path.endsWith(
                '/history-import/jobs/job-response-losses/cancel',
              ) &&
              request.method == 'POST') {
            cancelRequests += 1;
            return _jsonResponse({
              'id': 'job-response-losses',
              'status': 'CANCELLED',
              'uploadedBytes': serverAcknowledgedBytes,
              'expectedBytes': fileBytes.length,
            });
          }
          if (path.endsWith(
                '/history-import/jobs/job-response-losses/complete',
              ) &&
              request.method == 'POST') {
            completeRequests += 1;
            return _jsonResponse({
              'id': 'job-response-losses',
              'status': 'QUEUED',
              'uploadedBytes': serverAcknowledgedBytes,
              'expectedBytes': fileBytes.length,
            });
          }
          return http.Response('Not found', 404);
        }),
      );
      addTearDown(client.dispose);

      final job = await SalesReportRepository(client).enqueueHistoryImport(
        SalesReportImportFile(
          name: 'history.csv',
          size: fileBytes.length,
          bytes: fileBytes,
        ),
      );

      expect(chunkRequests, 3);
      expect(fetchedOffsets, [chunkBytes, 2 * chunkBytes, 3 * chunkBytes]);
      expect(cancelRequests, 0);
      expect(completeRequests, 1);
      expect(serverAcknowledgedBytes, fileBytes.length);
      expect(job.uploadedBytes, fileBytes.length);
      expect(job.status, 'QUEUED');
    },
  );

  test('cancelling aborts an in-flight multipart upload promptly', () async {
    final transport = _AbortAwareClient();
    final client = ApiClient.test(transport);
    addTearDown(client.dispose);
    final repository = SalesReportRepository(client);
    var cancelled = false;
    String? jobId;

    final upload = repository.enqueueHistoryImport(
      SalesReportImportFile(
        name: 'history.csv',
        size: 4,
        readStream: Stream.value(Uint8List.fromList([1, 2, 3, 4])),
      ),
      isCancelled: () => cancelled,
      onJobChanged: (job) => jobId = job.id,
    );
    await transport.multipartStarted.future;

    cancelled = true;
    repository.abortHistoryImportUpload(jobId!);

    await expectLater(
      upload.timeout(const Duration(seconds: 1)),
      throwsA(isA<SalesHistoryUploadCancelled>()),
    );
    await expectLater(
      transport.multipartAborted.future.timeout(const Duration(seconds: 1)),
      completes,
    );
  });

  test(
    'permanent chunk upload failure cancels the admitted job before surfacing the error',
    () async {
      var chunkAttempts = 0;
      var cancelRequests = 0;
      final observedStatuses = <String>[];
      final client = ApiClient.test(
        MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/history-import/jobs') &&
              request.method == 'POST') {
            return _jsonResponse({
              'id': 'job-permanent-failure',
              'status': 'UPLOADING',
              'uploadedBytes': 0,
              'expectedBytes': 4,
            });
          }
          if (path.contains(
            '/history-import/jobs/job-permanent-failure/chunks',
          )) {
            chunkAttempts += 1;
            return http.Response('upload rejected', 500);
          }
          if (path.endsWith('/history-import/jobs/job-permanent-failure') &&
              request.method == 'GET') {
            return _jsonResponse({
              'id': 'job-permanent-failure',
              'status': 'UPLOADING',
              'uploadedBytes': 0,
              'expectedBytes': 4,
            });
          }
          if (path.endsWith(
                '/history-import/jobs/job-permanent-failure/cancel',
              ) &&
              request.method == 'POST') {
            cancelRequests += 1;
            return _jsonResponse({
              'id': 'job-permanent-failure',
              'status': 'CANCELLED',
              'uploadedBytes': 0,
              'expectedBytes': 4,
            });
          }
          return http.Response('Not found', 404);
        }),
      );
      addTearDown(client.dispose);

      await expectLater(
        SalesReportRepository(client).enqueueHistoryImport(
          SalesReportImportFile(
            name: 'history.csv',
            size: 4,
            bytes: Uint8List.fromList([1, 2, 3, 4]),
          ),
          onJobChanged: (job) => observedStatuses.add(job.status),
        ),
        throwsA(isA<ApiException>()),
      );

      expect(chunkAttempts, 3);
      expect(cancelRequests, 1);
      expect(observedStatuses.last, 'CANCELLED');
    },
  );
}

http.Response _jsonResponse(Map<String, Object?> body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

class _AbortAwareClient extends http.BaseClient {
  final multipartStarted = Completer<void>();
  final multipartAborted = Completer<void>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.endsWith('/history-import/jobs')) {
      return _streamedJson({
        'id': 'job-abort',
        'status': 'UPLOADING',
        'uploadedBytes': 0,
        'expectedBytes': 4,
      });
    }
    if (path.contains('/history-import/jobs/job-abort/chunks')) {
      if (!multipartStarted.isCompleted) multipartStarted.complete();
      final abortTrigger =
          (request as http.AbortableMultipartRequest).abortTrigger!;
      await abortTrigger;
      if (!multipartAborted.isCompleted) multipartAborted.complete();
      throw http.RequestAbortedException(request.url);
    }
    return http.StreamedResponse(Stream.value(utf8.encode('Not found')), 404);
  }

  http.StreamedResponse _streamedJson(Map<String, Object?> body) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        200,
        headers: const {'content-type': 'application/json'},
      );
}
