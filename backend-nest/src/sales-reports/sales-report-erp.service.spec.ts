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
              customerType: 'PERSONAL',
              billingInfo: {
                customerType: 'PERSONAL',
                taxCode: '0301485534',
              },
              customerName: 'Nguyen Van A',
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
                name: 'Thiết bị mạng/ Router TPLink Archer C54',
                productGroup: {
                  id: '80283',
                  code: 'NH08',
                  name: 'Thiết bị mạng/ Router TPLink Archer C54',
                },
                categories: [
                  { code: 'NH08', name: 'Network', level: 1 },
                  {
                    code: 'NH08-01-01-01',
                    name: 'Router',
                    level: 3,
                  },
                ],
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
    expect(result.customerType).toBe('BUSINESS');
    expect(result.customerName).toBe('Nguyen Van A');
    expect(result.erpCustomerType).toBe('PERSONAL');
    expect(result.sanitizedSnapshot.billingInfo).toEqual({
      customerType: 'PERSONAL',
      hasTaxCode: true,
    });
    expect(result.paymentMethods).toEqual(['cash']);
    expect(result.items).toHaveLength(1);
    expect(result.items[0].productGroupId).toBe('80283');
    expect(result.items[0].productGroupCode).toBe('NH08');
    expect(result.items[0].listingCategories).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ code: 'NH08-01-01-01', level: 3 }),
      ]),
    );
    expect(result.categoryCandidates).toEqual(expect.arrayContaining(['NH08']));
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

  it.each([
    ['confirmationStatus', 'CANCELLED'],
    ['fulfillmentStatus', 'cancelled'],
  ])('blocks canceled ERP orders when %s is %s', async (field, statusValue) => {
    process.env.ERP_ACCESS_TOKEN = 'static-access-token';
    const fetchMock = jest.fn(async (input: string | URL) => {
      const url = input.toString();
      if (
        url ===
        'https://staff-bff.tekoapis.com/api/v2/staff-admin/orders/2606290002?thousandSeparator=%2C&decimalSeparator=.'
      ) {
        return jsonResponse({
          data: {
            order: {
              orderId: '2606290002',
              confirmationStatus:
                field === 'confirmationStatus' ? statusValue : '',
              fulfillmentStatus:
                field === 'fulfillmentStatus' ? statusValue : '',
              orderCaptureLineItems: [{ sellerSku: 'SKU-1' }],
              payments: [{ paymentMethod: 'cash', amount: 1230000 }],
            },
          },
        });
      }
      if (url.startsWith('https://listing.tekoapis.com/api/products/')) {
        throw new Error('Listing lookup should not be called');
      }
      throw new Error(`Unexpected fetch: ${url}`);
    }) as jest.MockedFunction<typeof fetch>;
    global.fetch = fetchMock;

    const service = new SalesReportErpService();

    await expect(service.lookupOrder('2606290002', 'CP62')).rejects.toThrow(
      'Đơn đã bị hủy.',
    );
    expect(
      fetchMock.mock.calls.some(([input]) =>
        input.toString().startsWith('https://listing.tekoapis.com/'),
      ),
    ).toBe(false);
  });

  it('defaults blank ERP billingInfo to personal customer type', async () => {
    process.env.ERP_ACCESS_TOKEN = 'static-access-token';
    const fetchMock = jest.fn(async (input: string | URL) => {
      const url = input.toString();
      if (
        url ===
        'https://staff-bff.tekoapis.com/api/v2/staff-admin/orders/2606290003?thousandSeparator=%2C&decimalSeparator=.'
      ) {
        return jsonResponse({
          data: {
            order: {
              orderId: '2606290003',
              customerType: 'BUSINESS',
              billingInfo: { customerType: '', taxCode: '' },
              confirmationStatus: 'active',
              fulfillmentStatus: 'PROCESSING',
              orderCaptureLineItems: [],
              payments: [
                { paymentMethodName: 'Ví điện tử', amount: '1,230,000' },
              ],
            },
          },
        });
      }
      if (url.startsWith('https://listing.tekoapis.com/api/products/')) {
        return jsonResponse({ result: { products: [] } });
      }
      throw new Error(`Unexpected fetch: ${url}`);
    }) as jest.MockedFunction<typeof fetch>;
    global.fetch = fetchMock;

    const service = new SalesReportErpService();
    const result = await service.lookupOrder('2606290003', 'CP62');

    expect(result.customerType).toBe('PERSONAL');
    expect(result.erpCustomerType).toBeNull();
    expect(result.paymentMethods).toEqual(['Ví điện tử']);
    expect(result.payments[0].amount).toBe(1230000);
  });

  it('fetches recent ERP orders for the sales report cockpit cache', async () => {
    process.env.ERP_ACCESS_TOKEN = 'static-access-token';
    const fetchMock = jest.fn(async (input: string | URL) => {
      const url = input.toString();
      if (
        url.startsWith(
          'https://staff-bff.tekoapis.com/api/v2/staff-admin/orders?',
        )
      ) {
        const parsed = new URL(url);
        expect(parsed.searchParams.get('createdAtGte')).toBe(
          '2026-07-01T00:00:00+07:00',
        );
        expect(parsed.searchParams.get('createdAtLte')).toBe(
          '2026-07-01T23:59:59+07:00',
        );
        expect(parsed.searchParams.get('sellerId')).toBe('1');
        expect(parsed.searchParams.get('platformId')).toBe('3');
        expect(parsed.searchParams.get('limit')).toBe('50');
        expect(parsed.searchParams.get('sort')).toBe('-createdAt');
        return jsonResponse({
          data: {
            orders: [
              {
                orderId: '2607010002',
                createdAt: '2026-07-01T01:00:00Z',
                paymentStatus: 'fully_paid',
                confirmationStatus: 'active',
                fulfillmentStatus: 'PROCESSING',
                terminalName: 'CP62 - Phan Dang Luu',
                grandTotal: 2500000,
                customerName: 'Tran Thi B',
                customerType: 'PERSONAL',
                billingInfo: {
                  customerType: 'PERSONAL',
                  taxCode: '0301485534',
                },
                platformId: 3,
                consultant: {
                  customId: 'SA_CP62_HCM_MN',
                  name: 'Sale CP62',
                  email: 'sale@phongvu.vn',
                },
                payments: [{ paymentMethod: 'cash' }],
              },
            ],
          },
        });
      }
      throw new Error(`Unexpected fetch: ${url}`);
    }) as jest.MockedFunction<typeof fetch>;
    global.fetch = fetchMock;

    const service = new SalesReportErpService();
    const result = await service.listRecentOrders({
      date: '2026-07-01',
      storeCode: 'CP62',
    });

    expect(result).toHaveLength(1);
    expect(result[0]).toMatchObject({
      orderCode: '2607010002',
      storeCode: 'CP62',
      grandTotal: 2500000,
      customerType: 'BUSINESS',
      consultantEmail: 'sale@phongvu.vn',
      paymentMethods: ['cash'],
    });
    expect(result[0].sanitizedSnapshot.billingInfo).toEqual({
      customerType: 'PERSONAL',
      hasTaxCode: true,
    });
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
