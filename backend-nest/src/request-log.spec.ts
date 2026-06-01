import { requestPathForLog } from './request-log';

describe('requestPathForLog', () => {
  it('drops query strings from originalUrl so tokens are not logged', () => {
    expect(
      requestPathForLog({ originalUrl: '/reset-password?token=secret-token' }),
    ).toBe('/reset-password');
  });

  it('prefers Express path when available', () => {
    expect(
      requestPathForLog({
        path: '/payment-notifications/123/audio',
        originalUrl: '/payment-notifications/123/audio?access_token=secret',
      }),
    ).toBe('/payment-notifications/123/audio');
  });

  it('falls back to slash for missing paths', () => {
    expect(requestPathForLog({})).toBe('/');
  });
});
