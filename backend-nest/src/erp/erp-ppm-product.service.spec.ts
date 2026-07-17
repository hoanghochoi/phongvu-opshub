import { ServiceUnavailableException } from '@nestjs/common';
import { SalesReportErpService } from '../sales-reports/sales-report-erp.service';
import { ErpPpmProductService } from './erp-ppm-product.service';

describe('ErpPpmProductService', () => {
  const originalEnv = process.env;
  let authorizedRequest: jest.Mock;
  let service: ErpPpmProductService;

  beforeEach(() => {
    process.env = {
      ...originalEnv,
      ERP_PPM_BASE_URL: 'https://ppm.tekoapis.com/api',
      ERP_PPM_SELLER_ID: '1',
      ERP_PPM_TERMINAL_CODE: '49180_PRICE_0001',
      ERP_PPM_CACHE_TTL_MS: '300000',
    };
    authorizedRequest = jest.fn();
    service = new ErpPpmProductService({
      authorizedRequest,
    } as unknown as SalesReportErpService);
  });

  afterEach(() => {
    process.env = originalEnv;
    jest.restoreAllMocks();
  });

  it('deduplicates and batches more than 50 SKUs without losing tax data', async () => {
    const skus = [
      '250902982',
      ...Array.from({ length: 51 }, (_, index) => `SKU-${index + 1}`),
      '250902982',
    ];
    authorizedRequest.mockImplementation(async (_url, init: RequestInit) => {
      const request = JSON.parse(String(init.body)) as { skus: string[] };
      return jsonResponse({
        result: {
          results: request.skus.map((sku) => ({
            sku,
            taxOutAmount: sku === '250902982' ? 8 : 10,
            taxOutCode: sku === '250902982' ? 'VAT8' : 'VAT10',
            taxOutLabel: sku === '250902982' ? 'Thuế 8%' : 'Thuế 10%',
          })),
          totalItems: request.skus.length,
        },
      });
    });

    const result = await service.lookupTaxes(skus);

    expect(authorizedRequest).toHaveBeenCalledTimes(2);
    expect(
      authorizedRequest.mock.calls.map(
        ([, init]) =>
          (JSON.parse(String(init.body)) as { skus: string[] }).skus.length,
      ),
    ).toEqual([50, 2]);
    expect(result.requestedSkus).toHaveLength(52);
    expect(result.items).toHaveLength(52);
    expect(result.missingSkus).toEqual([]);
    expect(result.items[0]).toMatchObject({
      sku: '250902982',
      taxOutAmount: 8,
      vatRateBps: 800,
      taxCode: 'VAT8',
      taxLabel: 'Thuế 8%',
      source: 'ERP_PPM',
    });
    const [, init] = authorizedRequest.mock.calls[0] as [string, RequestInit];
    expect(new Headers(init.headers).get('X-Seller-Id')).toBe('1');
    expect(JSON.parse(String(init.body))).toMatchObject({
      terminalCode: '49180_PRICE_0001',
      _page: 1,
      _limit: 50,
      _sort: 'sku',
      _order: 'ascend',
      getExtraData: ['price', 'tax_out'],
    });
  });

  it('keeps zero-percent and non-taxable tax codes distinct', async () => {
    authorizedRequest.mockResolvedValue(
      jsonResponse({
        result: {
          results: [
            {
              sku: 'ZERO',
              taxOutAmount: 0,
              taxOutCode: 'VAT0',
              taxOutLabel: 'Thuế suất 0%',
            },
            {
              sku: 'KCT',
              taxOutCode: 'KCT',
              taxOutLabel: 'Không chịu thuế',
            },
          ],
          totalItems: 2,
        },
      }),
    );

    const result = await service.lookupTaxes(['ZERO', 'KCT', 'NOT-FOUND']);

    expect(result.items[0]).toMatchObject({
      sku: 'ZERO',
      taxOutAmount: 0,
      vatRateBps: 0,
      taxCode: 'VAT0',
      source: 'ERP_PPM',
    });
    expect(result.items[1]).toMatchObject({
      sku: 'KCT',
      vatRateBps: 0,
      taxOutAmount: 0,
      taxCode: 'KCT',
      taxLabel: 'Không chịu thuế',
      source: 'ERP_PPM',
    });
    expect(result.missingSkus).toEqual(['NOT-FOUND']);
  });

  it('uses the five-minute cache and bypasses it for final refresh', async () => {
    authorizedRequest
      .mockResolvedValueOnce(
        jsonResponse({
          result: {
            results: [{ sku: '250902982', taxOutAmount: 8 }],
            totalItems: 1,
          },
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse({
          result: {
            results: [{ sku: '250902982', taxOutAmount: 10 }],
            totalItems: 1,
          },
        }),
      );

    const first = await service.lookupTaxes(['250902982']);
    const cached = await service.lookupTaxes(['250902982']);
    const refreshed = await service.lookupTaxes(['250902982'], {
      forceRefresh: true,
    });

    expect(first.items[0].vatRateBps).toBe(800);
    expect(cached.items[0].vatRateBps).toBe(800);
    expect(refreshed.items[0].vatRateBps).toBe(1000);
    expect(authorizedRequest).toHaveBeenCalledTimes(2);
  });

  it('shares preview tax through Redis without putting a raw SKU in the key', async () => {
    const values = new Map<string, unknown>();
    const redis = {
      getJson: jest.fn(async (key: string) => values.get(key) ?? null),
      setJsonWithTtl: jest.fn(
        async (key: string, value: unknown, _ttlSeconds: number) => {
          values.set(key, value);
        },
      ),
    };
    authorizedRequest.mockResolvedValue(
      jsonResponse({
        result: {
          results: [{ sku: '250902982', taxOutAmount: 8 }],
          totalItems: 1,
        },
      }),
    );
    const writer = new ErpPpmProductService(
      { authorizedRequest } as unknown as SalesReportErpService,
      redis as any,
    );

    await writer.lookupTaxes(['250902982']);

    const cacheKey = redis.setJsonWithTtl.mock.calls[0][0];
    expect(cacheKey).toMatch(/^contract-appendix:ppm-tax:v1:[a-f0-9]{64}$/);
    expect(cacheKey).not.toContain('250902982');
    const readerRequest = jest.fn();
    const reader = new ErpPpmProductService(
      { authorizedRequest: readerRequest } as unknown as SalesReportErpService,
      redis as any,
    );
    const result = await reader.lookupTaxes(['250902982']);
    expect(result.items[0]).toMatchObject({
      sku: '250902982',
      vatRateBps: 800,
      source: 'ERP_PPM',
    });
    expect(readerRequest).not.toHaveBeenCalled();
  });

  it('rejects a paginated response that would silently truncate tax rows', async () => {
    authorizedRequest.mockResolvedValue(
      jsonResponse({
        result: {
          results: [{ sku: 'SKU-1', taxOutAmount: 8 }],
          totalItems: 2,
        },
      }),
    );

    await expect(
      service.lookupTaxes(['SKU-1', 'SKU-2']),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
  });

  it('never treats an invalid tax amount as a usable VAT rate', async () => {
    authorizedRequest.mockResolvedValue(
      jsonResponse({
        result: {
          results: [{ sku: 'SKU-1', taxOutAmount: 101 }],
          totalItems: 1,
        },
      }),
    );

    const result = await service.lookupTaxes(['SKU-1']);

    expect(result.items[0]).toMatchObject({
      vatRateBps: null,
      taxOutAmount: null,
      source: 'MISSING',
    });
    expect(result.missingSkus).toEqual(['SKU-1']);
  });
});

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
