import { ConflictException, NotFoundException } from '@nestjs/common';
import { ContractAppendicesService } from './contract-appendices.service';

describe('ContractAppendicesService', () => {
  const fetchedAt = new Date('2026-07-17T02:00:00.000Z');
  const order = {
    orderCode: 'SO-250902982',
    fetchedAt,
    items: [
      {
        sku: '250902982',
        sellerSku: '250902982',
        name: 'Tai nghe Apple AirPods Pro 3',
        quantity: 2,
        finalSellPrice: 2_246_907,
        sellPrice: 99,
      },
    ],
  };
  const taxes = {
    terminalCode: '49180_PRICE_0001',
    sellerId: '1',
    requestedSkus: ['250902982'],
    missingSkus: [],
    fetchedAt,
    items: [
      {
        sku: '250902982',
        vatRateBps: 800,
        taxOutAmount: 8,
        taxCode: '8',
        taxLabel: 'Thuế 8%',
        source: 'ERP_PPM',
        fetchedAt,
      },
    ],
  };

  function harness() {
    const prisma = {
      contractAppendix: {
        create: jest.fn(),
        findMany: jest.fn(),
        count: jest.fn(),
        findFirst: jest.fn(),
        deleteMany: jest.fn(),
      },
      $transaction: jest.fn((values: unknown[]) => Promise.all(values)),
    };
    const orderErp = { lookupOrder: jest.fn().mockResolvedValue(order) };
    const productErp = { lookupTaxes: jest.fn().mockResolvedValue(taxes) };
    return {
      prisma,
      orderErp,
      productErp,
      service: new ContractAppendicesService(
        prisma as any,
        orderErp as any,
        productErp as any,
      ),
    };
  }

  it('uses existing ERP order finalSellPrice and PPM tax', async () => {
    const { service, orderErp, productErp } = harness();
    const result = await service.preview(
      { id: 'user-1' },
      { orderCode: ' SO-250902982 ' },
    );
    expect(orderErp.lookupOrder).toHaveBeenCalledWith(' SO-250902982 ');
    expect(productErp.lookupTaxes).toHaveBeenCalledWith(['250902982'], {
      forceRefresh: false,
    });
    expect(result.canSave).toBe(true);
    expect(result.items[0]).toMatchObject({
      sku: '250902982',
      quantity: 2,
      finalSellPrice: 2_246_907,
      unitPriceBeforeVat: 2_080_469,
      lineBeforeVat: 4_160_938,
      lineVatAmount: 332_876,
      lineAfterVat: 4_493_814,
    });
    expect(result.totalBeforeVat + result.totalVatAmount).toBe(
      result.totalAfterVat,
    );
  });

  it('requires an explicit manual tax when PPM has no tax', async () => {
    const { service, productErp } = harness();
    productErp.lookupTaxes.mockResolvedValue({
      ...taxes,
      missingSkus: ['250902982'],
      items: [{ ...taxes.items[0], vatRateBps: null, source: 'MISSING' }],
    });
    const unresolved = await service.preview(
      { id: 'user-1' },
      { orderCode: 'SO-250902982' },
    );
    expect(unresolved.canSave).toBe(false);
    expect(unresolved.unresolvedTaxCount).toBe(1);
    expect(unresolved.totalAfterVat).toBeNull();

    const manual = await service.preview(
      { id: 'user-1' },
      {
        orderCode: 'SO-250902982',
        overrides: [{ sourceLineKey: '1:250902982', manualVatRateBps: 800 }],
      },
    );
    expect(manual.canSave).toBe(true);
    expect(manual.manualTaxItemCount).toBe(1);
    expect(manual.items[0].taxSource).toBe('MANUAL');
  });

  it('force-refreshes tax and persists an immutable creator snapshot', async () => {
    const { service, prisma, productErp } = harness();
    const preview = await service.preview(
      { id: 'user-1' },
      { orderCode: 'SO-250902982' },
    );
    prisma.contractAppendix.create.mockImplementation(({ data }: any) => ({
      id: 'appendix-1',
      ...data,
      items: data.items.create.map((item: any, index: number) => ({
        id: `item-${index}`,
        contractAppendixId: 'appendix-1',
        ...item,
      })),
    }));

    const saved = await service.create(
      { id: 'user-1' },
      { orderCode: 'SO-250902982', quoteVersion: preview.quoteVersion },
    );
    expect(productErp.lookupTaxes).toHaveBeenLastCalledWith(['250902982'], {
      forceRefresh: true,
    });
    const createData = prisma.contractAppendix.create.mock.calls[0][0].data;
    expect(createData.userId).toBe('user-1');
    expect(createData.terminalCode).toBe('49180_PRICE_0001');
    expect(createData.totalAfterVat).toBe(4_493_814n);
    expect(
      createData.expiresAt.getTime() - createData.createdAt.getTime(),
    ).toBe(30 * 24 * 60 * 60 * 1000);
    expect(saved.totalAfterVat).toBe(4_493_814);
  });

  it('rejects save when ERP tax changed after preview', async () => {
    const { service, productErp } = harness();
    const preview = await service.preview(
      { id: 'user-1' },
      { orderCode: 'SO-250902982' },
    );
    productErp.lookupTaxes.mockResolvedValue({
      ...taxes,
      items: [{ ...taxes.items[0], vatRateBps: 1000, taxOutAmount: 10 }],
    });
    await expect(
      service.create(
        { id: 'user-1' },
        { orderCode: 'SO-250902982', quoteVersion: preview.quoteVersion },
      ),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it('uses id, creator and expiry together for history detail', async () => {
    const { service, prisma } = harness();
    prisma.contractAppendix.findFirst.mockResolvedValue(null);
    await expect(
      service.detail({ id: 'user-1' }, 'other-id'),
    ).rejects.toBeInstanceOf(NotFoundException);
    expect(prisma.contractAppendix.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          id: 'other-id',
          userId: 'user-1',
          expiresAt: { gt: expect.any(Date) },
        }),
      }),
    );
  });

  it('cleans expired snapshots idempotently', async () => {
    const { service, prisma } = harness();
    prisma.contractAppendix.deleteMany.mockResolvedValue({ count: 2 });
    await expect(service.cleanupExpired()).resolves.toBe(2);
    expect(prisma.contractAppendix.deleteMany).toHaveBeenCalledWith({
      where: { expiresAt: { lte: expect.any(Date) } },
    });
  });
});
