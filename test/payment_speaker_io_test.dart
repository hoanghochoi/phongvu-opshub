import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/payment_speaker_io.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/payment_speaker_types.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/payment_wav_tools.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  test(
    'normalizes WAV once after MCI 326 and plays the normalized file',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'opshub-speaker-test-',
      );
      final mciSampleRates = <int>[];
      try {
        final speaker = PaymentSpeaker(
          temporaryDirectoryForTesting: temp,
          waveOutDeviceCountForTesting: () => 1,
          mediaKitPlayerForTesting:
              ({
                required file,
                required extension,
                required timeout,
                required volume,
              }) async {
                throw StateError('media_kit disabled for test');
              },
          playSoundPlayerForTesting: ({required file, required timeout}) async {
            throw StateError('PlaySound disabled for test');
          },
          mciPlayerForTesting:
              ({required file, required extension, required timeout}) async {
                final info = PaymentWavTools.readInfo(await file.readAsBytes());
                mciSampleRates.add(info.sampleRateHz);
                if (info.sampleRateHz != PaymentWavTools.targetSampleRateHz) {
                  throw const MciCommandException(
                    326,
                    'No wave device can play files in the current format.',
                  );
                }
                return const PaymentSpeakerResult(
                  backend: 'mci',
                  extension: 'wav',
                  durationMs: 1,
                  reportedSuccess: true,
                  audibleVerified: false,
                );
              },
        );

        final result = await speaker.playServerAudio(
          amount: 1250000,
          audioBytes: _pcm16Wav(
            sampleRateHz: 22050,
            channels: 1,
            frames: const [
              [0],
              [1000],
              [-1000],
              [2000],
            ],
          ),
          notificationId: 'note-1',
          transactionId: 'txn-1',
          storeCode: 'CP01',
          clientId: 'pc-test',
          attempt: 1,
        );

        expect(result.backend, 'mci');
        expect(result.normalized, isTrue);
        expect(result.sampleRateHz, 44100);
        expect(result.channels, 1);
        expect(result.bitsPerSample, 16);
        expect(mciSampleRates, [22050, 44100]);
        expect(
          temp.listSync().where(
            (entry) => entry.path.contains('opshub-payment-normalized-'),
          ),
          isEmpty,
        );
      } finally {
        await temp.delete(recursive: true).catchError((_) => temp);
      }
    },
  );

  test('skips local cue when server audio already includes it', () async {
    final temp = await Directory.systemTemp.createTemp('opshub-speaker-test-');
    var mediaKitCalls = 0;
    try {
      final speaker = PaymentSpeaker(
        temporaryDirectoryForTesting: temp,
        waveOutDeviceCountForTesting: () => 1,
        mediaKitPlayerForTesting:
            ({
              required file,
              required extension,
              required timeout,
              required volume,
            }) async {
              mediaKitCalls += 1;
              expect(volume, 100.0);
              throw StateError('media_kit disabled for test');
            },
        playSoundPlayerForTesting: ({required file, required timeout}) async {
          return const PaymentSpeakerResult(
            backend: 'playsound',
            extension: 'wav',
            durationMs: 1,
            reportedSuccess: true,
            audibleVerified: false,
          );
        },
      );

      final result = await speaker.playServerAudio(
        amount: 1250000,
        audioBytes: _pcm16Wav(
          sampleRateHz: 22050,
          channels: 1,
          frames: const [
            [0],
            [1000],
          ],
        ),
        notificationId: 'note-1',
        transactionId: 'txn-1',
        storeCode: 'CP01',
        clientId: 'pc-test',
        attempt: 1,
        playLocalCue: false,
      );

      expect(result.backend, 'playsound');
      expect(mediaKitCalls, 1);
    } finally {
      await temp.delete(recursive: true).catchError((_) => temp);
    }
  });

  test(
    'plays fallback cue at 80 percent and keeps voice at 100 percent',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'opshub-speaker-test-',
      );
      final playbackVolumes = <String, double>{};
      try {
        final speaker = PaymentSpeaker(
          temporaryDirectoryForTesting: temp,
          waveOutDeviceCountForTesting: () => 1,
          mediaKitPlayerForTesting:
              ({
                required file,
                required extension,
                required timeout,
                required volume,
              }) async {
                playbackVolumes[extension] = volume;
                if (extension == 'wav') {
                  throw StateError('media_kit voice disabled for test');
                }
                return PaymentSpeakerResult(
                  backend: 'media_kit',
                  extension: extension,
                  durationMs: 1,
                  reportedSuccess: true,
                  audibleVerified: false,
                );
              },
          playSoundPlayerForTesting: ({required file, required timeout}) async {
            return const PaymentSpeakerResult(
              backend: 'playsound',
              extension: 'wav',
              durationMs: 1,
              reportedSuccess: true,
              audibleVerified: false,
            );
          },
        );

        final result = await speaker.playServerAudio(
          amount: 1250000,
          audioBytes: _pcm16Wav(
            sampleRateHz: 22050,
            channels: 1,
            frames: const [
              [0],
              [1000],
            ],
          ),
          notificationId: 'note-1',
          transactionId: 'txn-1',
          storeCode: 'CP01',
          clientId: 'pc-test',
          attempt: 1,
          playLocalCue: true,
        );

        expect(result.backend, 'playsound');
        expect(playbackVolumes, {'mp3': 80.0, 'wav': 100.0});
      } finally {
        await temp.delete(recursive: true).catchError((_) => temp);
      }
    },
  );

  test('plays local cue-prefix asset before raw amount audio', () async {
    final temp = await Directory.systemTemp.createTemp('opshub-speaker-test-');
    final playedFiles = <String>[];
    final playbackVolumes = <double>[];
    try {
      final speaker = PaymentSpeaker(
        temporaryDirectoryForTesting: temp,
        waveOutDeviceCountForTesting: () => 1,
        mediaKitPlayerForTesting:
            ({
              required file,
              required extension,
              required timeout,
              required volume,
            }) async {
              playedFiles.add(file.path);
              playbackVolumes.add(volume);
              return PaymentSpeakerResult(
                backend: 'media_kit',
                extension: extension,
                durationMs: 1,
                reportedSuccess: true,
                audibleVerified: false,
              );
            },
      );

      final result = await speaker.playServerAudio(
        amount: 1250000,
        audioBytes: _pcm16Wav(
          sampleRateHz: 22050,
          channels: 1,
          frames: const [
            [0],
            [1000],
          ],
        ),
        notificationId: 'note-1',
        transactionId: 'txn-1',
        storeCode: 'CP01',
        clientId: 'pc-test',
        attempt: 1,
        playLocalCue: false,
        playLocalCuePrefix: true,
      );

      expect(result.backend, 'media_kit');
      expect(playedFiles, hasLength(2));
      expect(playedFiles.first, contains('opshub-payment-cue-prefix.wav'));
      expect(playedFiles.last, contains('opshub-payment-'));
      expect(playbackVolumes, [100.0, 100.0]);
    } finally {
      await temp.delete(recursive: true).catchError((_) => temp);
    }
  });
}

