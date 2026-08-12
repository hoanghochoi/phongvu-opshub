import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/payment_amount_audio_composer_io.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/payment_amount_audio_composer_types.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/payment_wav_tools.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => AppLogger.instance.setUploadsEnabledForTesting(false));
  tearDown(() => AppLogger.instance.setUploadsEnabledForTesting(true));

  test('maps VND amounts to canonical three-digit chunk assets', () {
    expect(paymentAmountChunkAssetIds(1), [
      'chunk/leading/001',
      'chunk/unit/đồng',
    ]);
    expect(paymentAmountChunkAssetIds(1005005), [
      'chunk/leading/001',
      'chunk/unit/triệu',
      'chunk/forced/005',
      'chunk/unit/nghìn',
      'chunk/forced/005',
      'chunk/unit/đồng',
    ]);
    expect(paymentAmountChunkAssetIds(999999999999999999), hasLength(14));
    expect(() => paymentAmountChunkAssetIds(0), throwsArgumentError);
    expect(
      () => paymentAmountChunkAssetIds(1000000000000000000),
      throwsArgumentError,
    );
  });

  test('composes reviewed Piper assets without changing WAV policy', () async {
    final composer = PaymentAmountAudioComposerIo(
      packDirectoryForTesting: Directory(
        'windows/assets/payment_audio/local_preset_speaker_v1',
      ),
    );

    final result = await composer.compose(
      amount: 1250000,
      assetPackVersion: paymentAmountAudioPackVersion,
      voicePresetId: defaultPaymentAudioVoicePresetId,
    );
    final info = PaymentWavTools.readInfo(result.bytes);

    expect(result.assetIds, [
      'chunk/leading/001',
      'chunk/unit/triệu',
      'chunk/leading/250',
      'chunk/unit/nghìn',
      'chunk/unit/đồng',
    ]);
    expect(info.sampleRateHz, 22050);
    expect(info.channels, 1);
    expect(info.bitsPerSample, 16);
    expect(info.dataBytes, greaterThan(0));
    expect(PaymentWavTools.readInfo(result.prefixBytes).sampleRateHz, 22050);
    expect(result.voicePresetId, defaultPaymentAudioVoicePresetId);
  });

  test('preserves the reviewed currency tail for every voice preset', () async {
    final composer = PaymentAmountAudioComposerIo(
      packDirectoryForTesting: Directory(
        'windows/assets/payment_audio/local_preset_speaker_v1',
      ),
    );

    for (final preset in paymentAudioVoicePresets) {
      final result = await composer.compose(
        amount: 1,
        assetPackVersion: paymentAmountAudioPackVersion,
        voicePresetId: preset.id,
      );
      final info = PaymentWavTools.readInfo(result.bytes);
      final trailingSilentFrames = _trailingSilentFrames(result.bytes, info);
      final trailingSilenceMs = trailingSilentFrames * 1000 / info.sampleRateHz;

      expect(
        trailingSilenceMs,
        inInclusiveRange(180, 260),
        reason: '${preset.id} must retain its reviewed natural currency tail',
      );
    }
  });
}

int _trailingSilentFrames(Uint8List bytes, PaymentWavInfo info) {
  final data = ByteData.sublistView(bytes);
  var silentFrames = 0;
  for (var frame = info.frameCount - 1; frame >= 0; frame -= 1) {
    final offset = info.dataOffset + frame * info.blockAlign;
    if (data.getInt16(offset, Endian.little) != 0) break;
    silentFrames += 1;
  }
  return silentFrames;
}
