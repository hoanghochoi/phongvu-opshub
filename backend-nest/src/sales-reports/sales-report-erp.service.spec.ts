import { SalesReportErpService } from './sales-report-erp.service';

describe('SalesReportErpService', () => {
  const originalEnv = process.env;
  const originalFetch = global.fetch;

  beforeEach(() => {
    jest.useRealTimers();
    process.env = {
      ...originalEnv,
      ERP_USERNAME: 'sale@example.com',
      ERP_PASSWORD: 'secret-password',
      ERP_IDENTITY_BASE_URL: 'https://identity.tekoapis.com',
      ERP_OAUTH_BASE_URL: 'https://oauth-merchant.phongvu.vn',
      ERP_STAFF_BFF_BASE_URL: 'https://staff-bff.tekoapis.com',
      ERP_LISTING_BASE_URL: 'https://listing.tekoapis.com',
    };
  });

  afterEach(() => {
    global.fetch = originalFetch;
    process.env = originalEnv;
    jest.restoreAllMocks();
  });

  it('uses ERP redirect_to login flow before fetching an order', async () => {
    const fetchMock = jest.fn(async (input: string | URL) => {
      const url = input.toString();
      if (
        url.startsWith('https://oauth-merchant.phongvu.vn/oauth/authorize') &&
        !url.includes('login_verifier=')
      ) {
        return redirectResponse(
          'https://identity.teko.vn/login?challenge=challenge-123',
        );
      }
      if (url === 'https://identity.tekoapis.com/api/v1/users/login') {
        return jsonResponse({
          redirect_to:
            'https://oauth-merchant.phongvu.vn/oauth/authorize?client_id=erp-client&login_verifier=verifier-123',
        });
      }
      if (url.includes('login_verifier=verifier-123')) {
        return redirectResponse('https://erp.phongvu.vn/?code=code-123');
      }
      if (url === 'https://oauth-merchant.phongvu.vn/oauth/token') {
        return jsonResponse({
          access_token: 'access-token-123',
          expires_in: 3600,
        });
      }
      if (
        url ===
        'https://staff-bff.tekoapis.com/api/v2/staff-admin/orders/2606290001?thousandSeparator=%2C&decimalSeparator=.'
      ) {
        return jsonResponse({
          data: {
            order: {
              orderId: '2606290001',
              createdAt: '2026-06-29T00:00:00Z',
              paymentStatus: 'fully_paid',
              confirmationStatus: 'active',
              fulfillmentStatus: 'PROCESSING',
              terminalName: 'CP62',
              grandTotal: 1230000,
              platformId: 1,
              consultant: { customId: '7583', name: 'Sale CP62' },
              orderCaptureLineItems: [
                {
                  sellerSku: 'SKU-1',
                  name: 'RAM DDR5',
                  quantity: 1,
                  sellPrice: 1230000,
                  finalSellPrice: 1230000,
                  rowTotal: 1230000,
                },
              ],
              payments: [{ paymentMethod: 'cash', amount: 1230000 }],
            },
          },
        });
      }
      if (url.startsWith('https://listing.tekoapis.com/api/products/')) {
        return jsonResponse({
          result: {
            products: [
              {
                sku: 'SKU-1',
                name: 'RAM DDR5',
                productGroup: { id: 'NH03', name: 'Computer components' },
              },
            ],
          },
        });
      }
      throw new Error(`Unexpected fetch: ${url}`);
    }) as jest.MockedFunction<typeof fetch>;
    global.fetch = fetchMock;

    const service = new SalesReportErpService();
    const result = await service.lookupOrder(' 2606290001 ', 'CP62');

    expect(result.erpOrderId).toBe('2606290001');
    expect(result.items).toHaveLength(1);
    expect(result.items[0].productGroupId).toBe('NH03');
    expect(
      fetchMock.mock.calls.some(([input]) =>
        input.toString().includes('login_verifier=verifier-123'),
      ),
    ).toBe(true);
    expect(
      fetchMock.mock.calls.some(
        ([input, init]) =>
          input.toString().includes('/staff-admin/orders/2606290001') &&
          init?.headers &&
          String((init.headers as Record<string, string>).Authorization) ===
            'Bearer access-token-123',
      ),
    ).toBe(true);
  });
});

function redirectResponse(location: string) {
  return new Response(null, {
    status: 302,
    headers: { location },
  });
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}
