import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/logging/app_logger.dart';

class PaymentSpeaker {
  static const _source = 'PaymentSpeaker';

  Future<void> playServerAudio({
    required int amount,
    required List<int>? audioBytes,
  }) async {
    if (!Platform.isWindows) return;
    try {
      await AppLogger.instance.info(
        _source,
        'Preparing server payment audio playback',
        context: {
          'amount': amount,
          'hasAudioBytes': audioBytes != null && audioBytes.isNotEmpty,
          'bytes': audioBytes?.length ?? 0,
        },
      );
      await _playTingTing();
      if (audioBytes == null || audioBytes.isEmpty) {
        throw StateError('Server audio is empty');
      }

      final directory = await getTemporaryDirectory();
      final extension = _audioExtension(audioBytes);
      final file = File(
        '${directory.path}${Platform.pathSeparator}opshub-payment-${DateTime.now().microsecondsSinceEpoch}.$extension',
      );
      await file.writeAsBytes(audioBytes, flush: true);
      await AppLogger.instance.info(
        _source,
        'Playing server payment audio',
        context: {
          'amount': amount,
          'extension': extension,
          'bytes': audioBytes.length,
          'path': file.path,
        },
      );
      final player = AudioPlayer();
      try {
        await player.play(DeviceFileSource(file.path));
        await player.onPlayerComplete.first.timeout(
          const Duration(seconds: 20),
        );
      } finally {
        await player.dispose();
        await file.delete().catchError((_) => file);
      }
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        _source,
        'Server audio playback failed',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  String _audioExtension(List<int> audioBytes) {
    if (audioBytes.length >= 4 &&
        audioBytes[0] == 0x52 &&
        audioBytes[1] == 0x49 &&
        audioBytes[2] == 0x46 &&
        audioBytes[3] == 0x46) {
      return 'wav';
    }
    return 'mp3';
  }

  Future<void> _playTingTing() async {
    final player = AudioPlayer();
    try {
      await AppLogger.instance.info(
        _source,
        'Loading payment sound cue',
        context: {'asset': 'data/ting_ting.mp3'},
      );
      final asset = await rootBundle.load('data/ting_ting.mp3');
      await AppLogger.instance.info(
        _source,
        'Playing payment sound cue',
        context: {'bytes': asset.lengthInBytes},
      );
      await player.play(BytesSource(asset.buffer.asUint8List()));
      await player.onPlayerComplete.first.timeout(const Duration(seconds: 5));
    } finally {
      await player.dispose();
    }
  }
}
