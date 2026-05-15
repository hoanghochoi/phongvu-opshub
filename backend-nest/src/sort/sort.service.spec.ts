import { SortService } from './sort.service';
import { FifoLogType } from '@prisma/client';

describe('SortService', () => {
  let service: SortService;
  let inventoryService: {
    lookupBySku: jest.Mock;
    lookupByBin: jest.Mock;
    fifoCheckBySku: jest.Mock;
    fifoCheckBySerial: jest.Mock;
  };
  let fifoLogService: { createLog: jest.Mock };

  beforeEach(() => {
    inventoryService = {
      lookupBySku: jest.fn(),
      lookupByBin: jest.fn(),
      fifoCheckBySku: jest.fn(),
      fifoCheckBySerial: jest.fn(),
    };
    fifoLogService = { createLog: jest.fn() };
    service = new SortService(inventoryService as any, fifoLogService as any);
  });

  it('falls back to BIN lookup when SKU lookup is empty and logs the result', async () => {
    const binItems = [{ sku: 'SKU1', bin: 'BIN-A' }];
    inventoryService.lookupBySku.mockResolvedValue([]);
    inventoryService.lookupByBin.mockResolvedValue(binItems);

    await expect(service.sort('BIN-A', 'staff@phongvu-shop.vn')).resolves.toBe(
      binItems,
    );
    expect(inventoryService.lookupBySku).toHaveBeenCalledWith('BIN-A');
    expect(inventoryService.lookupByBin).toHaveBeenCalledWith('BIN-A');
    expect(fifoLogService.createLog).toHaveBeenCalledWith(
      FifoLogType.FIFO_SORT,
      'BIN-A',
      '1 item(s) found',
      binItems,
      'staff@phongvu-shop.vn',
    );
  });

  it('returns SKU FIFO check results without serial fallback', async () => {
    const skuItems = [{ sku: 'SKU1', serial_number: 'S1' }];
    inventoryService.fifoCheckBySku.mockResolvedValue(skuItems);

    await expect(
      service.fifoCheck('SKU1', 2, 'staff@phongvu-shop.vn'),
    ).resolves.toBe(skuItems);
    expect(inventoryService.fifoCheckBySku).toHaveBeenCalledWith('SKU1', 2);
    expect(inventoryService.fifoCheckBySerial).not.toHaveBeenCalled();
    expect(fifoLogService.createLog).toHaveBeenCalledWith(
      FifoLogType.FIFO_CHECK,
      'SKU1',
      'SKU check: 1 item(s)',
      skuItems,
      'staff@phongvu-shop.vn',
    );
  });

  it('falls back to serial FIFO check when SKU check is empty', async () => {
    const serialResult = { found: true, is_oldest: true, message: 'Đúng FIFO' };
    inventoryService.fifoCheckBySku.mockResolvedValue([]);
    inventoryService.fifoCheckBySerial.mockResolvedValue(serialResult);

    await expect(
      service.fifoCheck('SERIAL-1', undefined, 'staff@phongvu-shop.vn'),
    ).resolves.toBe(serialResult);
    expect(inventoryService.fifoCheckBySku).toHaveBeenCalledWith('SERIAL-1', 1);
    expect(inventoryService.fifoCheckBySerial).toHaveBeenCalledWith('SERIAL-1');
    expect(fifoLogService.createLog).toHaveBeenCalledWith(
      FifoLogType.FIFO_CHECK,
      'SERIAL-1',
      'Đúng FIFO',
      serialResult,
      'staff@phongvu-shop.vn',
    );
  });

  it('logs sort completion reports', async () => {
    const sortedSKUs = [{ sku: 'SKU1', count: 2 }];

    await expect(
      service.completionReport(
        sortedSKUs,
        'staff@phongvu-shop.vn',
        '2026-04-25T00:00:00.000Z',
      ),
    ).resolves.toEqual({ status: 'success', sortedCount: 1 });
    expect(fifoLogService.createLog).toHaveBeenCalledWith(
      FifoLogType.FIFO_SORT,
      'COMPLETION_REPORT',
      'Completed sorting 1 SKU group(s)',
      {
        sortedSKUs,
        timestamp: '2026-04-25T00:00:00.000Z',
      },
      'staff@phongvu-shop.vn',
    );
  });
});
