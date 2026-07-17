import { ServiceUnavailableException } from '@nestjs/common';
import { SalesReportErpService } from '../sales-reports/sales-report-erp.service';

describe('SalesReportErpService authorizedRequest', () => {
  const originalEnv = process.env;
  const originalFetch = global.fetch;

  beforeEach(() => {
    process.env = {
      ...originalEnv,
      ERP_USERNAME: 'sale@example.com',
      ERP_PASSWORD: 'secret-password',
      ERP_PPM_BASE_URL: 'https://ppm.tekoapis.com/api',
    };
    delete process.env.ERP_ACCESS_TOKEN;
  });

  afterEach(() => {
    process.env = originalEnv;
    global.fetch = originalFetch;
    jest.restoreAllMocks();
  });

  it('shares one in-flight login across concurrent ERP requests', async () => {
    const service = new SalesReportErpService();
    const login = jest
      .spyOn(service as any, 'loginWithPassword')
      .mockImplementation(async () => {
        await Promise.resolve();
        return {
          accessToken: 'shared-token',
          expiresAt: Date.now() + 60_000,
        };
      });
    const fetchMock = jest.fn().mockResolvedValue(jsonResponse({ ok: true }));
    global.fetch = fetchMock;

    await Promise.all([
      service.authorizedRequest('https://ppm.tekoapis.com/api/products'),
      service.authorizedRequest('https://ppm.tekoapis.com/api/products'),
    ]);

    expect(login).toHaveBeenCalledTimes(1);
    expect(fetchMock).toHaveBeenCalledTimes(2);
    for (const [, init] of fetchMock.mock.calls as [string, RequestInit][]) {
      expect(new Headers(init.headers).get('Authorization')).toBe(
        'Bearer shared-token',
      );
    }
  });

  it('invalidates the shared cached token and retries a 401 only once', async () => {
    const service = new SalesReportErpService();
    const login = jest
      .spyOn(service as any, 'loginWithPassword')
      .mockResolvedValueOnce({
        accessToken: 'expired-token',
        expiresAt: Date.now() + 60_000,
      })
      .mockResolvedValueOnce({
        accessToken: 'fresh-token',
        expiresAt: Date.now() + 60_000,
      });
    const seenTokens: string[] = [];
    global.fetch = jest.fn(async (_url, init) => {
      const token = new Headers(init?.headers).get('Authorization') ?? '';
      seenTokens.push(token);
      return token === 'Bearer expired-token'
        ? jsonResponse({}, 401)
        : jsonResponse({ ok: true });
    });

    const response = await service.authorizedRequest(
      'https://ppm.tekoapis.com/api/products',
    );

    expect(response.ok).toBe(true);
    expect(login).toHaveBeenCalledTimes(2);
    expect(seenTokens).toEqual(['Bearer expired-token', 'Bearer fresh-token']);
  });

  it('does not retry more than once when the refreshed token is rejected', async () => {
    const service = new SalesReportErpService();
    jest.spyOn(service as any, 'loginWithPassword').mockResolvedValue({
      accessToken: 'rejected-token',
      expiresAt: Date.now() + 60_000,
    });
    const fetchMock = jest.fn().mockResolvedValue(jsonResponse({}, 401));
    global.fetch = fetchMock;

    const response = await service.authorizedRequest(
      'https://ppm.tekoapis.com/api/products',
    );

    expect(response.status).toBe(401);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('blocks an unexpected origin before sending a token', async () => {
    const service = new SalesReportErpService();
    const login = jest.spyOn(service as any, 'loginWithPassword');
    const fetchMock = jest.fn();
    global.fetch = fetchMock;

    await expect(
      service.authorizedRequest('https://example.invalid/collect'),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
    expect(login).not.toHaveBeenCalled();
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
