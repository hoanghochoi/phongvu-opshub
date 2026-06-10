import { NotFoundException } from '@nestjs/common';
import { FifoLogType } from '@prisma/client';
import { FifoService } from './fifo.service';

describe('FifoService', () => {
  let service: FifoService;
  let prisma: { store: { findUnique: jest.Mock } };
  let inventory: {
    findBySku: jest.Mock;
    findByBin: jest.Mock;
    findBySerial: jest.Mock;
    findOldestActiveForSku: jest.Mock;
    setExported: jest.Mock;
    importManualInventory: jest.Mock;
  };
  let fifoLogService: { createLog: jest.Mock };

  const user = {
    email: 'staff@phongvu-shop.vn',
    storeId: 'store-uuid-1',
  };

  beforeEach(() => {
    delete process.env.FIFO_DATE_TOLERANCE_DAYS;
    prisma = {
      store: { findUnique: jest.fn().mockResolvedValue({ storeId: 'CP01' }) },
    };
    inventory = {
      findBySku: jest.fn(),
      findByBin: jest.fn(),
      findBySerial: jest.fn(),
      findOldestActiveForSku: jest.fn(),
      setExported: jest.fn(),
      importManualInventory: jest.fn(),
    };
    fifoLogService = { createLog: jest.fn() };
    service = new FifoService(
      prisma as any,
      inventory as any,
      fifoLogService as any,
    );
  });

  it('returns active SKU items scoped by SR and excludes exported by default', async () => {
    inventory.findBySku.mockResolvedValue([
      item({ id: 'oldest', serialNumber: 'S1' }),
      item({ id: 'newer', serialNumber: 'S2' }),
    ]);

    await expect(service.check(user, { text: 'sku1' })).resolves.toMatchObject({
      mode: 'sku',
      srCode: 'CP01',
      items: [
        { id: 'oldest', fifo: 'yes', exported: false },
        { id: 'newer', fifo: null, exported: false },
      ],
    });
    expect(inventory.findBySku).toHaveBeenCalledWith('CP01', 'SKU1', false);
  });

  it('includes exported SKU items when requested', async () => {
    inventory.findBySku.mockResolvedValue([
      item({ id: 'oldest', exported: true }),
    ]);

    await service.check(user, { text: 'SKU1', includeExported: true });

    expect(inventory.findBySku).toHaveBeenCalledWith('CP01', 'SKU1', true);
  });

  it('returns correct for the oldest serial', async () => {
    inventory.findBySku.mockResolvedValue([]);
    inventory.findBySerial.mockResolvedValue(item({ id: 'oldest' }));
    inventory.findOldestActiveForSku.mockResolvedValue(item({ id: 'oldest' }));

    await expect(service.check(user, { text: 'S1' })).resolves.toMatchObject({
      mode: 'serial',
      status: 'correct',
      message: 'Đúng FIFO',
      fifoDateDeltaDays: 0,
      fifoToleranceDays: 20,
    });
  });

  it('returns correct when serial is within the 20 day FIFO tolerance', async () => {
    inventory.findBySku.mockResolvedValue([]);
    inventory.findBySerial.mockResolvedValue(
      item({ id: 'newer', serialNumber: 'S2', importDate: date('2026-03-21') }),
    );
    inventory.findOldestActiveForSku.mockResolvedValue(
      item({
        id: 'oldest',
        serialNumber: 'S1',
        importDate: date('2026-03-01'),
      }),
    );

    await expect(service.check(user, { text: 'S2' })).resolves.toMatchObject({
      mode: 'serial',
      status: 'correct',
      message: 'Đúng FIFO',
      fifoDateDeltaDays: 20,
    });
  });

  it('returns wrong and suggests the oldest item when serial is beyond tolerance', async () => {
    inventory.findBySku.mockResolvedValue([]);
    inventory.findBySerial.mockResolvedValue(
      item({ id: 'newer', serialNumber: 'S2', importDate: date('2026-03-22') }),
    );
    inventory.findOldestActiveForSku.mockResolvedValue(
      item({
        id: 'oldest',
        serialNumber: 'S1',
        importDate: date('2026-03-01'),
      }),
    );

    await expect(service.check(user, { text: 'S2' })).resolves.toMatchObject({
      mode: 'serial',
      status: 'wrong',
      message: 'Sai FIFO',
      fifoDateDeltaDays: 21,
      suggestedItem: { id: 'oldest', serial_number: 'S1' },
    });
  });

  it('does not use tolerance when a FIFO date is missing', async () => {
    inventory.findBySku.mockResolvedValue([]);
    inventory.findBySerial.mockResolvedValue(
      item({ id: 'newer', serialNumber: 'S2', importDate: null }),
    );
    inventory.findOldestActiveForSku.mockResolvedValue(
      item({
        id: 'oldest',
        serialNumber: 'S1',
        importDate: date('2026-03-01'),
      }),
    );

    await expect(service.check(user, { text: 'S2' })).resolves.toMatchObject({
      status: 'wrong',
      fifoDateDeltaDays: null,
    });
  });

  it('returns display_reserved for display-reserved serials', async () => {
    inventory.findBySku.mockResolvedValue([]);
    inventory.findBySerial.mockResolvedValue(
      item({ id: 'display', binType: 'Hàng trưng bày chỉ định' }),
    );

    await expect(service.check(user, { text: 'S1' })).resolves.toMatchObject({
      mode: 'serial',
      status: 'display_reserved',
      message: 'Hàng trưng bày chỉ định',
    });
    expect(inventory.findOldestActiveForSku).not.toHaveBeenCalled();
  });

  it('returns exported status for an exported serial so it can be unmarked', async () => {
    inventory.findBySku.mockResolvedValue([]);
    inventory.findBySerial.mockResolvedValue(
      item({ id: 'exported-item', exported: true }),
    );

    await expect(service.check(user, { text: 'S1' })).resolves.toMatchObject({
      mode: 'serial',
      status: 'exported',
      item: { id: 'exported-item', exported: true },
    });
    expect(inventory.findOldestActiveForSku).not.toHaveBeenCalled();
  });

  it('exports and unexports only inventory rows in the user SR', async () => {
    inventory.setExported.mockResolvedValue(
      item({ id: 'item-1', exported: true }),
    );

    await expect(
      service.setExported(user, { inventoryId: 'item-1', exported: true }),
    ).resolves.toMatchObject({
      status: 'success',
      srCode: 'CP01',
      item: { id: 'item-1', exported: true },
    });
    expect(inventory.setExported).toHaveBeenCalledWith('CP01', 'item-1', true);
  });

  it('rejects export when the row is outside the user SR', async () => {
    inventory.setExported.mockResolvedValue(null);

    await expect(
      service.setExported(user, { inventoryId: 'item-2', exported: true }),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it('sorts from OpsHub FIFO inventory by SKU first and logs FIFO_SORT', async () => {
    inventory.findBySku.mockResolvedValue([
      item({ id: 'sku-item', serialNumber: 'S1' }),
    ]);

    await expect(service.sort(user, { text: 'sku1' })).resolves.toMatchObject([
      { id: 'sku-item', sku: 'SKU1', serial_number: 'S1' },
    ]);
    expect(inventory.findBySku).toHaveBeenCalledWith('CP01', 'SKU1', false);
    expect(inventory.findByBin).not.toHaveBeenCalled();
    expect(fifoLogService.createLog).toHaveBeenCalledWith(
      FifoLogType.FIFO_SORT,
      'SKU1',
      '1 item(s) found',
      expect.objectContaining({ srCode: 'CP01' }),
      'staff@phongvu-shop.vn',
    );
  });

  it('falls back to OpsHub FIFO inventory BIN sort when SKU is empty', async () => {
    inventory.findBySku.mockResolvedValue([]);
    inventory.findByBin.mockResolvedValue([
      item({ id: 'bin-item', bin: 'BIN-A' }),
    ]);

    await expect(service.sort(user, { text: 'bin-a' })).resolves.toMatchObject([
      { id: 'bin-item', bin: 'BIN-A' },
    ]);
    expect(inventory.findBySku).toHaveBeenCalledWith('CP01', 'BIN-A', false);
    expect(inventory.findByBin).toHaveBeenCalledWith('CP01', 'BIN-A', false);
  });

  it('allows ADMIN_PHONGVU users to import manual inventory', async () => {
    inventory.importManualInventory.mockResolvedValue({
      importedRows: 2,
      deactivatedRows: 0,
      srCodes: ['CP62'],
    });

    await expect(
      service.importManualInventory(
        { ...user, role: 'ADMIN_PHONGVU' },
        [canonicalItem({ itemKey: 'CP62:S1', branchId: 'CP62' })],
        { fileName: 'inventory.xlsx', totalRows: 2, skippedRows: 0 },
      ),
    ).resolves.toMatchObject({
      importedRows: 2,
      deactivatedRows: 0,
      skippedRows: 0,
      totalRows: 2,
      srCodes: ['CP62'],
    });
  });

  it('blocks non-admin users from importing manual inventory', async () => {
    await expect(
      service.importManualInventory(
        { ...user, role: 'MANAGER' },
        [canonicalItem({ itemKey: 'CP62:S1', branchId: 'CP62' })],
        { fileName: 'inventory.xlsx', totalRows: 1, skippedRows: 0 },
      ),
    ).rejects.toThrow('Chỉ ADMIN trở lên');
    expect(inventory.importManualInventory).not.toHaveBeenCalled();
  });
});

function item(overrides: Partial<ReturnType<typeof itemBase>> = {}) {
  return { ...itemBase(), ...overrides };
}

function itemBase() {
  return {
    id: 'item-1',
    srCode: 'CP01',
    sku: 'SKU1',
    skuName: 'Product 1',
    serialNumber: 'S1',
    bin: 'BIN-A',
    zone: 'Z1',
    binType: 'Hàng bán mới tại kho',
    importDate: date('2026-03-01'),
    dateImportCompany: date('2026-03-01'),
    dateImportSite: date('2026-03-01'),
    count: 1,
    exported: false,
    source: 'bigquery',
  };
}

function canonicalItem(overrides: Record<string, unknown> = {}) {
  return {
    itemKey: 'CP62:S1',
    serial: 'S1',
    sku: 'SKU1',
    skuName: 'Product 1',
    branchId: 'CP62',
    branchName: 'Branch 62',
    brand: null,
    categoryId: null,
    categoryName: null,
    subCategoryId: null,
    subCategoryName: null,
    subcatIdLowestLevel: null,
    subcatNameLowestLevel: null,
    location: 'BIN-A',
    binType: 'Hàng bán mới tại kho',
    binZone: 'Z1',
    dateImportCompany: null,
    dateImportSite: date('2026-03-01'),
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

function date(value: string) {
  return new Date(`${value}T00:00:00.000Z`);
}
