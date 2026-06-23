import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/logging/app_logger.dart';
import 'payment_speaker_types.dart';
import 'payment_wav_tools.dart';

typedef PaymentMediaKitPlayer =
    Future<PaymentSpeakerResult> Function({
      required File file,
      required String extension,
      required Duration timeout,
      required double volume,
    });

typedef PaymentPlaySoundPlayer =
    Future<PaymentSpeakerResult> Function({
      required File file,
      required Duration timeout,
    });

typedef PaymentMciPlayer =
    Future<PaymentSpeakerResult> Function({
      required File file,
      required String extension,
      required Duration timeout,
    });

class PaymentSpeaker {
  static const _source = 'PaymentSpeaker';
  static const _voiceTimeout = Duration(seconds: 20);
  static const _cueTimeout = Duration(seconds: 5);
  static const _cueVolumePercent = 80.0;

  final PaymentMediaKitPlayer? _mediaKitPlayerForTesting;
  final PaymentPlaySoundPlayer? _playSoundPlayerForTesting;
  final PaymentMciPlayer? _mciPlayerForTesting;
  final Directory? _temporaryDirectoryForTesting;
  final int Function()? _waveOutDeviceCountForTesting;

  PaymentSpeaker({
    PaymentMediaKitPlayer? mediaKitPlayerForTesting,
    PaymentPlaySoundPlayer? playSoundPlayerForTesting,
    PaymentMciPlayer? mciPlayerForTesting,
    Directory? temporaryDirectoryForTesting,
    int Function()? waveOutDeviceCountForTesting,
  }) : _mediaKitPlayerForTesting = mediaKitPlayerForTesting,
       _playSoundPlayerForTesting = playSoundPlayerForTesting,
       _mciPlayerForTesting = mciPlayerForTesting,
       _temporaryDirectoryForTesting = temporaryDirectoryForTesting,
       _waveOutDeviceCountForTesting = waveOutDeviceCountForTesting;

  Future<PaymentSpeakerResult> playServerAudio({
    required int amount,
    required List<int>? audioBytes,
    required String notificationId,
    required String transactionId,
    required String storeCode,
    required String clientId,
    required int attempt,
    bool playLocalCue = true,
  }) async {
    if (!Platform.isWindows) {
      return const PaymentSpeakerResult(
        backend: 'unsupported',
        extension: 'wav',
        durationMs: 0,
        reportedSuccess: true,
        audibleVerified: false,
      );
    }

    if (audioBytes == null || audioBytes.isEmpty) {
      throw const PaymentSpeakerException('Server audio is empty');
    }

    final extension = _audioExtension(audioBytes);
    final waveOutDevices = _waveOutDeviceCount();
    final wavInfo = extension == 'wav'
        ? PaymentWavTools.tryReadInfo(audioBytes)
        : null;
    final audioPreflightStatus = waveOutDevices > 0
        ? 'wave_out_devices_available'
        : 'wave_out_devices_missing';
    final playbackContext = <String, Object?>{
      'notificationId': notificationId,
      'transactionId': transactionId,
      'storeCode': storeCode,
      'clientId': clientId,
      'amount': amount,
      'attempt': attempt,
      'extension': extension,
      'bytes': audioBytes.length,
      'waveOutDevices': waveOutDevices,
      'audioPreflightStatus': audioPreflightStatus,
      'playLocalCue': playLocalCue,
      if (wavInfo != null) ...wavInfo.toLogContext(prefix: 'sourceWav'),
      if (extension == 'wav' && wavInfo == null) 'wavHeader': 'unreadable',
    };
    await AppLogger.instance.info(
      _source,
      'Preparing server payment audio playback',
      context: playbackContext,
    );
    if (waveOutDevices <= 0) {
      throw const PaymentSpeakerException(
        'Windows does not report any audio output device',
        backendErrors: ['waveOutDevices=0'],
        retryable: false,
      );
    }

    final directory =
        _temporaryDirectoryForTesting ?? await getTemporaryDirectory();
    if (playLocalCue) {
      await _playTingTing(directory);
    }

    final file = File(
      '${directory.path}${Platform.pathSeparator}opshub-payment-${DateTime.now().microsecondsSinceEpoch}.$extension',
    );
    await file.writeAsBytes(audioBytes, flush: true);

    try {
      return await _playWithFallbacks(
        file: file,
        extension: extension,
        context: playbackContext,
        audioPreflightStatus: audioPreflightStatus,
      );
    } finally {
      await file.delete().catchError((_) => file);
    }
  }

