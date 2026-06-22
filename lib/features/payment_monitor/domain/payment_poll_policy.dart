bool shouldDeferPaymentPoll({
  required DateTime now,
  required DateTime? nextPollAllowedAt,
  required bool bypassBackoff,
}) {
  return !bypassBackoff &&
      nextPollAllowedAt != null &&
      now.isBefore(nextPollAllowedAt);
}
