import 'dart:io';

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
        'windows/assets/payment_audio/piper_vi_vais1000_chunk_v1',
      ),
    );

    final result = await composer.compose(
      amount: 1250000,
      assetPackVersion: paymentAmountAudioPackVersion,
    );
    final info = PaymentWavTools.readInfo(result.bytes);

    expect(result.assetIds, [
      'chunk/leading/001',
      'chunk/unit/triệu',
      'chunk/leading/250',
      'chunk/unit/nghìn',
      'chunk/unit/đồng',
    ]);
    expect(info.sampleRateHz, 24000);
    expect(info.channels, 1);
    expect(info.bitsPerSample, 16);
    expect(info.dataBytes, greaterThan(0));
  });
}
