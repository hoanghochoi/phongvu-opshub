import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/network/private_media_headers.dart';

void main() {
  const baseUrl = 'https://opshub.example.test/api';

  group('privateMediaHeaders', () {
    tearDown(() => ApiClient().setAuthToken(null));

    test('uses the active ApiClient token for protected media', () {
      ApiClient().setAuthToken('active-session-token');

      expect(
        privateMediaHeaders(
          'https://opshub.example.test/api/media/object-1',
          apiBaseUrl: baseUrl,
        ),
        const <String, String>{'Authorization': 'Bearer active-session-token'},
      );
    });

    test('attaches bearer token only to protected media on the API origin', () {
      expect(
        privateMediaHeaders(
          'https://opshub.example.test/api/media/object-1?expires=123',
          apiBaseUrl: baseUrl,
          authToken: 'session-token',
        ),
        const <String, String>{'Authorization': 'Bearer session-token'},
      );
    });

    test('does not attach credentials to an external media URL', () {
      expect(
        privateMediaHeaders(
          'https://cdn.example.test/api/media/object-1',
          apiBaseUrl: baseUrl,
          authToken: 'session-token',
        ),
        isEmpty,
      );
    });

    test('rejects same-host URLs containing user info', () {
      expect(
        privateMediaHeaders(
          'https://attacker@opshub.example.test/api/media/object-1',
          apiBaseUrl: baseUrl,
          authToken: 'session-token',
        ),
        isEmpty,
      );
    });

    test('does not attach credentials to a same-origin legacy upload URL', () {
      expect(
        privateMediaHeaders(
          'https://opshub.example.test/uploads/warranty/photo.jpg',
          apiBaseUrl: baseUrl,
          authToken: 'session-token',
        ),
        isEmpty,
      );
    });

    test('does not attach an empty token', () {
      expect(
        privateMediaHeaders(
          'https://opshub.example.test/api/media/object-1',
          apiBaseUrl: baseUrl,
          authToken: '  ',
        ),
        isEmpty,
      );
    });
  });
}
