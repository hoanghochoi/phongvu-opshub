import {
  OpshubFifoInventoryService,
  rowToCanonicalItem,
} from './opshub-fifo-inventory.service';

describe('OpshubFifoInventoryService', () => {
  it('maps BigQuery rows using canonical column names', () => {
    const item = rowToCanonicalItem(
      {
        Serial: '225ABC967',
        SKU: 250403171,
        SKU_name: 'Product 250403171',
        Branch_ID: 'CP62',
        Branch_name: 'Branch 62',
        Brand: 'Apple',
        Category_ID: 'NH05',
        Category_name: 'Apple',
        SubCategory_ID: 'NH05-02-01-01',
        SubCategory_name: 'Iphone',
        Location: '06-VK5.03-01-d',
        BIN_type: 'Hàng bán mới tại kho',
        BIN_zone: 'Trưng bày hàng bán mới',
        Date_import_company: { value: '2026-03-04' },
        Date_import_site: { value: '2026-03-05' },
        Inventory: 1,
        Purchase_status: 'OK',
      },
      1,
      'bigquery',
    );

    expect(item).toMatchObject({
      itemKey: 'CP62:225ABC967',
      branchId: 'CP62',
      sku: '250403171',
      location: '06-VK5.03-01-d',
      binType: 'Hàng bán mới tại kho',
      inventory: 1,
      purchaseStatus: 'OK',
    });
    expect(item?.dateImportCompany?.toISOString()).toBe(
      '2026-03-04T00:00:00.000Z',
    );
    expect(item?.dateImportSite?.toISOString()).toBe(
      '2026-03-05T00:00:00.000Z',
    );
  });

  it('keeps manual import additive and does not deactivate SR inventory', async () => {
    const service = new OpshubFifoInventoryService();
    const client = {
      query: jest.fn().mockResolvedValue({ rowCount: 1 }),
      release: jest.fn(),
    };
    jest.spyOn(service as any, 'ensureSchema').mockResolvedValue(undefined);
    jest.spyOn(service as any, 'getPool').mockReturnValue({
      connect: jest.fn().mockResolvedValue(client),
    });

    await expect(
      service.importManualInventory([canonicalItem()]),
    ).resolves.toMatchObject({ importedRows: 1, deactivatedRows: 0 });

    const sql = client.query.mock.calls
      .map(([query]) => String(query))
      .join('\n');
    expect(sql).toContain('BEGIN');
    expect(sql).toContain('INSERT INTO "fifo_inventory" AS target');
    expect(sql).toContain('"opshub_item_key"');
    expect(sql).not.toContain("opshub_source} = 'bigquery'");
    expect(sql).toContain('COMMIT');
    expect(client.release).toHaveBeenCalled();
  });

  it('upserts BigQuery rows and deactivates missing BigQuery rows for synced SRs', async () => {
    const service = new OpshubFifoInventoryService();
    const client = {
      query: jest.fn().mockResolvedValue({ rowCount: 2 }),
      release: jest.fn(),
    };
    jest.spyOn(service as any, 'ensureSchema').mockResolvedValue(undefined);
    jest.spyOn(service as any, 'getPool').mockReturnValue({
      connect: jest.fn().mockResolvedValue(client),
    });

    await expect(
      service.importBigQueryInventory([canonicalItem()]),
    ).resolves.toMatchObject({ importedRows: 1, deactivatedRows: 2 });

    const sql = client.query.mock.calls
      .map(([query]) => String(query))
      .join('\n');
    expect(sql).toContain('INSERT INTO "fifo_inventory" AS target');
    expect(sql).toContain('"Date_import_company"');
    expect(sql.match(/"exported" =/g)).toHaveLength(1);
    expect(sql).toContain('"opshub_source" = \'bigquery\'');
    expect(sql).toContain('AND NOT ("opshub_item_key"::text = ANY');
  });

  it('filters SKU queries using active canonical BigQuery columns', async () => {
    const service = new OpshubFifoInventoryService();
    jest.spyOn(service as any, 'ensureSchema').mockResolvedValue(undefined);
    jest.spyOn(service as any, 'getPool').mockReturnValue({
      query: jest.fn().mockResolvedValue({ rows: [] }),
    });

    await service.findBySku('CP62', '250403171', false);

    const pool = (service as any).getPool();
    const [sql, values] = pool.query.mock.calls[0] as [string, unknown[]];
    expect(sql).toContain('"Branch_ID"');
    expect(sql).toContain('"SKU"');
    expect(sql).toContain('"BIN_type"');
    expect(sql).toContain('Hàng trưng bày chỉ định');
    expect(sql).toContain('"opshub_exported"');
    expect(values).toEqual(['CP62', '250403171']);
  });
});

function canonicalItem(overrides: Record<string, unknown> = {}) {
  return {
    itemKey: 'CP62:225ABC967',
    serial: '225ABC967',
    sku: '250403171',
    skuName: 'Product 250403171',
    branchId: 'CP62',
    branchName: 'Branch 62',
    brand: 'Apple',
    categoryId: 'NH05',
    categoryName: 'Apple',
    subCategoryId: 'NH05-02-01-01',
    subCategoryName: 'Iphone',
    subcatIdLowestLevel: null,
    subcatNameLowestLevel: null,
    location: '06-VK5.03-01-d',
    binType: 'Hàng bán mới tại kho',
    binZone: 'Trưng bày hàng bán mới',
    dateImportCompany: new Date('2026-03-04T00:00:00.000Z'),
    dateImportSite: new Date('2026-03-04T00:00:00.000Z'),
    agingCompany: null,
    badStockCompany: null,
    agingSite: null,
    stockDaySite: null,
    badStockSite: null,
    stockDayCompany: null,
    purchaseStatus: null,
    inventory: 1,
    inventoryAmount: null,
    manualPayload: null,
    ...overrides,
  } as any;
}
