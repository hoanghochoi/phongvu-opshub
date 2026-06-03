import 'dart:math' as math;
import 'dart:typed_data';

class PaymentWavException implements Exception {
  final String message;

  const PaymentWavException(this.message);

  @override
  String toString() => message;
}

class PaymentWavInfo {
  final int audioFormat;
  final int channels;
  final int sampleRateHz;
  final int byteRate;
  final int blockAlign;
  final int bitsPerSample;
  final int dataOffset;
  final int dataBytes;

  const PaymentWavInfo({
    required this.audioFormat,
    required this.channels,
    required this.sampleRateHz,
    required this.byteRate,
    required this.blockAlign,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.dataBytes,
  });

  bool get isPcm16 => audioFormat == 1 && bitsPerSample == 16;

  int get frameCount => blockAlign <= 0 ? 0 : dataBytes ~/ blockAlign;

  Map<String, Object?> toLogContext({String prefix = 'wav'}) {
    return {
      '${prefix}AudioFormat': audioFormat,
      '${prefix}Channels': channels,
      '${prefix}SampleRateHz': sampleRateHz,
      '${prefix}ByteRate': byteRate,
      '${prefix}BlockAlign': blockAlign,
      '${prefix}BitsPerSample': bitsPerSample,
      '${prefix}DataBytes': dataBytes,
      '${prefix}FrameCount': frameCount,
    };
  }
}

class PaymentWavNormalizeResult {
  final Uint8List bytes;
  final PaymentWavInfo source;
  final PaymentWavInfo target;

  const PaymentWavNormalizeResult({
    required this.bytes,
    required this.source,
    required this.target,
  });
}

class PaymentWavTools {
  static const int targetSampleRateHz = 44100;

  const PaymentWavTools._();

  static PaymentWavInfo readInfo(List<int> bytes) {
    final data = _asUint8List(bytes);
    if (data.length < 12 ||
        !_matchesAscii(data, 0, 'RIFF') ||
        !_matchesAscii(data, 8, 'WAVE')) {
      throw const PaymentWavException('Audio is not a RIFF/WAVE file');
    }

    _Chunk? fmtChunk;
    _Chunk? dataChunk;
    var offset = 12;
    while (offset + 8 <= data.length) {
      final id = _asciiAt(data, offset);
      final size = _uint32(data, offset + 4);
      final chunkDataOffset = offset + 8;
      final nextOffset = chunkDataOffset + size + (size.isOdd ? 1 : 0);
      if (size < 0 || chunkDataOffset + size > data.length) {
        throw const PaymentWavException('WAV chunk length is invalid');
      }
      if (id == 'fmt ') {
        fmtChunk = _Chunk(chunkDataOffset, size);
      } else if (id == 'data') {
        dataChunk = _Chunk(chunkDataOffset, size);
      }
      offset = nextOffset;
    }

    if (fmtChunk == null || fmtChunk.size < 16) {
      throw const PaymentWavException('WAV fmt chunk is missing or invalid');
    }
    if (dataChunk == null) {
      throw const PaymentWavException('WAV data chunk is missing');
    }

    final fmtOffset = fmtChunk.offset;
    final audioFormat = _uint16(data, fmtOffset);
    final channels = _uint16(data, fmtOffset + 2);
    final sampleRateHz = _uint32(data, fmtOffset + 4);
    final byteRate = _uint32(data, fmtOffset + 8);
    final blockAlign = _uint16(data, fmtOffset + 12);
    final bitsPerSample = _uint16(data, fmtOffset + 14);

    return PaymentWavInfo(
      audioFormat: audioFormat,
      channels: channels,
      sampleRateHz: sampleRateHz,
      byteRate: byteRate,
      blockAlign: blockAlign,
      bitsPerSample: bitsPerSample,
      dataOffset: dataChunk.offset,
      dataBytes: dataChunk.size,
    );
  }

  static PaymentWavInfo? tryReadInfo(List<int> bytes) {
    try {
      return readInfo(bytes);
    } on PaymentWavException {
      return null;
    }
  }

  static PaymentWavNormalizeResult normalizeToPcm16Mono44100(List<int> bytes) {
    final data = _asUint8List(bytes);
    final source = readInfo(data);
    if (!source.isPcm16) {
      throw PaymentWavException(
        'Only PCM 16-bit WAV can be normalized; format=${source.audioFormat} bits=${source.bitsPerSample}',
      );
    }
    if (source.channels <= 0 || source.sampleRateHz <= 0) {
      throw const PaymentWavException(
        'WAV channel count or sample rate is invalid',
      );
    }
    final expectedBlockAlign = source.channels * 2;
    if (source.blockAlign != expectedBlockAlign) {
      throw PaymentWavException(
        'WAV blockAlign is invalid; expected=$expectedBlockAlign actual=${source.blockAlign}',
      );
    }
    if (source.dataBytes <= 0 || source.dataBytes % source.blockAlign != 0) {
      throw const PaymentWavException('WAV data length is not frame aligned');
    }

    final monoSamples = _readMonoSamples(data, source);
    final resampled = _resampleLinear(
      monoSamples,
      source.sampleRateHz,
      targetSampleRateHz,
    );
    final normalizedBytes = _writePcm16MonoWav(resampled, targetSampleRateHz);
    final target = readInfo(normalizedBytes);
    return PaymentWavNormalizeResult(
      bytes: normalizedBytes,
      source: source,
      target: target,
    );
  }

