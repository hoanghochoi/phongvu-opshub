import 'dart:typed_data';

const paymentAmountAudioPackVersion = 'local-preset-speaker-v1';
const defaultPaymentAudioVoicePresetId = 'mien-bac-thanh-ha';

class PaymentAudioVoicePreset {
  final String id;
  final String label;
  final String subtitle;

  const PaymentAudioVoicePreset({
    required this.id,
    required this.label,
    required this.subtitle,
  });
}

const paymentAudioVoicePresets = <PaymentAudioVoicePreset>[
  PaymentAudioVoicePreset(
    id: 'mien-bac-thanh-ha',
    label: 'Miền Bắc — Thanh Hà',
    subtitle: 'Giọng mặc định cho máy loa mới',
  ),
  PaymentAudioVoicePreset(
    id: 'mien-trung-mai-ngoc',
    label: 'Miền Trung — Mai Ngọc',
    subtitle: 'Giọng miền Trung',
  ),
  PaymentAudioVoicePreset(
    id: 'mien-nam-phuong-ly',
    label: 'Miền Nam — Phương Ly',
    subtitle: 'Giọng miền Nam',
  ),
];

PaymentAudioVoicePreset? paymentAudioVoicePresetForId(String id) {
  for (final preset in paymentAudioVoicePresets) {
    if (preset.id == id) return preset;
  }
  return null;
}

class PaymentAmountAudioResult {
  final Uint8List bytes;
  final Uint8List prefixBytes;
  final String voicePresetId;
  final List<String> assetIds;
  final int composeDurationMs;

  const PaymentAmountAudioResult({
    required this.bytes,
    required this.prefixBytes,
    required this.voicePresetId,
    required this.assetIds,
    required this.composeDurationMs,
  });
}

abstract class PaymentAmountAudioComposer {
  Future<PaymentAmountAudioResult> compose({
    required int amount,
    required String assetPackVersion,
    required String voicePresetId,
  });
}
