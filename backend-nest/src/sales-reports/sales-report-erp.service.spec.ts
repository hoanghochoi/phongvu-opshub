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

  it('uses Listing category codes as auto-fill category candidates', async () => {
    process.env.ERP_ACCESS_TOKEN = 'static-access-token';
    const fetchMock = jest.fn(async (input: string | URL) => {
      const url = input.toString();
      if (
        url ===
        'https://staff-bff.tekoapis.com/api/v2/staff-admin/orders/26070132780090?thousandSeparator=%2C&decimalSeparator=.'
      ) {
        return jsonResponse({
          data: {
            order: {
              orderId: '26070132780090',
              confirmationStatus: 'active',
              fulfillmentStatus: 'PROCESSING',
              orderCaptureLineItems: [
                {
                  sellerSku: 'SKU-WIFI',
                  name: 'Card mạng PCIe WiFi AX1800 + Bluetooth 5.2 TP-Link Archer TX20E',
                  quantity: 1,
                },
              ],
              payments: [{ paymentMethod: 'cash', amount: 500000 }],
            },
          },
        });
      }
      if (url.startsWith('https://listing.tekoapis.com/api/products/')) {
        return jsonResponse({
          result: {
            products: [
              {
                sku: 'SKU-WIFI',
                name: 'Card mạng PCIe WiFi AX1800 + Bluetooth 5.2 TP-Link Archer TX20E',
                categories: [
                  {
                    id: 386102,
                    code: 'NH08',
                    name: 'Thiết bị mạng và an ninh',
                    level: 1,
                    parentId: 0,
                  },
                  {
                    id: 386200,
                    code: 'NH08-01-99-02',
                    name: 'Card mạng',
                    level: 3,
                    parentId: 386102,
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
    const result = await service.lookupOrder('26070132780090', 'CP62');

    expect(result.categoryCandidates).toEqual(['NH08']);
  });

  it('uses only Listing level-1 codes for a Logitech B100 order', async () => {
    process.env.ERP_ACCESS_TOKEN = 'static-access-token';
    const fetchMock = jest.fn(async (input: string | URL) => {
      const url = input.toString();
      if (
        url ===
        'https://staff-bff.tekoapis.com/api/v2/staff-admin/orders/26070133166730?thousandSeparator=%2C&decimalSeparator=.'
      ) {
        return jsonResponse({
          data: {
            order: {
              orderId: '26070133166730',
              confirmationStatus: 'active',
              fulfillmentStatus: 'PROCESSING',
              orderCaptureLineItems: [
                {
                  sellerSku: '240901775',
                  name: 'Chuột máy tính Logitech B100',
                  quantity: 1,
                },
              ],
              payments: [{ paymentMethod: 'cash', amount: 80000 }],
            },
          },
        });
      }
      if (url.startsWith('https://listing.tekoapis.com/api/products/')) {
        return jsonResponse({
          result: {
            products: [
              {
                sku: '240901775',
                name: 'Chuột máy tính Logitech B100',
                productGroup: {
                  code: 'NH01-FAKE',
                  name: 'Phụ kiện Laptop',
                },
                productType: {
                  code: 'NH02-FAKE',
                  name: 'Phụ kiện PC',
                },
                categories: [
                  {
                    id: 386106,
                    code: 'NH06',
                    name: 'Thiết bị ngoại vi',
                    level: 1,
                    parentId: 0,
                  },
                  {
                    code: 'NH01-02-03',
                    name: 'Phụ kiện Laptop',
                    level: 2,
                  },
                  {
                    code: 'NH02-02-03',
                    name: 'Phụ kiện PC',
                    level: 2,
                  },
                  {
                    code: 'NH06-03-01-01',
                    name: 'Chuột máy tính',
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
    const result = await service.lookupOrder('26070133166730', 'CP62');

    expect(result.customerNeed).toBe('Chuột máy tính Logitech B100');
    expect(result.categoryCandidates).toEqual(['NH06']);
    expect(result.categoryCandidates).not.toContain('NH01');
    expect(result.categoryCandidates).not.toContain('NH02');
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
        expect(parsed.searchParams.get('limit')).toBe('100');
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
                terminalName: 'Kho DDKD37 - 40-42 Thai Nguyen, P. Phuong Sai',
                createdFromSiteDisplayName:
                  '[CH1001] CHI NHANH 30 - CONG TY CO PHAN THUONG MAI - DICH VU PHONG VU',
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
    });

    expect(result).toHaveLength(1);
    expect(result[0]).toMatchObject({
      orderCode: '2607010002',
      storeCode: 'CH1001',
      terminalName: 'Kho DDKD37 - 40-42 Thai Nguyen, P. Phuong Sai',
      grandTotal: 2500000,
      customerType: 'BUSINESS',
      consultantEmail: 'sale@phongvu.vn',
      paymentMethods: ['cash'],
    });
    expect(result[0].sanitizedSnapshot.billingInfo).toEqual({
      customerType: 'PERSONAL',
      hasTaxCode: true,
    });
    expect(result[0].sanitizedSnapshot.createdFromSiteDisplayName).toBe(
      '[CH1001] CHI NHANH 30 - CONG TY CO PHAN THUONG MAI - DICH VU PHONG VU',
    );
  });

  it('uses data.orders.creator.email as the cached order owner email', async () => {
    process.env.ERP_ACCESS_TOKEN = 'static-access-token';
    const fetchMock = jest.fn(async (input: string | URL) => {
      const url = input.toString();
      if (
        url.startsWith(
          'https://staff-bff.tekoapis.com/api/v2/staff-admin/orders?',
        )
      ) {
        return jsonResponse({
          data: {
            orders: [
              {
                orderId: '2607010003',
                createdAt: '2026-07-01T02:00:00Z',
                paymentStatus: 'fully_paid',
                confirmationStatus: 'active',
                fulfillmentStatus: 'PROCESSING',
                terminalName: 'CP01',
                grandTotal: 3500000,
                customerName: 'Le Van C',
                creator: {
                  id: 'creator-1',
                  name: 'Sale CP01',
                  email: 'sale.cp01@phongvu.vn',
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
      storeCode: 'CP01',
    });

    expect(result).toHaveLength(1);
    expect(result[0]).toMatchObject({
      orderCode: '2607010003',
      storeCode: 'CP01',
      consultantName: 'Sale CP01',
      consultantEmail: 'sale.cp01@phongvu.vn',
      sellerId: 'creator-1',
      sellerName: 'Sale CP01',
      sellerEmail: 'sale.cp01@phongvu.vn',
    });
    expect(result[0].sanitizedSnapshot).toMatchObject({
      creator: {
        id: 'creator-1',
        name: 'Sale CP01',
        email: 'sale.cp01@phongvu.vn',
      },
    });
  });

  it('extracts store code from leading createdFromSiteDisplayName text', async () => {
    process.env.ERP_ACCESS_TOKEN = 'static-access-token';
    const fetchMock = jest.fn(async (input: string | URL) => {
      const url = input.toString();
      if (
        url.startsWith(
          'https://staff-bff.tekoapis.com/api/v2/staff-admin/orders?',
        )
      ) {
        return jsonResponse({
          data: {
            orders: [
              {
                orderId: '26070133166730',
                createdAt: '2026-07-01T03:50:00Z',
                paymentStatus: 'fully_paid',
                confirmationStatus: 'active',
                fulfillmentStatus: 'PROCESSING',
                terminalName: '264A-264B-264C Nguyen Thi Minh Khai',
                createdFromSiteDisplayName:
                  'CP01 - 264A-264B-264C Nguyen Thi Minh Khai, Phuong 6',
                grandTotal: 160000,
                creator: {
                  email: 'sale.cp01@phongvu.vn',
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
    });

    expect(result).toHaveLength(1);
    expect(result[0]).toMatchObject({
      orderCode: '26070133166730',
      storeCode: 'CP01',
      terminalName: '264A-264B-264C Nguyen Thi Minh Khai',
      consultantEmail: 'sale.cp01@phongvu.vn',
    });
    expect(result[0].sanitizedSnapshot.createdFromSiteDisplayName).toBe(
      'CP01 - 264A-264B-264C Nguyen Thi Minh Khai, Phuong 6',
    );
  });

  it('classifies pending, completed, canceled, partial and full returns from ERP payloads', async () => {
    process.env.ERP_ACCESS_TOKEN = 'static-access-token';
    const orders: Record<string, Record<string, unknown>> = {
      '2607011001': {
        orderId: '2607011001',
        confirmationStatus: 'active',
        fulfillmentStatus: 'PROCESSING',
        platformId: 3,
        grandTotal: 1000000,
      },
      '2607011002': {
        orderId: '2607011002',
        confirmationStatus: 'active',
        fulfillmentStatus: 'DELIVERED',
        platformId: 3,
        grandTotal: 1000000,
      },
      '2607011003': {
        orderId: '2607011003',
        confirmationStatus: 'Active',
        fulfillmentStatus: 'cAnCeLlEd',
        platformId: 3,
        grandTotal: 1000000,
      },
      '2607011004': {
        orderId: '2607011004',
        confirmationStatus: 'active',
        fulfillmentStatus: 'DELIVERED',
        platformId: 3,
        grandTotal: 1000000,
      },
      '2607011005': {
        orderId: '2607011005',
        confirmationStatus: 'active',
        fulfillmentStatus: 'DELIVERED',
        hasReturnedFullItems: true,
        platformId: 3,
        grandTotal: 1000000,
      },
    };
    const fetchMock = jest.fn(async (input: string | URL) => {
      const url = new URL(input.toString());
      if (url.pathname.startsWith('/api/v2/staff-admin/orders/')) {
        const orderCode = url.pathname.split('/').pop()!;
        return jsonResponse({ data: { order: orders[orderCode] } });
      }
      if (url.pathname === '/api/v2/return-requests') {
        const orderCode = url.searchParams.get('orderIds');
        if (orderCode === '2607011004') {
          return jsonResponse({
            request: [
              {
                id: 'return-1',
                status: 'RETURN_STATUS_RETURNED',
                refunds: [{ status: 'REFUND_STATUS_PENDING' }],
                items: [{ returnedQuantity: 2, unitAfterTaxPrice: 100000 }],
              },
              {
                id: 'return-1',
                status: 'RETURN_STATUS_RETURNED',
                items: [{ returnedQuantity: 2, unitAfterTaxPrice: 100000 }],
              },
              {
                id: 'return-2',
                status: 'RETURN_STATUS_RETURNED',
                items: [{ returnedQuantity: 1, unitAfterTaxPrice: 50000 }],
              },
            ],
          });
        }
        return jsonResponse({ request: [] });
      }
      throw new Error(`Unexpected fetch: ${url}`);
    }) as jest.MockedFunction<typeof fetch>;
    global.fetch = fetchMock;

    const service = new SalesReportErpService();
    await expect(
      service.lookupOrderStatus('2607011001'),
    ).resolves.toMatchObject({
      lifecycleStatus: 'PENDING',
      returnedAfterTaxAmount: 0,
    });
    await expect(
      service.lookupOrderStatus('2607011002'),
    ).resolves.toMatchObject({
      lifecycleStatus: 'COMPLETED',
      returnedAfterTaxAmount: 0,
    });
    await expect(
      service.lookupOrderStatus('2607011003'),
    ).resolves.toMatchObject({ lifecycleStatus: 'CANCELLED' });
    await expect(
      service.lookupOrderStatus('2607011004'),
    ).resolves.toMatchObject({
      lifecycleStatus: 'COMPLETED_PARTIAL_RETURN',
      returnedAfterTaxAmount: 250000,
    });
    await expect(
      service.lookupOrderStatus('2607011005'),
    ).resolves.toMatchObject({
      lifecycleStatus: 'RETURNED_FULL',
      hasReturnedFullItems: true,
      returnedAfterTaxAmount: 1000000,
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
