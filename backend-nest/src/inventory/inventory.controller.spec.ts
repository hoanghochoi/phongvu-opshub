import { ForbiddenException } from '@nestjs/common';
import { InventoryController } from './inventory.controller';

describe('InventoryController', () => {
  let controller: InventoryController;
  let inventoryService: {
    lookupBySku: jest.Mock;
    lookupByBin: jest.Mock;
    syncFromBigQuery: jest.Mock;
  };

  beforeEach(() => {
    inventoryService = {
      lookupBySku: jest.fn(),
      lookupByBin: jest.fn(),
      syncFromBigQuery: jest.fn(),
    };
    controller = new InventoryController(inventoryService as any);
  });

  it('looks up inventory by SKU by default', async () => {
    inventoryService.lookupBySku.mockResolvedValue([{ sku: 'SKU1' }]);

    await expect(controller.lookup('SKU1', undefined as any)).resolves.toEqual([
      { sku: 'SKU1' },
    ]);
    expect(inventoryService.lookupBySku).toHaveBeenCalledWith('SKU1');
  });

  it('looks up inventory by BIN when requested', async () => {
    inventoryService.lookupByBin.mockResolvedValue([{ bin: 'BIN-A' }]);

    await expect(controller.lookup('BIN-A', 'bin')).resolves.toEqual([
      { bin: 'BIN-A' },
    ]);
    expect(inventoryService.lookupByBin).toHaveBeenCalledWith('BIN-A');
  });

  it('triggers manual BigQuery sync', async () => {
    inventoryService.syncFromBigQuery.mockResolvedValue(undefined);

    await expect(
      controller.manualSync({ user: { role: 'ADMIN' } }),
    ).resolves.toEqual({
      message: 'BigQuery sync triggered',
    });
  });

  it('rejects manual BigQuery sync for non-admin users', async () => {
    await expect(
      controller.manualSync({ user: { role: 'STAFF' } }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(inventoryService.syncFromBigQuery).not.toHaveBeenCalled();
  });
});
