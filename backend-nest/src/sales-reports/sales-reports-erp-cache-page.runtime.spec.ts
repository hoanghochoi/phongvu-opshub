import { SalesReportsErpCachePageRuntime } from './sales-reports-erp-cache-page.runtime';

describe('SalesReportsErpCachePageRuntime', () => {
  function createHarness() {
    const orders: any[] = [];
    const existingRows: any[] = [];
    const owners = new Map<string, any>();
    const stores = new Map<string, any>();
    const persistResults: any[] = [];
    const listRecentOrders = jest.fn(async () => orders);
    const loadExistingRows = jest.fn(async () => existingRows);
    const loadOwners = jest.fn(async () => owners);
    const loadStores = jest.fn(async () => stores);
    const persist = jest.fn(
      async () =>
        persistResults.shift() ?? { excluded: false, exclusionReason: null },
    );
    const runtime = new SalesReportsErpCachePageRuntime({
      listRecentOrders,
      loadExistingRows,
      loadOwners,
      loadStores,
      systemContext: () => ({ createdByUserId: null }),
      normalizeOrderCode: (value) =>
        String(value || '')
          .trim()
          .toUpperCase()
          .replace(/\s+/g, ''),
      normalizeStoreCode: (value) => {
        const normalized = String(value || '')
          .trim()
          .toUpperCase();
        return normalized || null;
      },
      authoritativeStoreCodeForCache: (snapshot, existingSnapshot) => {
        const read = (value: any) => {
          const match = String(value?.createdFromSiteDisplayName || '').match(
            /^\[([^\]]+)\]/,
          );
          return match?.[1] ?? null;
        };
        return read(snapshot) ?? read(existingSnapshot);
      },
      syncOrderOwner: (order, ownerByEmail) =>
        ownerByEmail.get(String(order.consultantEmail || '').toLowerCase()) ??
        ownerByEmail.get(String(order.sellerEmail || '').toLowerCase()) ??
        null,
      syncOrderOwnerFromEmails: (emailValues, ownerByEmail) => {
        for (const value of emailValues) {
          const owner = ownerByEmail.get(String(value || '').toLowerCase());
          if (owner) return owner;
        }
        return null;
      },
      persist,
      log: jest.fn(),
    });
    return {
      runtime,
      orders,
      existingRows,
      owners,
      stores,
      persistResults,
      listRecentOrders,
      loadExistingRows,
      loadOwners,
      loadStores,
      persist,
    };
  }

  function order(orderCode: string, storeCode: string, ownerEmail = 'owner@x') {
    return {
      orderCode,
      consultantEmail: ownerEmail,
      sellerEmail: null,
      sanitizedSnapshot: {
        orderCode,
        createdFromSiteDisplayName: `[${storeCode}] Phong Vu ${storeCode}`,
      },
    };
  }

  function row(orderCode: string, storeCode: string, ownerEmail = 'owner@x') {
    return {
      orderCode,
      sanitizedSnapshot: {
        orderCode,
        createdFromSiteDisplayName: `[${storeCode}] Phong Vu ${storeCode}`,
      },
      storeCode,
      organizationNodeId: `node-${storeCode}`,
      sourceUserId: 'owner-id',
      sourceUserEmail: ownerEmail,
      consultantEmail: ownerEmail,
      sellerEmail: null,
      excludedAt: null,
    };
  }

  it('preserves page offset and backfills an existing row from owner/store mapping', async () => {
    const harness = createHarness();
    harness.orders.push(order(' 2607 010002 ', 'CP01', 'current@x'));
    harness.existingRows.push({
      ...row('2607010002', 'CP62'),
      sourceUserId: null,
      sourceUserEmail: null,
    });
    harness.owners.set('current@x', {
      id: 'owner-current',
      email: 'current@x',
      storeCode: null,
      storeName: null,
      organizationNodeId: null,
    });
    harness.stores.set('CP01', { organizationNodeId: 'node-cp01' });

    await expect(
      harness.runtime.sync({
        date: '2026-07-01',
        limit: 50,
        offset: 100,
        source: 'characterization',
      }),
    ).resolves.toEqual({
      count: 1,
      newOrderCount: 0,
      mappedOrderCount: 1,
      excludedOrderCount: 0,
      orderCodes: ['2607010002'],
      storeCodes: ['CP01'],
      recipientUserIds: ['owner-current'],
    });
    expect(harness.listRecentOrders).toHaveBeenCalledWith({
      date: '2026-07-01',
      limit: 50,
      offset: 100,
    });
    expect(harness.persist).toHaveBeenCalledWith(
      null,
      { createdByUserId: null },
      harness.orders[0],
      harness.stores,
      expect.objectContaining({ id: 'owner-current' }),
      expect.objectContaining({
        existingCacheRow: harness.existingRows[0],
        preserveVerifiedLifecycle: true,
        canonicalGrandTotalFromList: true,
      }),
    );
  });

  it('deduplicates recipients and stores across visible new rows', async () => {
    const harness = createHarness();
    harness.orders.push(
      order('2607011001', 'CP01'),
      order('2607011002', 'CP01'),
    );
    harness.owners.set('owner@x', {
      id: 'owner-shared',
      email: 'owner@x',
      storeCode: 'CP01',
      storeName: null,
      organizationNodeId: 'node-cp01',
    });
    harness.stores.set('CP01', { organizationNodeId: 'node-cp01' });

    await expect(
      harness.runtime.sync({
        date: '2026-07-01',
        limit: 50,
        source: 'characterization',
      }),
    ).resolves.toEqual(
      expect.objectContaining({
        count: 2,
        newOrderCount: 2,
        mappedOrderCount: 0,
        excludedOrderCount: 0,
        storeCodes: ['CP01'],
        recipientUserIds: ['owner-shared'],
      }),
    );
  });

  it('counts only a newly excluded transition', async () => {
    const harness = createHarness();
    harness.orders.push(
      order('2607012001', 'CP01', 'one@x'),
      order('2607012002', 'CP02', 'two@x'),
    );
    harness.existingRows.push(row('2607012001', 'CP01', 'one@x'), {
      ...row('2607012002', 'CP02', 'two@x'),
      excludedAt: new Date(),
    });
    harness.owners.set('one@x', {
      id: 'owner-one',
      email: 'one@x',
      storeCode: 'CP01',
      storeName: null,
      organizationNodeId: 'node-cp01',
    });
    harness.owners.set('two@x', {
      id: 'owner-two',
      email: 'two@x',
      storeCode: 'CP02',
      storeName: null,
      organizationNodeId: 'node-cp02',
    });
    harness.stores.set('CP01', { organizationNodeId: 'node-cp01' });
    harness.stores.set('CP02', { organizationNodeId: 'node-cp02' });
    harness.persistResults.push(
      { excluded: true, exclusionReason: 'ERP_ORDER_CANCELLED' },
      { excluded: true, exclusionReason: 'ERP_ORDER_CANCELLED' },
    );

    await expect(
      harness.runtime.sync({
        date: '2026-07-01',
        limit: 50,
        source: 'characterization',
      }),
    ).resolves.toEqual(
      expect.objectContaining({
        count: 2,
        newOrderCount: 0,
        mappedOrderCount: 0,
        excludedOrderCount: 1,
        storeCodes: ['CP01'],
        recipientUserIds: ['owner-one'],
      }),
    );
  });

  it('does not report an unchanged existing row as a mapping change', async () => {
    const harness = createHarness();
    harness.orders.push(order('2607010002', 'CP62'));
    harness.existingRows.push(row('2607010002', 'CP62'));
    harness.owners.set('owner@x', {
      id: 'owner-id',
      email: 'owner@x',
      storeCode: 'CP62',
      storeName: null,
      organizationNodeId: 'node-CP62',
    });
    harness.stores.set('CP62', { organizationNodeId: 'node-CP62' });

    await expect(
      harness.runtime.sync({
        date: '2026-07-01',
        limit: 50,
        source: 'characterization',
      }),
    ).resolves.toEqual(
      expect.objectContaining({
        count: 1,
        newOrderCount: 0,
        mappedOrderCount: 0,
        excludedOrderCount: 0,
        storeCodes: [],
        recipientUserIds: [],
      }),
    );
  });

  it('returns an empty page without loading rows, stores or persisting', async () => {
    const harness = createHarness();

    await expect(
      harness.runtime.sync({
        date: '2026-07-01',
        limit: 50,
        source: 'characterization',
      }),
    ).resolves.toEqual({
      count: 0,
      newOrderCount: 0,
      mappedOrderCount: 0,
      excludedOrderCount: 0,
      orderCodes: [],
      storeCodes: [],
      recipientUserIds: [],
    });
    expect(harness.loadExistingRows).not.toHaveBeenCalled();
    expect(harness.loadStores).toHaveBeenCalledWith([]);
    expect(harness.persist).not.toHaveBeenCalled();
  });
});
