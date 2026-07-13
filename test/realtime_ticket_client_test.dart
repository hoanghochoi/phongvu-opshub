import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phongvu_opshub/core/constants/api_constants.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/network/api_exception.dart';
import 'package:phongvu_opshub/core/network/realtime_ticket_client.dart';

void main() {
  test(
    'requests a one-time ticket and never places the JWT in the WS URL',
    () async {
      final oneTimeTicket = List.filled(43, 'a').join();
      late http.Request captured;
      final apiClient = ApiClient.test(
        MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'ticket': oneTimeTicket,
              'audience': 'opshub-realtime',
              'expiresAt': DateTime.now()
                  .toUtc()
                  .add(const Duration(seconds: 45))
                  .toIso8601String(),
              'expiresInSeconds': 45,
            }),
            200,
          );
        }),
      )..setAuthToken('long-lived-jwt');
      final client = RealtimeTicketClient(apiClient: apiClient);

      final uri = await client.issueConnectionUri(storeCode: 'cp01');

      expect(captured.url.path, endsWith(ApiConstants.realtimeTicketEndpoint));
      expect(captured.headers['authorization'], 'Bearer long-lived-jwt');
      expect(jsonDecode(captured.body), {'storeCode': 'CP01'});
      expect(uri.queryParameters['ticket'], oneTimeTicket);
      expect(uri.queryParameters['store_id'], 'CP01');
      expect(uri.queryParameters.containsKey('access_token'), isFalse);
      expect(uri.toString(), isNot(contains('long-lived-jwt')));
    },
  );

  test('rejects malformed or expired ticket responses', () async {
    final apiClient = ApiClient.test(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'ticket': 'short',
            'audience': 'wrong-audience',
            'expiresAt': DateTime.now()
                .toUtc()
                .subtract(const Duration(seconds: 1))
                .toIso8601String(),
          }),
          200,
        ),
      ),
    )..setAuthToken('jwt');

    await expectLater(
      RealtimeTicketClient(apiClient: apiClient).issueConnectionUri(),
      throwsA(isA<ApiException>()),
    );
  });
}
