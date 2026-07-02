import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';

void main() {
  test('app log upload payload keeps environment inside context', () {
    final body = AppLogger.instance.buildUploadBodyForTesting(
      'error',
      'Zone',
      'Uncaught async error',
      context: {'reason': 'websocket-close'},
      storeCode: 'CH001',
    );

    expect(body, isNot(contains('environment')));
    expect(body['level'], 'error');
    expect(body['source'], 'Zone');
    expect(body['message'], 'Uncaught async error');
    expect(body['storeCode'], 'CH001');

    final context = body['context'] as Map<String, Object?>;
    expect(context['environment'], isA<String>());
    expect(context['reason'], 'websocket-close');
  });
}
