import { InventoryService } from './inventory.service';

describe('InventoryService', () => {
  let service: InventoryService;
  let prisma: {
    inventory: {
      findMany: jest.Mock;
      findFirst: jest.Mock;
      deleteMany: jest.Mock;
      createMany: jest.Mock;
    };
  };

  beforeEach(() => {
    prisma = {
      inventory: {
        findMany: jest.fn(),
        findFirst: jest.fn(),
        deleteMany: jest.fn(),
        createMany: jest.fn(),
      },
    };
    service = new InventoryService(prisma as any);
  });

  it('looks up SKU results in FIFO order and formats app fields', async () => {
    prisma.inventory.findMany.mockResolvedValue([
      {
        sku: 'SKU1',
        skuName: 'Product 1',
        serialNumber: 'SERIAL-1',
        bin: 'BIN-A',
        zone: 'Z1',
        importDate: new Date('2026-04-01T00:00:00.000Z'),
        count: 3,
      },
    ]);

    await expect(service.lookupBySku('SKU1')).resolves.toEqual([
      {
        sku: 'SKU1',
        sku_name: 'Product 1',
        serial_number: 'SERIAL-1',
        bin: 'BIN-A',
        zone: 'Z1',
        import_date: '01/04/2026',
        count: 3,
        fifo: 'yes',
      },
    ]);
    expect(prisma.inventory.findMany).toHaveBeenCalledWith({
      where: { sku: { contains: 'SKU1', mode: 'insensitive' } },
      orderBy: { importDate: 'asc' },
    });
  });

  it('takes qty plus one items for SKU FIFO checks', async () => {
    prisma.inventory.findMany.mockResolvedValue([]);

    await service.fifoCheckBySku('SKU1', 2);

    expect(prisma.inventory.findMany).toHaveBeenCalledWith({
      where: { sku: { equals: 'SKU1', mode: 'insensitive' } },
      orderBy: { importDate: 'asc' },
      take: 3,
    });
  });

  it('marks serial FIFO checks as wrong and suggests the oldest item', async () => {
    prisma.inventory.findFirst
      .mockResolvedValueOnce({
        sku: 'SKU1',
        skuName: 'Product 1',
        serialNumber: 'NEWER',
        importDate: new Date('2026-04-02T00:00:00.000Z'),
        count: 1,
      })
      .mockResolvedValueOnce({
        sku: 'SKU1',
        skuName: 'Product 1',
        serialNumber: 'OLDER',
        importDate: new Date('2026-04-01T00:00:00.000Z'),
        count: 1,
      });

    await expect(service.fifoCheckBySerial('NEWER')).resolves.toMatchObject({
      found: true,
      is_oldest: false,
      item: { serial_number: 'NEWER' },
      suggested_item: { serial_number: 'OLDER' },
    });
  });
});
