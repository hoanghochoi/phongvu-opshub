import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/platform/media_kit_bootstrap.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/payment_amount_audio_composer_io.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/payment_amount_audio_composer_types.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/payment_speaker_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Manual smoke is test-only even though it lives outside test/ so the full
    // suite never plays audible output automatically.
    // ignore: invalid_use_of_visible_for_testing_member
    AppLogger.instance.setUploadsEnabledForTesting(false);
    await initializeMediaKitIfSupported(
      isWebOverride: false,
      platformOverride: TargetPlatform.windows,
    );
  });

  tearDownAll(() {
    // ignore: invalid_use_of_visible_for_testing_member
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  test(
    'plays a local payment announcement through the Windows speaker',
    () async {
      if (!Platform.isWindows) {
        fail('Payment speaker smoke requires Windows.');
      }
      final temp = await Directory.systemTemp.createTemp(
        'opshub-payment-speaker-smoke-',
      );
      final composer = PaymentAmountAudioComposerIo(
        packDirectoryForTesting: Directory(
          'windows/assets/payment_audio/local_preset_speaker_v1',
        ),
      );
      final speaker = PaymentSpeaker(temporaryDirectoryForTesting: temp);

      try {
        for (final preset in paymentAudioVoicePresets) {
          final audio = await composer.compose(
            amount: 123000,
            assetPackVersion: paymentAmountAudioPackVersion,
            voicePresetId: preset.id,
          );
          final result = await speaker.playServerAudio(
            amount: 123000,
            audioBytes: audio.bytes,
            notificationId: 'manual-smoke-${preset.id}',
            transactionId: 'manual-smoke',
            storeCode: 'LOCAL',
            clientId: 'manual-smoke',
            attempt: 1,
            localPrefixBytes: audio.prefixBytes,
            playLocalCue: false,
            playLocalCuePrefix: true,
          );

          expect(result.reportedSuccess, isTrue);
          expect(result.durationMs, greaterThan(0));
          // Visible terminal evidence supplements the required listening check.
          // ignore: avoid_print
          print(
            'PAYMENT_SPEAKER_SMOKE voice=${preset.id} '
            'backend=${result.backend} durationMs=${result.durationMs}',
          );
        }
      } finally {
        await temp.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
