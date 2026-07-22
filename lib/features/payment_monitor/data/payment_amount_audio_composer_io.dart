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
  static const _assetCount = 1103;
  static const _packDirectoryName = 'ngoc_linh_chunk_v4';
  static const _storedLeadingSilence = Duration(milliseconds: 300);
  static const _storedTrailingSilence = Duration(milliseconds: 200);
  static const _retainedBoundarySilence = Duration(milliseconds: 30);
  static const _joinGap = Duration(milliseconds: 45);

  final Directory? _packDirectoryForTesting;
  Future<_PaymentAudioManifest>? _manifestFuture;

  PaymentAmountAudioComposerIo({Directory? packDirectoryForTesting})
    : _packDirectoryForTesting = packDirectoryForTesting;

  @override
  Future<PaymentAmountAudioResult> compose({
    required int amount,
    required String assetPackVersion,
  }) async {
    final stopwatch = Stopwatch()..start();
    final assetIds = paymentAmountChunkAssetIds(amount);
    await AppLogger.instance.info(
      _source,
      'Offline payment amount composition started',
      context: {
        'amount': amount,
        'assetPackVersion': assetPackVersion,
        'assetCount': assetIds.length,
      },
    );
    try {
      if (assetPackVersion != paymentAmountAudioPackVersion) {
        throw StateError(
          'Asset pack version mismatch: event=$assetPackVersion client=$paymentAmountAudioPackVersion',
        );
      }
      final manifest = await (_manifestFuture ??= _loadManifest());
      if (manifest.version != assetPackVersion) {
        throw StateError(
          'Installed payment audio manifest version does not match the event',
        );
      }
      final segments = await Future.wait(
        assetIds.map((assetId) => _loadAsset(manifest, assetId)),
      );
      final combined = PaymentWavTools.combinePcm16SequenceWithKnownGuards(
        segments: segments,
        storedLeadingSilence: _storedLeadingSilence,
        storedTrailingSilence: _storedTrailingSilence,
        retainedBoundarySilence: _retainedBoundarySilence,
        gap: _joinGap,
      );
      stopwatch.stop();
      await AppLogger.instance.info(
        _source,
        'Offline payment amount composition succeeded',
        context: {
          'amount': amount,
          'assetPackVersion': assetPackVersion,
          'assetCount': assetIds.length,
          'bytes': combined.bytes.length,
          'composeDurationMs': stopwatch.elapsedMilliseconds,
          'gapMs': combined.gapMs,
          ...combined.combined.toLogContext(prefix: 'composedWav'),
        },
      );
      return PaymentAmountAudioResult(
        bytes: combined.bytes,
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
          'assetCount': assetIds.length,
          'composeDurationMs': stopwatch.elapsedMilliseconds,
        },
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<_PaymentAudioManifest> _loadManifest() async {
    final directory = _packDirectory;
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
    if (json['schemaVersion'] != 1 ||
        json['assetPackVersion'] != paymentAmountAudioPackVersion ||
        json['voice'] != 'Ngọc Linh') {
      throw const FormatException('Payment audio manifest identity is invalid');
    }
    final policy = json['audioPolicy'];
    if (policy is! Map ||
        policy['packageSampleRate'] != 24000 ||
        policy['channels'] != 1 ||
        policy['bitsPerSample'] != 16 ||
        policy['assetLeadingSilenceMs'] != 300 ||
        policy['assetTrailingSilenceMs'] != 200 ||
        policy['composeBoundarySilenceMs'] != 30 ||
        policy['joinGapMs'] != 45) {
      throw const FormatException('Payment audio manifest policy is invalid');
    }
    final rawAssets = json['assets'];
    if (rawAssets is! List || rawAssets.length != _assetCount) {
      throw const FormatException(
        'Payment audio manifest inventory is incomplete',
      );
    }
    final assets = <String, _PaymentAudioAsset>{};
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
      if (id.isEmpty ||
          fileName.isEmpty ||
          fileName.contains('/') ||
          fileName.contains(r'\') ||
          fileName.contains('..') ||
          digest.length != 64 ||
          bytes is! int ||
          bytes <= 44 ||
          assets.containsKey(id)) {
        throw FormatException('Payment audio asset metadata is invalid: $id');
      }
      assets[id] = _PaymentAudioAsset(
        fileName: fileName,
        sha256: digest,
        bytes: bytes,
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
    return bytes;
  }

  Directory get _packDirectory {
    final override = _packDirectoryForTesting;
    if (override != null) return override;
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'Offline payment audio is supported on Windows only',
      );
    }
    final executableDirectory = File(Platform.resolvedExecutable).parent;
    return Directory(
      '${executableDirectory.path}${Platform.pathSeparator}data'
      '${Platform.pathSeparator}payment_audio'
      '${Platform.pathSeparator}$_packDirectoryName',
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

  const _PaymentAudioAsset({
    required this.fileName,
    required this.sha256,
    required this.bytes,
  });
}
