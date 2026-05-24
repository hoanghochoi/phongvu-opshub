import { OpshubFifoInventoryService } from './opshub-fifo-inventory.service';

describe('OpshubFifoInventoryService', () => {
  it('uses manual import date only as the FIFO import date fallback', async () => {
    const service = new OpshubFifoInventoryService();
    const config = (service as any).getConfig();
    const client = { query: jest.fn().mockResolvedValue({ rowCount: 1 }) };
    const manualImportDate = new Date('2026-04-01T00:00:00.000Z');

    await (service as any).upsertManualInventoryChunk(client, config, [
      {
        id: 'CP62:SMYXFX06J76',
        srCode: 'CP62',
        srName: 'PHAN DANG LUU',
        sku: '251010231',
        skuName: 'MacBook Pro',
        serialNumber: 'SMYXFX06J76',
        serialType: 'Thuong',
        serialTypeChangedAt: null,
        brand: 'Apple',
        categoryId: 'NH05',
        categoryName: 'Apple',
        subcategoryId: 'NH05-01-01-01',
        subcategoryName: 'Macbook',
        partNumber: 'MDE14SA/A',
        unit: 'Cai',
        bin: '01-VHH.01-01-a',
        binName: '01-VHH.01-01-a',
        zone: 'Trung bay hang ban moi',
        binType: null,
        manualImportDate,
        count: 1,
        stockType: 'Hang ban',
        purchaseStatus: null,
      },
    ]);

    const [sql, values] = client.query.mock.calls[0] as [string, unknown[]];

    expect(sql).toContain('INSERT INTO "fifo_inventory" AS target');
    expect(sql).toContain('manual_import_date');
    expect(sql).toContain(
      'COALESCE(target.bigquery_import_date, target."import_date", EXCLUDED.manual_import_date)',
    );
    expect(values).toHaveLength(24);
    expect(values[19]).toBe(manualImportDate);
    expect(values[20]).toBe(manualImportDate);
  });
});