  static List<int> _readMonoSamples(Uint8List bytes, PaymentWavInfo info) {
    final samples = <int>[];
    for (var frame = 0; frame < info.frameCount; frame += 1) {
      final frameOffset = info.dataOffset + frame * info.blockAlign;
      var sum = 0;
      for (var channel = 0; channel < info.channels; channel += 1) {
        sum += _int16(bytes, frameOffset + channel * 2);
      }
      samples.add(_clampInt16((sum / info.channels).round()));
    }
    return samples;
  }

  static List<int> _resampleLinear(
    List<int> samples,
    int sourceSampleRate,
    int targetSampleRate,
  ) {
    if (samples.isEmpty || sourceSampleRate == targetSampleRate) {
      return List<int>.from(samples);
    }
    final targetFrames = math.max(
      1,
      (samples.length * targetSampleRate / sourceSampleRate).round(),
    );
    final ratio = sourceSampleRate / targetSampleRate;
    final result = List<int>.filled(targetFrames, 0);
    for (var i = 0; i < targetFrames; i += 1) {
      final sourcePosition = i * ratio;
      final left = sourcePosition.floor().clamp(0, samples.length - 1).toInt();
      final right = (left + 1).clamp(0, samples.length - 1).toInt();
      final fraction = sourcePosition - left;
      final value = samples[left] + (samples[right] - samples[left]) * fraction;
      result[i] = _clampInt16(value.round());
    }
    return result;
  }

  static Uint8List _writePcm16MonoWav(List<int> samples, int sampleRateHz) {
    final dataBytes = samples.length * 2;
    final bytes = Uint8List(44 + dataBytes);
    _writeAscii(bytes, 0, 'RIFF');
    _writeUint32(bytes, 4, 36 + dataBytes);
    _writeAscii(bytes, 8, 'WAVE');
    _writeAscii(bytes, 12, 'fmt ');
    _writeUint32(bytes, 16, 16);
    _writeUint16(bytes, 20, 1);
    _writeUint16(bytes, 22, 1);
    _writeUint32(bytes, 24, sampleRateHz);
    _writeUint32(bytes, 28, sampleRateHz * 2);
    _writeUint16(bytes, 32, 2);
    _writeUint16(bytes, 34, 16);
    _writeAscii(bytes, 36, 'data');
    _writeUint32(bytes, 40, dataBytes);
    var offset = 44;
    for (final sample in samples) {
      _writeInt16(bytes, offset, _clampInt16(sample));
      offset += 2;
    }
    return bytes;
  }

  static Uint8List _asUint8List(List<int> bytes) {
    return bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  }

  static bool _matchesAscii(Uint8List bytes, int offset, String text) {
    if (offset + text.length > bytes.length) return false;
    for (var i = 0; i < text.length; i += 1) {
      if (bytes[offset + i] != text.codeUnitAt(i)) return false;
    }
    return true;
  }

  static String _asciiAt(Uint8List bytes, int offset) {
    return String.fromCharCodes(bytes.sublist(offset, offset + 4));
  }

  static int _uint16(Uint8List bytes, int offset) {
    return ByteData.sublistView(bytes).getUint16(offset, Endian.little);
  }

  static int _uint32(Uint8List bytes, int offset) {
    return ByteData.sublistView(bytes).getUint32(offset, Endian.little);
  }

  static int _int16(Uint8List bytes, int offset) {
    return ByteData.sublistView(bytes).getInt16(offset, Endian.little);
  }

  static void _writeAscii(Uint8List bytes, int offset, String text) {
    for (var i = 0; i < text.length; i += 1) {
      bytes[offset + i] = text.codeUnitAt(i);
    }
  }

  static void _writeUint16(Uint8List bytes, int offset, int value) {
    ByteData.sublistView(bytes).setUint16(offset, value, Endian.little);
  }

  static void _writeUint32(Uint8List bytes, int offset, int value) {
    ByteData.sublistView(bytes).setUint32(offset, value, Endian.little);
  }

  static void _writeInt16(Uint8List bytes, int offset, int value) {
    ByteData.sublistView(bytes).setInt16(offset, value, Endian.little);
  }

  static int _clampInt16(num value) {
    return value.round().clamp(-32768, 32767).toInt();
  }
}

class _Chunk {
  final int offset;
  final int size;

  const _Chunk(this.offset, this.size);
}
