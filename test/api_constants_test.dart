import 'package:flutter_test/flutter_test.dart';

import 'package:phongvu_opshub/core/constants/api_constants.dart';

void main() {
  test('default contract uses the new production API, web and realtime hosts', () {
    expect(ApiConstants.baseUrl, 'https://api.phongvu.work/v1');
    expect(ApiConstants.publicBaseUri.toString(), 'https://phongvu.work');
    expect(
      ApiConstants.realtimeWsUri(ticket: ' ticket ').toString(),
      'wss://api.phongvu.work/v1/ws?ticket=ticket',
    );
    expect(
      ApiConstants.appUpdateRealtimeWsUrl,
      'wss://api.phongvu.work/v1/ws/app-updates',
    );
  });
}