  Future<void> _playTingTing(Directory directory) async {
    try {
      final asset = await rootBundle.load('data/ting_ting.mp3');
      final file = File(
        '${directory.path}${Platform.pathSeparator}opshub-ting-ting.mp3',
      );
      await file.writeAsBytes(asset.buffer.asUint8List(), flush: true);
      try {
        await AppLogger.instance.info(
          _source,
          'Payment sound cue playback started',
          context: {'cueVolumePercent': _cueVolumePercent},
        );
        final result = await _playWithMediaKit(
          file: file,
          extension: 'mp3',
          timeout: _cueTimeout,
          volume: _cueVolumePercent,
        );
        await AppLogger.instance.info(
          _source,
          'Payment sound cue playback succeeded',
          context: {
            'cueVolumePercent': _cueVolumePercent,
            'backend': result.backend,
            'durationMs': result.durationMs,
          },
        );
      } finally {
        await file.delete().catchError((_) => file);
      }
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

  Future<PaymentSpeakerResult> _playWithFallbacks({
    required File file,
    required String extension,
    required Map<String, Object?> context,
    required String audioPreflightStatus,
    bool allowMci326Normalize = true,
    bool normalized = false,
  }) async {
    final backendErrors = <String>[];
    final wavInfo = extension == 'wav' ? await _readWavInfo(file) : null;

    try {
      final result = await _playWithMediaKit(
        file: file,
        extension: extension,
        timeout: _voiceTimeout,
        volume: 100.0,
      );
      return _withAudioContext(
        result,
        wavInfo,
        normalized: normalized,
        audioPreflightStatus: audioPreflightStatus,
      );
    } catch (error) {
      backendErrors.add('media_kit: ${_safeBackendError(error)}');
      await AppLogger.instance.warn(
        _source,
        'media_kit playback failed; trying Windows fallback',
        context: {
          ...context,
          'normalized': normalized,
          'error': _safeBackendError(error),
        },
      );
    }

    if (extension == 'wav') {
      try {
        final result = await _playWithPlaySound(
          file: file,
          timeout: _voiceTimeout,
        );
        return _withAudioContext(
          result,
          wavInfo,
          normalized: normalized,
          audioPreflightStatus: audioPreflightStatus,
        );
      } catch (error) {
        backendErrors.add('play_sound: ${_safeBackendError(error)}');
        await AppLogger.instance.warn(
          _source,
          'PlaySound fallback failed; trying MCI fallback',
          context: {
            ...context,
            'normalized': normalized,
            'error': _safeBackendError(error),
          },
        );
      }
    }

    try {
      final result = await _playWithMci(
        file: file,
        extension: extension,
        timeout: _voiceTimeout,
      );
      return _withAudioContext(
        result,
        wavInfo,
        normalized: normalized,
        audioPreflightStatus: audioPreflightStatus,
      );
    } catch (error) {
      backendErrors.add('mci: ${_safeBackendError(error)}');
      await _logMciFailure(error, context, normalized: normalized);
      if (extension == 'wav' &&
          allowMci326Normalize &&
          _isMciCode(error, 326)) {
        final normalizedFile = await _createNormalizedWavForMci326(
          sourceFile: file,
          context: context,
        );
        if (normalizedFile != null) {
          try {
            return await _playWithFallbacks(
              file: normalizedFile.file,
              extension: 'wav',
              context: {
                ...context,
                'normalizeReason': 'mci326',
                'normalizedBytes': normalizedFile.result.bytes.length,
                ...normalizedFile.result.source.toLogContext(
                  prefix: 'originalWav',
                ),
                ...normalizedFile.result.target.toLogContext(
                  prefix: 'normalizedWav',
                ),
              },
              audioPreflightStatus: audioPreflightStatus,
              allowMci326Normalize: false,
              normalized: true,
            );
          } catch (normalizedError) {
            backendErrors.add(
              'normalized_wav: ${_safeBackendError(normalizedError)}',
            );
          } finally {
            await normalizedFile.file.delete().catchError(
              (_) => normalizedFile.file,
            );
          }
        }
      }
    }

    throw PaymentSpeakerException(
      'Payment speaker playback failed',
      backendErrors: backendErrors,
      retryable: !_isAudioEnvironmentFailure(backendErrors),
    );
  }

  Future<PaymentSpeakerResult> _playWithMediaKit({
    required File file,
    required String extension,
    required Duration timeout,
    required double volume,
  }) async {
    final override = _mediaKitPlayerForTesting;
    if (override != null) {
      return override(
        file: file,
        extension: extension,
        timeout: timeout,
        volume: volume,
      );
    }

    final stopwatch = Stopwatch()..start();
    final player = Player();
    try {
      final completed = player.stream.completed.firstWhere((value) => value);
      final failed = player.stream.error
          .where((message) => message.trim().isNotEmpty)
          .first
          .then<void>((message) {
            throw StateError('media_kit error: $message');
          });
      await player.setVolume(volume);
      await player.open(Media(file.uri.toString()), play: true);
      await Future.any<void>([completed.then((_) {}), failed]).timeout(timeout);
      return PaymentSpeakerResult(
        backend: 'media_kit',
        extension: extension,
        durationMs: stopwatch.elapsedMilliseconds,
        reportedSuccess: true,
        audibleVerified: false,
      );
    } finally {
      await player.stop().catchError((_) {});
      await player.dispose().catchError((_) {});
    }
  }

  Future<PaymentSpeakerResult> _playWithPlaySound({
    required File file,
    required Duration timeout,
  }) async {
    final override = _playSoundPlayerForTesting;
    if (override != null) {
      return override(file: file, timeout: timeout);
    }

    final waveDevices = _waveOutDeviceCount();
    if (waveDevices <= 0) {
      throw StateError('No wave output device is available for PlaySound');
    }
    final stopwatch = Stopwatch()..start();
    await Isolate.run(
      () => _playAudioFileWithPlaySound(file.path),
    ).timeout(timeout);
    return PaymentSpeakerResult(
      backend: 'play_sound',
      extension: 'wav',
      durationMs: stopwatch.elapsedMilliseconds,
      reportedSuccess: true,
      audibleVerified: false,
    );
  }

  Future<PaymentSpeakerResult> _playWithMci({
    required File file,
    required String extension,
    required Duration timeout,
  }) async {
    final override = _mciPlayerForTesting;
    if (override != null) {
      return override(file: file, extension: extension, timeout: timeout);
    }

    final stopwatch = Stopwatch()..start();
    await Isolate.run(
      () => _playAudioFileWithMci(
        file.path,
        type: extension == 'mp3' ? 'mpegvideo' : null,
      ),
    ).timeout(timeout);
    return PaymentSpeakerResult(
      backend: 'mci',
      extension: extension,
      durationMs: stopwatch.elapsedMilliseconds,
      reportedSuccess: true,
      audibleVerified: false,
    );
  }

  Future<PaymentWavInfo?> _readWavInfo(File file) async {
    try {
      return PaymentWavTools.readInfo(await file.readAsBytes());
    } on PaymentWavException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  PaymentSpeakerResult _withAudioContext(
    PaymentSpeakerResult result,
    PaymentWavInfo? wavInfo, {
    required bool normalized,
    required String audioPreflightStatus,
  }) {
    return result.copyWith(
      normalized: normalized || result.normalized,
      sampleRateHz: wavInfo?.sampleRateHz ?? result.sampleRateHz,
      channels: wavInfo?.channels ?? result.channels,
      bitsPerSample: wavInfo?.bitsPerSample ?? result.bitsPerSample,
      audioPreflightStatus: result.audioPreflightStatus ?? audioPreflightStatus,
    );
  }

  Future<void> _logMciFailure(
    Object error,
    Map<String, Object?> context, {
    required bool normalized,
  }) async {
    await AppLogger.instance.warn(
      _source,
      'MCI playback failed',
      context: {
        ...context,
        'normalized': normalized,
        if (error is MciCommandException) 'mciCode': error.code,
        if (error is MciCommandException) 'mciMessage': error.message,
        'error': _safeBackendError(error),
      },
    );
  }

  Future<_NormalizedWavFile?> _createNormalizedWavForMci326({
    required File sourceFile,
    required Map<String, Object?> context,
  }) async {
    try {
      final sourceBytes = await sourceFile.readAsBytes();
      final sourceInfo = PaymentWavTools.readInfo(sourceBytes);
      if (_isAlreadyPcm16Mono44100(sourceInfo)) {
        await AppLogger.instance.warn(
          _source,
          'MCI 326 normalize fallback skipped because WAV is already normalized',
          context: {
            ...context,
            'normalizeReason': 'mci326',
            ...sourceInfo.toLogContext(prefix: 'sourceWav'),
          },
        );
        return null;
      }

      final normalized = PaymentWavTools.normalizeToPcm16Mono44100(sourceBytes);
      final file = File(
        '${sourceFile.parent.path}${Platform.pathSeparator}opshub-payment-normalized-${DateTime.now().microsecondsSinceEpoch}.wav',
      );
      await file.writeAsBytes(normalized.bytes, flush: true);
      await AppLogger.instance.info(
        _source,
        'Payment WAV normalized for MCI 326 fallback',
        context: {
          ...context,
          'normalizeReason': 'mci326',
          'originalBytes': sourceBytes.length,
          'normalizedBytes': normalized.bytes.length,
          ...normalized.source.toLogContext(prefix: 'originalWav'),
          ...normalized.target.toLogContext(prefix: 'normalizedWav'),
        },
      );
      return _NormalizedWavFile(file, normalized);
    } catch (error) {
      await AppLogger.instance.warn(
        _source,
        'Payment WAV normalize fallback skipped',
        context: {
          ...context,
          'normalizeReason': 'mci326',
          'error': _safeBackendError(error),
        },
      );
      return null;
    }
  }

  bool _isAlreadyPcm16Mono44100(PaymentWavInfo info) {
    return info.isPcm16 &&
        info.channels == 1 &&
        info.sampleRateHz == PaymentWavTools.targetSampleRateHz;
  }

  bool _isMciCode(Object error, int code) {
    return error is MciCommandException && error.code == code;
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

  int _waveOutDeviceCount() {
    final override = _waveOutDeviceCountForTesting;
    if (override != null) return override();

    final winmm = DynamicLibrary.open('winmm.dll');
    final waveOutGetNumDevs = winmm
        .lookupFunction<_WaveOutGetNumDevsNative, _WaveOutGetNumDevsDart>(
          'waveOutGetNumDevs',
        );
    return waveOutGetNumDevs();
  }

  String _safeBackendError(Object error) {
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length <= 180 ? text : '${text.substring(0, 177)}...';
  }

  bool _isAudioEnvironmentFailure(List<String> backendErrors) {
    final text = backendErrors.join(' ').toLowerCase();
    return text.contains('waveoutdevices=0') ||
        text.contains('no wave output device') ||
        text.contains('no wave device') ||
        text.contains('mci command failed (326)') ||
        text.contains('mci command failed (277)');
  }
}

class MciCommandException implements Exception {
  final int code;
  final String message;

  const MciCommandException(this.code, this.message);

  @override
  String toString() => 'Windows MCI command failed ($code): $message';
}

class _NormalizedWavFile {
  final File file;
  final PaymentWavNormalizeResult result;

  const _NormalizedWavFile(this.file, this.result);
}

typedef _PlaySoundNative = Int32 Function(Pointer<Utf16>, IntPtr, Uint32);
typedef _PlaySoundDart = int Function(Pointer<Utf16>, int, int);
typedef _WaveOutGetNumDevsNative = Uint32 Function();
typedef _WaveOutGetNumDevsDart = int Function();
typedef _MciSendStringNative =
    Uint32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32, IntPtr);
typedef _MciSendStringDart =
    int Function(Pointer<Utf16>, Pointer<Utf16>, int, int);
typedef _MciGetErrorStringNative =
    Int32 Function(Uint32, Pointer<Utf16>, Uint32);
typedef _MciGetErrorStringDart = int Function(int, Pointer<Utf16>, int);

void _playAudioFileWithPlaySound(String path) {
  final winmm = DynamicLibrary.open('winmm.dll');
  final playSound = winmm.lookupFunction<_PlaySoundNative, _PlaySoundDart>(
    'PlaySoundW',
  );
  final nativePath = path.toNativeUtf16();
  const sndFilename = 0x00020000;
  const sndSync = 0x0000;
  const sndNodefault = 0x0002;
  try {
    final ok = playSound(nativePath, 0, sndFilename | sndSync | sndNodefault);
    if (ok == 0) {
      throw StateError('PlaySoundW failed to play WAV audio');
    }
  } finally {
    calloc.free(nativePath);
  }
}

void _playAudioFileWithMci(String path, {String? type}) {
  final alias = 'opshub${DateTime.now().microsecondsSinceEpoch}';
  try {
    final openCommand = type == null
        ? 'open "${_escapeMciPath(path)}" alias $alias'
        : 'open "${_escapeMciPath(path)}" type $type alias $alias';
    _sendMciCommand(openCommand);
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
      throw MciCommandException(code, _mciErrorMessage(winmm, code));
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
