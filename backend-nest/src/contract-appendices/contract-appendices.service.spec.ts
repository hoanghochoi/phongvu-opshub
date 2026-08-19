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
        rowTotal: 15_570_000,
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
      'SO-220909037',
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

  it('uses shipment rowTotal instead of multiplying the gross price', async () => {
    const { service, orderErp, productErp } = harness();
    productErp.lookupTaxes.mockResolvedValue({
      ...taxes,
      items: [
        {
          ...taxes.items[0],
          vatRateBps: 800,
          taxCode: 'VAT8',
          taxLabel: 'Thuế 8%',
        },
      ],
    });
    orderErp.lookupContractAppendixOrder.mockResolvedValue({
      ...order,
      items: [
        {
          ...order.items[0],
          quantity: 2,
          finalSellPrice: 250,
          rowTotal: 499,
        },
      ],
    });

    const result = await service.preview(
      { id: 'user-1' },
      { orderCodes: ['SO-ROW-TOTAL'] },
    );

    expect(result.items[0]).toMatchObject({
      finalSellPrice: 250,
      quantity: 2,
      lineAfterVat: 499,
    });
    expect(result.totalAfterVat).toBe(499);
  });

  it('looks up multiple orders atomically, keeps order, and groups compatible lines', async () => {
    const { service, orderErp, productErp } = harness();
    productErp.lookupTaxes.mockResolvedValue({
      ...taxes,
      items: [
        {
          ...taxes.items[0],
          vatRateBps: 800,
          taxCode: 'VAT8',
          taxLabel: 'Thuế 8%',
        },
      ],
    });
    orderErp.lookupContractAppendixOrder.mockImplementation(
      async (orderCode: string) => ({
        ...order,
        orderCode,
        items: [
          {
            ...order.items[0],
            sku: 'SKU-GROUP',
            sellerSku: 'SKU-GROUP',
            quantity: orderCode === 'SO-1' ? 2 : 3,
            finalSellPrice: 250,
            rowTotal: orderCode === 'SO-1' ? 499 : 750,
            uomName: 'Cái',
            name: orderCode === 'SO-1' ? 'Tên đầu tiên' : 'Tên khác',
          },
        ],
      }),
    );

    const result = await service.preview(
      { id: 'user-1' },
      { orderCodes: ['so-1', 'SO-2'] },
    );

    expect(orderErp.lookupContractAppendixOrder.mock.calls.map(([code]) => code))
      .toEqual(expect.arrayContaining(['SO-1', 'SO-2']));
    expect(result.orderCodes).toEqual(['SO-1', 'SO-2']);
    expect(result.sourceOrders.map((source: any) => source.orderCode)).toEqual([
      'SO-1',
      'SO-2',
    ]);
    expect(result.items).toHaveLength(1);
    expect(result.items[0]).toMatchObject({
      sku: 'SKU-GROUP',
      quantity: 5,
      erpRowTotal: 1_249,
      lineAfterVat: 1_249,
      sourceOrderCodes: ['SO-1', 'SO-2'],
    });
    expect(result.items[0].sourceLineIdentities).toHaveLength(2);
    expect(productErp.lookupTaxes).toHaveBeenCalledWith(['SKU-GROUP']);
  });

  it('fails the whole preview with the first failed order and no partial table', async () => {
    const { service, orderErp } = harness();
    orderErp.lookupContractAppendixOrder.mockImplementation(async (code: string) => {
      if (code === 'SO-2') throw new Error('ERP down');
      return order;
    });

    await expect(
      service.preview({ id: 'user-1' }, { orderCodes: ['SO-1', 'SO-2'] }),
    ).rejects.toThrow('SO-2');
  });

  it('applies one grouped-line override to every constituent source identity', async () => {
    const { service, orderErp, productErp } = harness();
    productErp.lookupTaxes.mockResolvedValue({
      ...taxes,
      items: [
        {
          ...taxes.items[0],
          sku: 'SKU-GROUP',
          vatRateBps: 800,
          taxCode: 'VAT8',
          taxLabel: 'Thuế 8%',
        },
      ],
    });
    orderErp.lookupContractAppendixOrder.mockImplementation(
      async (orderCode: string) => ({
        ...order,
        orderCode,
        items: [
          {
            ...order.items[0],
            sku: 'SKU-GROUP',
            sellerSku: 'SKU-GROUP',
            quantity: 1,
            finalSellPrice: 250,
            rowTotal: 250,
            uomName: 'Cái',
          },
        ],
      }),
    );

    const first = await service.preview(
      { id: 'user-1' },
      { orderCodes: ['SO-1', 'SO-2'] },
    );
    const grouped = first.items[0];
    const refreshed = await service.preview(
      { id: 'user-1' },
      {
        orderCodes: ['SO-1', 'SO-2'],
        overrides: [
          {
            sourceLineKey: grouped.sourceLineKey,
            sourceLineIdentities: grouped.sourceLineIdentities,
            productName: 'Tên đã sửa',
            unit: 'Bộ',
          },
        ],
      },
    );

    expect(refreshed.items).toHaveLength(1);
    expect(refreshed.items[0]).toMatchObject({
      productName: 'Tên đã sửa',
      unit: 'Bộ',
      quantity: 2,
      erpRowTotal: 500,
    });
  });

  it('rejects duplicate, incompatible, and oversized order selections before ERP lookup', async () => {
    const { service, orderErp } = harness();

    await expect(
      service.preview({ id: 'user-1' }, { orderCodes: ['so-1', 'SO-1'] }),
    ).rejects.toThrow('bị trùng');
    await expect(
      service.preview(
        { id: 'user-1' },
        { orderCode: 'SO-1', orderCodes: ['SO-1', 'SO-2'] },
      ),
    ).rejects.toThrow('không khớp');
    await expect(
      service.preview(
        { id: 'user-1' },
        { orderCodes: Array.from({ length: 11 }, (_, index) => `SO-${index}`) },
      ),
    ).rejects.toThrow('tối đa 10');
    expect(orderErp.lookupContractAppendixOrder).not.toHaveBeenCalled();
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
    expect(unresolved.totalAfterVat).toBe(15_570_000);
    expect(unresolved.amountInWords).toBeTruthy();

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