Uint8List _pcm16Wav({
  required int sampleRateHz,
  required int channels,
  required List<List<int>> frames,
}) {
  final blockAlign = channels * 2;
  final dataBytes = frames.length * blockAlign;
  final bytes = Uint8List(44 + dataBytes);
  _writeAscii(bytes, 0, 'RIFF');
  _writeUint32(bytes, 4, 36 + dataBytes);
  _writeAscii(bytes, 8, 'WAVE');
  _writeAscii(bytes, 12, 'fmt ');
  _writeUint32(bytes, 16, 16);
  _writeUint16(bytes, 20, 1);
  _writeUint16(bytes, 22, channels);
  _writeUint32(bytes, 24, sampleRateHz);
  _writeUint32(bytes, 28, sampleRateHz * blockAlign);
  _writeUint16(bytes, 32, blockAlign);
  _writeUint16(bytes, 34, 16);
  _writeAscii(bytes, 36, 'data');
  _writeUint32(bytes, 40, dataBytes);
  var offset = 44;
  for (final frame in frames) {
    for (final sample in frame) {
      ByteData.sublistView(bytes).setInt16(offset, sample, Endian.little);
      offset += 2;
    }
  }
  return bytes;
}

void _writeAscii(Uint8List bytes, int offset, String text) {
  for (var i = 0; i < text.length; i += 1) {
    bytes[offset + i] = text.codeUnitAt(i);
  }
}

void _writeUint16(Uint8List bytes, int offset, int value) {
  ByteData.sublistView(bytes).setUint16(offset, value, Endian.little);
}

void _writeUint32(Uint8List bytes, int offset, int value) {
  ByteData.sublistView(bytes).setUint32(offset, value, Endian.little);
}
