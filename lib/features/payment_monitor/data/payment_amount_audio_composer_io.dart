import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../core/logging/app_logger.dart';
import 'payment_amount_audio_composer_types.dart';
import 'payment_wav_tools.dart';

const _paymentAmountMaxSupportedVnd = 999999999999999999;

List<String> paymentAmountChunkAssetIds(int amount) {
  if (amount <= 0 || amount > _paymentAmountMaxSupportedVnd) {
    throw ArgumentError.value(
      amount,
      'amount',
      'Amount is outside the supported VND range',
    );
  }
  const units = ['', 'nghìn', 'triệu', 'tỷ', 'nghìn tỷ', 'triệu tỷ'];
  final groups = <int>[];
  var remaining = amount;
  while (remaining > 0) {
    groups.add(remaining % 1000);
    remaining ~/= 1000;
  }
  if (groups.length > units.length) {
    throw ArgumentError.value(
      amount,
      'amount',
      'Amount has too many three-digit groups',
    );
  }

  final highest = groups.length - 1;
  final ids = <String>[];
  for (var index = highest; index >= 0; index -= 1) {
    final value = groups[index];
    if (value == 0) continue;
    final role = index < highest && value < 100 ? 'forced' : 'leading';
    ids.add('chunk/$role/${value.toString().padLeft(3, '0')}');
    final unit = units[index];
    if (unit.isNotEmpty) {
      ids.addAll(unit.split(' ').map((part) => 'chunk/unit/$part'));
    }
  }
  ids.add('chunk/unit/đồng');
  return List.unmodifiable(ids);
}

class PaymentAmountAudioComposerIo implements PaymentAmountAudioComposer {
  static const _source = 'PaymentAmountAudio';
  static const _assetCount = 1104;
  static const _packDirectoryName = 'local_preset_speaker_v1';
  static const _sampleRateHz = 22050;
  static const _prefixAssetId = 'prefix';
  static const _crossfade = Duration(milliseconds: 50);
  static const _trimThresholdPcm = 33;

  final Directory? _packDirectoryForTesting;
  final Map<String, Future<_PaymentAudioManifest>> _manifestFutures = {};

  PaymentAmountAudioComposerIo({Directory? packDirectoryForTesting})
    : _packDirectoryForTesting = packDirectoryForTesting;

