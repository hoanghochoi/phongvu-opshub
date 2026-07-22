# OPS-11: Đọc số tiền bằng asset Piper trên Windows

## Goal

Loại bỏ TTS và tải audio khỏi đường realtime thông thường để giảm tải server và
đưa latency từ lúc nhận WebSocket đến lúc bắt đầu phát về p95 dưới 2 giây.

## Accepted Behavior

- Windows installer chứa pack bất biến `piper-vi-vais1000-chunk-v1`: 1.103 WAV PCM16
  mono 24 kHz, guard 300 ms đầu và 200 ms cuối.
- Pack được sinh một lần bằng Piper 1.4.2, model production `vi-vais1000`, tốc
  độ 0.90 và gain headroom cố định -1,5 dB; model không nằm trong client.
- Client tách amount thành nhóm ba chữ số, bỏ guard giữa các chunk và chèn gap 45 ms,
  sau đó phát một WAV đã ghép.
- Local path chỉ bật khi event ghi `currency=VND`, `playbackMode=LOCAL_ASSET` và
  version pack khớp.
- Client compose và kiểm hash các file cần dùng, gọi claim nhẹ rồi phát; không
  gọi endpoint audio hoặc TTS trên đường thành công.
- Mọi lỗi pack/format/hash/version/platform đều có `AppLogger` và fallback về
  server audio hiện tại. `PAYMENT_LOCAL_ASSET_ENABLED=false` là kill switch.
- Queue FIFO, local dedupe, ACK, recovery window và client cũ không đổi.

## Composition Policy

The current client composition policy trims stored guards fully between amount
chunks and inserts a 45 ms join gap. The fixed production cue is joined to the
amount with a 150 ms gap.

## Boundaries

- Không nhúng Piper/model hoặc chạy TTS trong Flutter.
- Không thay `data/payment-cue-prefix.wav`; cue “Phong Vũ đã nhận:” dùng asset
  runtime hiện có.
- Không đưa pack vào `pubspec.yaml`; Android, iOS và web không nhận thêm 88 MB.
- Không tắt server audio trước khi staging telemetry và physical-speaker QA đạt.

## Runtime Paths

- `windows/assets/payment_audio/piper_vi_vais1000_chunk_v1/`
- `lib/features/payment_monitor/data/payment_amount_audio_composer*`
- `lib/features/payment_monitor/presentation/providers/payment_monitor_provider.dart`
- `backend-nest/src/payment-notifications/`
- `windows/CMakeLists.txt`
- Windows build/deploy workflows
