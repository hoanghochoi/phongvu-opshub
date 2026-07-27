import { ConflictException, NotFoundException } from '@nestjs/common';
import { ContractAppendicesService } from './contract-appendices.service';

describe('ContractAppendicesService', () => {
  const fetchedAt = new Date('2026-07-17T02:00:00.000Z');
  const order = {
    orderCode: 'SO-220909037',
    fetchedAt,
    items: [
      {
        sku: '220909037',
        sellerSku: '220909037',
        name: 'Phần mềm Microsoft Win Pro 11 64-bit',
        quantity: 3,
        uomName: 'Bản',
        finalSellPrice: 5_190_000,
        sellPrice: 99,
      },
    ],
  };
  const taxes = {
    terminalCode: '49180_PRICE_0001',
    sellerId: '1',
    requestedSkus: ['220909037'],
    missingSkus: [],
    fetchedAt,
    items: [
      {
        sku: '220909037',
        vatRateBps: 0,
        taxOutAmount: 0,
        taxCode: 'VAT0',
        taxLabel: 'Thuế 0%',
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
    const orderErp = {
      lookupContractAppendixOrder: jest.fn().mockResolvedValue(order),
    };
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

  it('uses shipment-priced ERP order data and PPM tax', async () => {
    const { service, orderErp, productErp } = harness();
    const result = await service.preview(
      { id: 'user-1' },
      { orderCode: ' SO-220909037 ' },
    );
    expect(orderErp.lookupContractAppendixOrder).toHaveBeenCalledWith(
      ' SO-220909037 ',
    );
    expect(productErp.lookupTaxes).toHaveBeenCalledWith(['220909037']);
    expect(result.canSave).toBe(true);
    expect(result.items[0]).toMatchObject({
      sku: '220909037',
      quantity: 3,
      unit: 'Bản',
      finalSellPrice: 5_190_000,
      unitPriceBeforeVat: 5_190_000,
      lineBeforeVat: 15_570_000,
      lineVatAmount: 0,
      lineAfterVat: 15_570_000,
    });
    expect(result.totalBeforeVat + result.totalVatAmount).toBe(
      result.totalAfterVat,
    );
  });

  it('uses an explicit unit override but never invents a missing ERP unit', async () => {
    const { service, orderErp } = harness();
    orderErp.lookupContractAppendixOrder.mockResolvedValue({
      ...order,
      items: [{ ...order.items[0], uomName: null }],
    });

    await expect(
      service.preview({ id: 'user-1' }, { orderCode: 'SO-220909037' }),
    ).rejects.toThrow('ERP chưa trả đơn vị tính');

    const result = await service.preview(
      { id: 'user-1' },
      {
        orderCode: 'SO-220909037',
        overrides: [{ sourceLineKey: '1:220909037', unit: 'Bản' }],
      },
    );
    expect(result.items[0].unit).toBe('Bản');
  });

  it('requires an explicit manual tax when PPM has no tax', async () => {
    const { service, productErp } = harness();
    productErp.lookupTaxes.mockResolvedValue({
      ...taxes,
      missingSkus: ['220909037'],
      items: [{ ...taxes.items[0], vatRateBps: null, source: 'MISSING' }],
    });
    const unresolved = await service.preview(
      { id: 'user-1' },
      { orderCode: 'SO-220909037' },
    );
    expect(unresolved.canSave).toBe(false);
    expect(unresolved.unresolvedTaxCount).toBe(1);
    expect(unresolved.totalAfterVat).toBeNull();

    const manual = await service.preview(
      { id: 'user-1' },
      {
        orderCode: 'SO-220909037',
        overrides: [{ sourceLineKey: '1:220909037', manualVatRateBps: 800 }],
      },
    );
    expect(manual.canSave).toBe(true);
    expect(manual.manualTaxItemCount).toBe(1);
    expect(manual.items[0].taxSource).toBe('MANUAL');
  });

  it('refetches live tax and persists an immutable creator snapshot', async () => {
    const { service, prisma, productErp } = harness();
    const preview = await service.preview(
      { id: 'user-1' },
      { orderCode: 'SO-220909037' },
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
      { orderCode: 'SO-220909037', quoteVersion: preview.quoteVersion },
    );
    expect(productErp.lookupTaxes).toHaveBeenCalledTimes(2);
    expect(productErp.lookupTaxes).toHaveBeenLastCalledWith(['220909037']);
    const createData = prisma.contractAppendix.create.mock.calls[0][0].data;
    expect(createData.userId).toBe('user-1');
    expect(createData.terminalCode).toBe('49180_PRICE_0001');
    expect(createData.items.create[0].unit).toBe('Bản');
    expect(createData.items.create[0].vatRateBps).toBe(0);
    expect(createData.totalAfterVat).toBe(15_570_000n);
    expect(
      createData.expiresAt.getTime() - createData.createdAt.getTime(),
    ).toBe(30 * 24 * 60 * 60 * 1000);
    expect(saved.totalAfterVat).toBe(15_570_000);
  });

  it('rejects save when ERP tax changed after preview', async () => {
    const { service, productErp } = harness();
    const preview = await service.preview(
      { id: 'user-1' },
      { orderCode: 'SO-220909037' },
    );
    productErp.lookupTaxes.mockResolvedValue({
      ...taxes,
      items: [{ ...taxes.items[0], vatRateBps: 1000, taxOutAmount: 10 }],
    });
    await expect(
      service.create(
        { id: 'user-1' },
        { orderCode: 'SO-220909037', quoteVersion: preview.quoteVersion },
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