  @override
  Future<PaymentAmountAudioResult> compose({
    required int amount,
    required String assetPackVersion,
    required String voicePresetId,
  }) async {
    final stopwatch = Stopwatch()..start();
    final assetIds = paymentAmountChunkAssetIds(amount);
    await AppLogger.instance.info(
      _source,
      'Offline payment amount composition started',
      context: {
        'amount': amount,
        'assetPackVersion': assetPackVersion,
        'voicePresetId': voicePresetId,
        'assetCount': assetIds.length,
      },
    );
    try {
      if (assetPackVersion != paymentAmountAudioPackVersion) {
        throw StateError(
          'Asset pack version mismatch: event=$assetPackVersion client=$paymentAmountAudioPackVersion',
        );
      }
      if (paymentAudioVoicePresetForId(voicePresetId) == null) {
        throw StateError('Unknown local payment voice preset: $voicePresetId');
      }
      final manifest = await _manifestFutures.putIfAbsent(
        voicePresetId,
        () => _loadManifest(voicePresetId),
      );
      if (manifest.version != assetPackVersion) {
        throw StateError(
          'Installed payment audio manifest version does not match the event',
        );
      }
      final loadedAssets = await Future.wait(
        [
          _prefixAssetId,
          ...assetIds,
        ].map((assetId) => _loadAsset(manifest, assetId)),
      );
      final prefixBytes = loadedAssets.first;
      final combined = PaymentWavTools.combinePcm16SequenceWithCrossfade(
        segments: loadedAssets.skip(1).toList(growable: false),
        crossfade: _crossfade,
        silenceThresholdPcm: _trimThresholdPcm,
      );
      stopwatch.stop();
      await AppLogger.instance.info(
        _source,
        'Offline payment amount composition succeeded',
        context: {
          'amount': amount,
          'assetPackVersion': assetPackVersion,
          'voicePresetId': voicePresetId,
          'assetCount': assetIds.length,
          'bytes': combined.bytes.length,
          'composeDurationMs': stopwatch.elapsedMilliseconds,
          'gapMs': combined.gapMs,
          'crossfadeMs': combined.crossfadeMs,
          'prefixBytes': prefixBytes.length,
          ...combined.combined.toLogContext(prefix: 'composedWav'),
        },
      );
      return PaymentAmountAudioResult(
        bytes: combined.bytes,
        prefixBytes: prefixBytes,
        voicePresetId: voicePresetId,
        assetIds: assetIds,
        composeDurationMs: stopwatch.elapsedMilliseconds,
      );
    } catch (error, stackTrace) {
      stopwatch.stop();
      await AppLogger.instance.error(
        _source,
        'Offline payment amount composition failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          'amount': amount,
          'assetPackVersion': assetPackVersion,
          'voicePresetId': voicePresetId,
          'assetCount': assetIds.length,
          'composeDurationMs': stopwatch.elapsedMilliseconds,
        },
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<_PaymentAudioManifest> _loadManifest(String voicePresetId) async {
    final directory = _packDirectory(voicePresetId);
    final file = File(
      '${directory.path}${Platform.pathSeparator}manifest.json',
    );
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw const FormatException(
        'Payment audio manifest must be a JSON object',
      );
    }
    final json = decoded.map((key, value) => MapEntry(key.toString(), value));
    final preset = paymentAudioVoicePresetForId(voicePresetId);
    final rawVoicePreset = json['voicePreset'];
    if (preset == null ||
        json['schemaVersion'] != 2 ||
        json['assetPackVersion'] != paymentAmountAudioPackVersion ||
        rawVoicePreset is! Map ||
        rawVoicePreset['id'] != preset.id ||
        rawVoicePreset['label'] != preset.label) {
      throw const FormatException('Payment audio manifest identity is invalid');
    }
    final policy = json['audioPolicy'];
    if (policy is! Map ||
        policy['packageSampleRate'] != _sampleRateHz ||
        policy['channels'] != 1 ||
        policy['bitsPerSample'] != 16 ||
        policy['sourceBoundaryTrimThresholdDbfs'] != -60 ||
        policy['internalAmountJoinGapMs'] != 0 ||
        policy['internalAmountCrossfadeMs'] != _crossfade.inMilliseconds ||
        policy['preserveFinalCurrencyTail'] != true ||
        policy['cueToPhraseGapMs'] != 120 ||
        policy['prefixToAmountGapMs'] != 150) {
      throw const FormatException('Payment audio manifest policy is invalid');
    }
    final rawAssets = json['assets'];
    if (rawAssets is! List || rawAssets.length != _assetCount) {
      throw const FormatException(
        'Payment audio manifest inventory is incomplete',
      );
    }
    final assets = <String, _PaymentAudioAsset>{};
    final expectedIds = <String>{
      _prefixAssetId,
      for (var value = 0; value < 1000; value += 1)
        'chunk/leading/${value.toString().padLeft(3, '0')}',
      for (var value = 1; value < 100; value += 1)
        'chunk/forced/${value.toString().padLeft(3, '0')}',
      'chunk/unit/nghìn',
      'chunk/unit/triệu',
      'chunk/unit/tỷ',
      'chunk/unit/đồng',
    };
    for (final rawAsset in rawAssets) {
      if (rawAsset is! Map) {
        throw const FormatException('Payment audio asset entry is invalid');
      }
      final asset = rawAsset.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final id = asset['id']?.toString() ?? '';
      final fileName = asset['file']?.toString() ?? '';
      final digest = asset['sha256']?.toString() ?? '';
      final bytes = asset['bytes'];
      final frames = asset['frames'];
      final durationMs = asset['durationMs'];
      if (id.isEmpty ||
          fileName.isEmpty ||
          fileName.contains('/') ||
          fileName.contains(r'\') ||
          fileName.contains('..') ||
          digest.length != 64 ||
          bytes is! int ||
          bytes <= 44 ||
          frames is! int ||
          frames <= 0 ||
          durationMs is! num ||
          durationMs.toDouble() !=
              ((frames * 1000 / _sampleRateHz) * 1000).round() / 1000 ||
          assets.containsKey(id)) {
        throw FormatException('Payment audio asset metadata is invalid: $id');
      }
      assets[id] = _PaymentAudioAsset(
        fileName: fileName,
        sha256: digest,
        bytes: bytes,
        frames: frames,
      );
    }
    if (assets.length != _assetCount ||
        assets.length != expectedIds.length ||
        !assets.keys.every(expectedIds.contains)) {
      throw const FormatException(
        'Payment audio manifest inventory is invalid',
      );
    }
    return _PaymentAudioManifest(
      version: paymentAmountAudioPackVersion,
      directory: directory,
      assets: assets,
    );
  }

  Future<Uint8List> _loadAsset(
    _PaymentAudioManifest manifest,
    String assetId,
  ) async {
    final asset = manifest.assets[assetId];
    if (asset == null) {
      throw StateError(
        'Payment audio asset is missing from manifest: $assetId',
      );
    }
    final file = File(
      '${manifest.directory.path}${Platform.pathSeparator}${asset.fileName}',
    );
    final bytes = await file.readAsBytes();
    if (bytes.length != asset.bytes) {
      throw StateError('Payment audio asset size mismatch: $assetId');
    }
    if (sha256.convert(bytes).toString() != asset.sha256) {
      throw StateError('Payment audio asset hash mismatch: $assetId');
    }
    final info = PaymentWavTools.readInfo(bytes);
    if (!info.isPcm16 ||
        info.channels != 1 ||
        info.sampleRateHz != _sampleRateHz ||
        info.frameCount != asset.frames) {
      throw StateError('Payment audio asset format mismatch: $assetId');
    }
    return bytes;
  }

  Directory _packDirectory(String voicePresetId) {
    final override = _packDirectoryForTesting;
    if (override != null) {
      final normalised = override.path.replaceAll('\\', '/');
      if (normalised.endsWith('/$voicePresetId')) return override;
      return Directory(
        '${override.path}${Platform.pathSeparator}$voicePresetId',
      );
    }
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'Offline payment audio is supported on Windows only',
      );
    }
    final executableDirectory = File(Platform.resolvedExecutable).parent;
    return Directory(
      '${executableDirectory.path}${Platform.pathSeparator}data'
      '${Platform.pathSeparator}payment_audio'
      '${Platform.pathSeparator}$_packDirectoryName'
      '${Platform.pathSeparator}$voicePresetId',
    );
  }
}

class _PaymentAudioManifest {
  final String version;
  final Directory directory;
  final Map<String, _PaymentAudioAsset> assets;

  const _PaymentAudioManifest({
    required this.version,
    required this.directory,
    required this.assets,
  });
}

class _PaymentAudioAsset {
  final String fileName;
  final String sha256;
  final int bytes;
  final int frames;

  const _PaymentAudioAsset({
    required this.fileName,
    required this.sha256,
    required this.bytes,
    required this.frames,
  });
}
