import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/logging/app_logger.dart';
import 'vietnamese_amount_words.dart';

class PaymentSpeaker {
  static const _source = 'PaymentSpeaker';

  Future<void> speakAmount(int amount) async {
    if (!Platform.isWindows) return;
    await _playTingTing();
    await _speakWithWindowsSapi(amount);
  }

  Future<void> playServerAudio({
    required int amount,
    required List<int>? audioBytes,
  }) async {
    if (!Platform.isWindows) return;
    await _playTingTing();
    if (audioBytes == null || audioBytes.isEmpty) {
      throw StateError('Server audio is empty');
    }

    try {
      final directory = await getTemporaryDirectory();
      final extension = _audioExtension(audioBytes);
      final file = File(
        '${directory.path}${Platform.pathSeparator}opshub-payment-${DateTime.now().microsecondsSinceEpoch}.$extension',
      );
      await file.writeAsBytes(audioBytes, flush: true);
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
      final asset = await rootBundle.load('data/ting_ting.mp3');
      await player.play(BytesSource(asset.buffer.asUint8List()));
      await player.onPlayerComplete.first.timeout(const Duration(seconds: 5));
    } finally {
      await player.dispose();
    }
  }

  Future<void> _speakWithWindowsSapi(int amount) async {
    final speechText = 'Đã nhận ${vietnameseAmountWords(amount)} đồng';
    final script = r'''
& {
[CmdletBinding()]
param([string]$text)
Add-Type -AssemblyName System.Speech
$speaker = New-Object System.Speech.Synthesis.SpeechSynthesizer
$speaker.Rate = 0
$speaker.Volume = 100
$voice = $speaker.GetInstalledVoices() |
  Where-Object {
    $_.VoiceInfo.Culture.Name -like 'vi-*' -or
    $_.VoiceInfo.Name -match 'Vietnam|Vietnamese|An'
  } |
  Select-Object -First 1
if ($null -ne $voice) {
  $speaker.SelectVoice($voice.VoiceInfo.Name)
}
$speaker.Speak($text)
}
''';
    await Process.run('powershell.exe', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      script,
      speechText,
    ], runInShell: false);
  }
}
