import { logFingerprint, safeLogError } from './log-sanitizer';

describe('log sanitizer', () => {
  it('creates a stable short identifier without exposing the source', () => {
    expect(logFingerprint(' Staff@PhongVu.vn ')).toBe(
      logFingerprint('staff@phongvu.vn'),
    );
    expect(logFingerprint('staff@phongvu.vn')).not.toContain('staff');
  });

  it('redacts credentials, email and line breaks from errors', () => {
    expect(
      safeLogError(
        'failed staff@phongvu.vn password=secret\npostgresql://user:pass@db/app',
      ),
    ).toBe('failed [redacted-email] [redacted] postgresql://[redacted]@db/app');
  });
});
