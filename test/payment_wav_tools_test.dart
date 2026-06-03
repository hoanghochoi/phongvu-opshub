import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/payment_wav_tools.dart';

void main() {
  test('reads PCM 16-bit mono 22050 Hz WAV metadata', () {
    final wav = _pcm16Wav(
      sampleRateHz: 22050,
      channels: 1,
      frames: const [
        [0],
        [1000],
        [-1000],
        [2000],
      ],
    );

    final info = PaymentWavTools.readInfo(wav);

    expect(info.audioFormat, 1);
    expect(info.channels, 1);
    expect(info.sampleRateHz, 22050);
    expect(info.bitsPerSample, 16);
    expect(info.blockAlign, 2);
    expect(info.dataBytes, 8);
    expect(info.frameCount, 4);
  });

  test('normalizes PCM 16-bit mono 22050 Hz WAV to 44100 Hz mono', () {
    final wav = _pcm16Wav(
      sampleRateHz: 22050,
      channels: 1,
      frames: const [
        [0],
        [1000],
        [-1000],
        [2000],
      ],
    );

    final result = PaymentWavTools.normalizeToPcm16Mono44100(wav);
    final info = PaymentWavTools.readInfo(result.bytes);

    expect(result.source.sampleRateHz, 22050);
    expect(info.audioFormat, 1);
    expect(info.channels, 1);
    expect(info.sampleRateHz, 44100);
    expect(info.bitsPerSample, 16);
    expect(info.blockAlign, 2);
    expect(info.dataBytes, 16);
    expect(info.frameCount, 8);
  });

  test(
    'downmixes stereo PCM 16-bit WAV to mono without changing sample rate',
    () {
      final wav = _pcm16Wav(
        sampleRateHz: 44100,
        channels: 2,
        frames: const [
          [1000, -1000],
          [2000, 0],
        ],
      );

      final result = PaymentWavTools.normalizeToPcm16Mono44100(wav);
      final info = PaymentWavTools.readInfo(result.bytes);

      expect(info.channels, 1);
      expect(info.sampleRateHz, 44100);
      expect(info.frameCount, 2);
      expect(_int16(result.bytes, 44), 0);
      expect(_int16(result.bytes, 46), 1000);
    },
  );

  test('rejects unsupported WAV formats without crashing', () {
    final wav = _wavHeader(
      audioFormat: 3,
      sampleRateHz: 22050,
      channels: 1,
      bitsPerSample: 32,
      dataBytes: 4,
    );

    expect(
      () => PaymentWavTools.normalizeToPcm16Mono44100(wav),
      throwsA(isA<PaymentWavException>()),
    );
  });
}

Uint8List _pcm16Wav({
  required int sampleRateHz,
  required int channels,
  required List<List<int>> frames,
}) {
  final blockAlign = channels * 2;
  final dataBytes = frames.length * blockAlign;
  final bytes = _wavHeader(
    audioFormat: 1,
    sampleRateHz: sampleRateHz,
    channels: channels,
    bitsPerSample: 16,
    dataBytes: dataBytes,
  );
  var offset = 44;
  for (final frame in frames) {
    if (frame.length != channels) {
      throw ArgumentError('Frame does not match channel count');
    }
    for (final sample in frame) {
      _writeInt16(bytes, offset, sample);
      offset += 2;
    }
  }
  return bytes;
}

Uint8List _wavHeader({
  required int audioFormat,
  required int sampleRateHz,
  required int channels,
  required int bitsPerSample,
  required int dataBytes,
}) {
  final bytes = Uint8List(44 + dataBytes);
  final blockAlign = channels * (bitsPerSample ~/ 8);
  _writeAscii(bytes, 0, 'RIFF');
  _writeUint32(bytes, 4, 36 + dataBytes);
  _writeAscii(bytes, 8, 'WAVE');
  _writeAscii(bytes, 12, 'fmt ');
  _writeUint32(bytes, 16, 16);
  _writeUint16(bytes, 20, audioFormat);
  _writeUint16(bytes, 22, channels);
  _writeUint32(bytes, 24, sampleRateHz);
  _writeUint32(bytes, 28, sampleRateHz * blockAlign);
  _writeUint16(bytes, 32, blockAlign);
  _writeUint16(bytes, 34, bitsPerSample);
  _writeAscii(bytes, 36, 'data');
  _writeUint32(bytes, 40, dataBytes);
  return bytes;
}

int _int16(Uint8List bytes, int offset) {
  return ByteData.sublistView(bytes).getInt16(offset, Endian.little);
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

void _writeInt16(Uint8List bytes, int offset, int value) {
  ByteData.sublistView(bytes).setInt16(offset, value, Endian.little);
}
