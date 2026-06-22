import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/features/payment_monitor/domain/payment_poll_policy.dart';

void main() {
  test('realtime and fallback polls respect active backoff', () {
    final now = DateTime(2026, 6, 22, 10);

    expect(
      shouldDeferPaymentPoll(
        now: now,
        nextPollAllowedAt: now.add(const Duration(seconds: 30)),
        bypassBackoff: false,
      ),
      isTrue,
    );
  });

  test('explicit user action may bypass active backoff', () {
    final now = DateTime(2026, 6, 22, 10);

    expect(
      shouldDeferPaymentPoll(
        now: now,
        nextPollAllowedAt: now.add(const Duration(seconds: 30)),
        bypassBackoff: true,
      ),
      isFalse,
    );
  });
}
