import { BadGatewayException } from '@nestjs/common';
import {
  BankProviderHttpException,
  MapVietinProviderRuntime,
} from './map-vietin-provider.runtime';

describe('MapVietinProviderRuntime', () => {
  const originalEnv = process.env;

  afterEach(() => {
    process.env = originalEnv;
    jest.restoreAllMocks();
  });

  it('caches MAP sessions by username until expiry or forced refresh', async () => {
    const runtime = new MapVietinProviderRuntime();
    const login = jest
      .fn()
      .mockResolvedValueOnce({
        accessToken: 'token-1',
        merchantId: 'merchant-1',
      })
      .mockResolvedValueOnce({
        accessToken: 'token-2',
        merchantId: 'merchant-1',
      });
    jest.spyOn(Date, 'now').mockReturnValueOnce(1_000).mockReturnValue(2_000);

    await expect(
      runtime.getGlobalSession('global-user', 60, false, login),
    ).resolves.toEqual({ accessToken: 'token-1', merchantId: 'merchant-1' });
    await expect(
      runtime.getGlobalSession('global-user', 60, false, login),
    ).resolves.toEqual({ accessToken: 'token-1', merchantId: 'merchant-1' });
    await expect(
      runtime.getGlobalSession('global-user', 60, true, login),
    ).resolves.toEqual({ accessToken: 'token-2', merchantId: 'merchant-1' });
    expect(login).toHaveBeenCalledTimes(2);
  });

  it('invalidates eFAST cache when the configured CIF changes', async () => {
    const runtime = new MapVietinProviderRuntime();
    const login = jest
      .fn()
      .mockResolvedValueOnce({
        username: 'efast-user',
        cifno: 'CIF-1',
        sessionId: 'session-1',
      })
      .mockResolvedValueOnce({
        username: 'efast-user',
        cifno: 'CIF-2',
        sessionId: 'session-2',
      });

    await expect(
      runtime.getEfastSession('efast-user', 'CIF-1', 60, false, login),
    ).resolves.toMatchObject({ sessionId: 'session-1' });
    await expect(
      runtime.getEfastSession('efast-user', 'CIF-2', 60, false, login),
    ).resolves.toMatchObject({ sessionId: 'session-2' });
    expect(login).toHaveBeenCalledTimes(2);
  });

  it('preserves bounded JSON transport and provider Retry-After errors', async () => {
    const runtime = new MapVietinProviderRuntime();
    const fetchSpy = jest.spyOn(global, 'fetch').mockResolvedValue({
      status: 429,
      ok: false,
      headers: new Headers({ 'retry-after': '90' }),
      text: async () =>
        JSON.stringify({ status: { message: 'Too Many Requests' } }),
    } as Response);

    await expect(
      runtime.postJson('https://example.test/map', { query: 'value' }, {}),
    ).rejects.toMatchObject<Partial<BankProviderHttpException>>({
      providerStatus: 429,
      retryAfterMs: 90_000,
      message: expect.stringContaining('Too Many Requests'),
    });
    expect(fetchSpy).toHaveBeenCalledWith(
      'https://example.test/map',
      expect.objectContaining({ method: 'POST' }),
    );
  });

  it('keeps exponential MAP backoff capped and honors Retry-After', () => {
    const runtime = new MapVietinProviderRuntime();
    jest.spyOn(Math, 'random').mockReturnValue(0);
    jest.spyOn(Date, 'now').mockReturnValue(10_000);

    runtime.registerMapProviderBackoff(429);
    expect(runtime.mapProviderBackoffUntil).toBe(40_000);
    runtime.registerMapProviderBackoff(429, 90_000);
    expect(runtime.mapProviderBackoffUntil).toBe(100_000);
    runtime.registerMapProviderBackoff(429);
    expect(runtime.mapProviderBackoffUntil).toBe(130_000);
    expect(runtime.mapProviderBackoffAttempt).toBe(3);

    runtime.clearMapProviderBackoff();
    expect(runtime.mapProviderBackoffUntil).toBe(0);
    expect(runtime.mapProviderBackoffAttempt).toBe(0);
  });

  it('maps malformed provider JSON to a bad-gateway error', async () => {
    const runtime = new MapVietinProviderRuntime();
    jest.spyOn(global, 'fetch').mockResolvedValue({
      status: 200,
      ok: true,
      headers: new Headers(),
      text: async () => '{not-json',
    } as Response);

    await expect(
      runtime.postJson('https://example.test/map', {}, {}),
    ).rejects.toBeInstanceOf(BadGatewayException);
  });
});
