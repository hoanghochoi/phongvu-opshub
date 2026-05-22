import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
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
      final directory = await getTemporaryDirectory();
      await _playTingTing(directory);
      if (audioBytes == null || audioBytes.isEmpty) {
        throw StateError('Server audio is empty');
      }

      final extension = _audioExtension(audioBytes);
      final file = File(
        '${directory.path}${Platform.pathSeparator}opshub-payment-${DateTime.now().microsecondsSinceEpoch}.$extension',
      );
      await file.writeAsBytes(audioBytes, flush: true);
      await AppLogger.instance.info(
        _source,
        'Playing server payment audio through Windows MCI',
        context: {
          'amount': amount,
          'extension': extension,
          'bytes': audioBytes.length,
          'path': file.path,
        },
      );
      try {
        await _playAudioFile(file.path, const Duration(seconds: 20));
      } finally {
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

  Future<void> _playTingTing(Directory directory) async {
    try {
      await AppLogger.instance.info(
        _source,
        'Loading payment sound cue',
        context: {'asset': 'data/ting_ting.mp3'},
      );
      final asset = await rootBundle.load('data/ting_ting.mp3');
      final file = File(
        '${directory.path}${Platform.pathSeparator}opshub-ting-ting.mp3',
      );
      await file.writeAsBytes(asset.buffer.asUint8List(), flush: true);
      await AppLogger.instance.info(
        _source,
        'Playing payment sound cue through Windows MCI',
        context: {'bytes': asset.lengthInBytes, 'path': file.path},
      );
      await _playAudioFile(file.path, const Duration(seconds: 5));
    } catch (error, stackTrace) {
      await AppLogger.instance.warn(
        _source,
        'Payment sound cue skipped',
        context: {
          'error': error.toString(),
          'stackTrace': stackTrace.toString(),
        },
      );
    }
  }

  Future<void> _playAudioFile(String path, Duration timeout) {
    return Isolate.run(() => _playAudioFileWithMci(path)).timeout(timeout);
  }
}

typedef _MciSendStringNative =
    Uint32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32, IntPtr);
typedef _MciSendStringDart =
    int Function(Pointer<Utf16>, Pointer<Utf16>, int, int);
typedef _MciGetErrorStringNative =
    Int32 Function(Uint32, Pointer<Utf16>, Uint32);
typedef _MciGetErrorStringDart = int Function(int, Pointer<Utf16>, int);

void _playAudioFileWithMci(String path) {
  final alias = 'opshub${DateTime.now().microsecondsSinceEpoch}';
  final type = path.toLowerCase().endsWith('.mp3') ? 'mpegvideo' : 'waveaudio';
  try {
    _sendMciCommand('open "${_escapeMciPath(path)}" type $type alias $alias');
    _sendMciCommand('play $alias wait');
  } finally {
    _sendMciCommand('close $alias', throwOnError: false);
  }
}

void _sendMciCommand(String command, {bool throwOnError = true}) {
  final winmm = DynamicLibrary.open('winmm.dll');
  final mciSendString = winmm
      .lookupFunction<_MciSendStringNative, _MciSendStringDart>(
        'mciSendStringW',
      );
  final nativeCommand = command.toNativeUtf16();
  try {
    final code = mciSendString(nativeCommand, nullptr, 0, 0);
    if (code != 0 && throwOnError) {
      throw StateError(
        'Windows MCI command failed ($code): ${_mciErrorMessage(winmm, code)}',
      );
    }
  } finally {
    calloc.free(nativeCommand);
  }
}

String _mciErrorMessage(DynamicLibrary winmm, int code) {
  final mciGetErrorString = winmm
      .lookupFunction<_MciGetErrorStringNative, _MciGetErrorStringDart>(
        'mciGetErrorStringW',
      );
  final buffer = calloc<Uint16>(256).cast<Utf16>();
  try {
    final ok = mciGetErrorString(code, buffer, 256);
    return ok == 0 ? 'Unknown MCI error' : buffer.toDartString();
  } finally {
    calloc.free(buffer);
  }
}

String _escapeMciPath(String path) {
  return path.replaceAll('"', '');
}
