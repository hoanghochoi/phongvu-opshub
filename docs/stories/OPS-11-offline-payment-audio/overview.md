# OPS-11: Đọc số tiền bằng asset Ngọc Linh trên Windows

## Goal

Loại bỏ TTS và tải audio khỏi đường realtime thông thường để giảm tải server và
đưa latency từ lúc nhận WebSocket đến lúc bắt đầu phát về p95 dưới 2 giây.

## Accepted Behavior

- Windows installer chứa pack bất biến `ngoc-linh-chunk-v4`: 1.103 WAV PCM16
  mono 24 kHz, guard 300 ms đầu và 200 ms cuối.
- Client tách amount thành nhóm ba chữ số, giữ 30 ms mỗi biên và chèn gap 45 ms,
  sau đó phát một WAV đã ghép.
- Local path chỉ bật khi event ghi `currency=VND`, `playbackMode=LOCAL_ASSET` và
  version pack khớp.
- Client compose và kiểm hash các file cần dùng, gọi claim nhẹ rồi phát; không
  gọi endpoint audio hoặc TTS trên đường thành công.
- Mọi lỗi pack/format/hash/version/platform đều có `AppLogger` và fallback về
  server audio hiện tại. `PAYMENT_LOCAL_ASSET_ENABLED=false` là kill switch.
- Queue FIFO, local dedupe, ACK, recovery window và client cũ không đổi.

## Boundaries

- Không nhúng model VieNeu hoặc chạy TTS trong Flutter.
- Không đưa pack vào `pubspec.yaml`; Android, iOS và web không nhận thêm 88 MB.
- Không tắt server audio trước khi staging telemetry và physical-speaker QA đạt.

## Runtime Paths

- `windows/assets/payment_audio/ngoc_linh_chunk_v4/`
- `lib/features/payment_monitor/data/payment_amount_audio_composer*`
- `lib/features/payment_monitor/presentation/providers/payment_monitor_provider.dart`
- `backend-nest/src/payment-notifications/`
- `windows/CMakeLists.txt`
- Windows build/deploy workflows
