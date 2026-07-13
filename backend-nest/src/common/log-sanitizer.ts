import { createHash } from 'crypto';

export function logFingerprint(value: unknown) {
  const normalized = String(value ?? '')
    .trim()
    .toLowerCase();
  if (!normalized) return 'none';
  return createHash('sha256').update(normalized).digest('hex').slice(0, 12);
}

export function safeLogError(error: unknown, maxLength = 240) {
  return String(error instanceof Error ? error.message : error)
    .replace(/(Bearer\s+)[A-Za-z0-9._-]+/gi, '$1[redacted]')
    .replace(
      /"?(?:password|token|secret|authorization)"?\s*[:=]\s*("[^"]*"|'[^']*'|[^\s,}]+)/gi,
      '[redacted]',
    )
    .replace(
      /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g,
      '[redacted-email]',
    )
    .replace(/([a-z][a-z0-9+.-]*:\/\/)[^\s/@]+@/gi, '$1[redacted]@')
    .replace(/[\r\n]+/g, ' ')
    .slice(0, maxLength);
}
