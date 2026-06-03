import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/auth_device_info.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient().setAuthToken(null);
  });

  test('maps Flutter target platforms to auth session platforms', () {
    expect(
      AuthDeviceInfoProvider.platformName(
        platform: TargetPlatform.windows,
        isWeb: false,
      ),
      'windows',
    );
    expect(
      AuthDeviceInfoProvider.platformName(
        platform: TargetPlatform.android,
        isWeb: false,
      ),
      'android',
    );
    expect(
      AuthDeviceInfoProvider.platformName(
        platform: TargetPlatform.iOS,
        isWeb: false,
      ),
      'ios',
    );
    expect(
      AuthDeviceInfoProvider.platformName(
        platform: TargetPlatform.macOS,
        isWeb: false,
      ),
      'macos',
    );
    expect(
      AuthDeviceInfoProvider.platformName(
        platform: TargetPlatform.linux,
        isWeb: false,
      ),
      'linux',
    );
    expect(
      AuthDeviceInfoProvider.platformName(
        platform: TargetPlatform.windows,
        isWeb: true,
      ),
      'web',
    );
  });

  test('persists one app-local auth device id', () async {
    final provider = AuthDeviceInfoProvider(
      platformOverride: TargetPlatform.windows,
      isWebOverride: false,
      packageInfoLoader: () async => throw StateError('no package info'),
    );

    final first = await provider.load();
    final second = await provider.load();

    expect(first.platform, 'windows');
    expect(first.deviceId, isNotEmpty);
    expect(second.deviceId, first.deviceId);
  });

  test(
    'AuthRepository sends device payload during login and registration',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final repo = AuthRepository(
        ApiClient(),
        deviceInfoProvider: _FakeAuthDeviceInfoProvider(
          const AuthDevicePayload(
            platform: 'windows',
            deviceId: 'device-123456',
            deviceLabel: 'windows',
            appVersion: '1.1.1',
            buildNumber: '2',
          ),
        ),
        publicClient: MockClient((http.Request request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({
              'login': true,
              'access_token': 'jwt-token',
              'email': 'staff@phongvu.vn',
              'name': 'An',
              'role': 'STAFF',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await repo.login(email: 'staff@phongvu.vn', password: 'Password1!');
      await repo.register(
        firstName: 'An',
        email: 'staff@phongvu.vn',
        password: 'Password1!',
        verificationCode: '123456',
      );

      expect(bodies, hasLength(2));
      for (final body in bodies) {
        expect(body['platform'], 'windows');
        expect(body['deviceId'], 'device-123456');
        expect(body['deviceLabel'], 'windows');
        expect(body['appVersion'], '1.1.1');
        expect(body['buildNumber'], '2');
      }
    },
  );

  test('AuthRepository sends forgot-password code flow payloads', () async {
    final requests = <({String path, Map<String, dynamic> body})>[];
    final repo = AuthRepository(
      ApiClient(),
      publicClient: MockClient((http.Request request) async {
        requests.add((
          path: request.url.path,
          body: jsonDecode(request.body) as Map<String, dynamic>,
        ));
        if (request.url.path.endsWith('/auth/forgot-password/verify-code')) {
          return http.Response(
            jsonEncode({
              'ok': true,
              'resetToken': 'reset-token-1234567890',
              'expiresInMinutes': 10,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'ok': true, 'expiresInMinutes': 10}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await repo.requestPasswordReset(email: 'staff@phongvu.vn');
    final resetToken = await repo.verifyPasswordResetCode(
      email: 'staff@phongvu.vn',
      code: '123456',
    );
    await repo.resetForgottenPassword(
      resetToken: resetToken,
      newPassword: 'Password2!',
    );

    expect(requests, hasLength(3));
    expect(requests[0].path, endsWith('/auth/forgot-password'));
    expect(requests[0].body, {'email': 'staff@phongvu.vn'});
    expect(requests[1].path, endsWith('/auth/forgot-password/verify-code'));
    expect(requests[1].body, {'email': 'staff@phongvu.vn', 'code': '123456'});
    expect(requests[2].path, endsWith('/auth/reset-password'));
    expect(requests[2].body, {
      'token': 'reset-token-1234567890',
      'newPassword': 'Password2!',
    });
  });
}

class _FakeAuthDeviceInfoProvider extends AuthDeviceInfoProvider {
  _FakeAuthDeviceInfoProvider(this.payload);

  final AuthDevicePayload payload;

  @override
  Future<AuthDevicePayload> load() async => payload;
}
