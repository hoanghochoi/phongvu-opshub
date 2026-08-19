import { calculateContractAppendix } from './contract-appendix-calculator';

describe('calculateContractAppendix', () => {
  it('derives net unit price from finalSellPrice and preserves ERP gross', () => {
    const result = calculateContractAppendix('SO-1', [
      {
        sourceLineKey: '1:250902982',
        sku: '250902982',
        sellerSku: '250902982',
        productName: 'Tai nghe Apple AirPods Pro 3',
        quantity: 2,
        unit: 'Cái',
        finalSellPrice: 2_246_907,
        erpRowTotal: 4_493_815,
        sourceOrderCodes: ['SO-1'],
        sourceLineIdentities: ['SO-1:line-1'],
        vatRateBps: 800,
        taxCode: '8',
        taxLabel: 'Thuế 8%',
        taxSource: 'ERP_PPM',
        taxFetchedAt: new Date('2026-07-17T00:00:00.000Z'),
      },
    ]);

    expect(result.items[0].unitPriceBeforeVat).toBe(2_080_469n);
    expect(result.items[0].lineBeforeVat).toBe(4_160_938n);
    expect(result.items[0].lineAfterVat).toBe(4_493_815n);
    expect(result.items[0].lineVatAmount).toBe(332_877n);
    expect(result.totalBeforeVat + result.totalVatAmount).toBe(
      result.totalAfterVat,
    );
  });

  it('keeps a zero-tax item unchanged and counts manual tax', () => {
    const result = calculateContractAppendix('SO-2', [
      {
        sourceLineKey: '1:SKU',
        sku: 'SKU',
        sellerSku: null,
        productName: 'Phần mềm',
        quantity: 8,
        unit: 'Bản',
        finalSellPrice: 3_390_000,
        erpRowTotal: 27_120_000,
        sourceOrderCodes: ['SO-2'],
        sourceLineIdentities: ['SO-2:line-1'],
        vatRateBps: 0,
        taxCode: null,
        taxLabel: null,
        taxSource: 'MANUAL',
        taxFetchedAt: null,
      },
    ]);
    expect(result.items[0].unitPriceBeforeVat).toBe(3_390_000n);
    expect(result.totalVatAmount).toBe(0n);
    expect(result.manualTaxItemCount).toBe(1);
  });

  it('reconciles mixed 0% and 8% lines independently', () => {
    const result = calculateContractAppendix('SO-MIXED', [
      {
        sourceLineKey: '1:220909037',
        sku: '220909037',
        sellerSku: '220909037',
        productName: 'Phần mềm Microsoft Win Pro 11 64-bit',
        quantity: 3,
        unit: 'Bản',
        finalSellPrice: 5_190_000,
        erpRowTotal: 15_570_000,
        sourceOrderCodes: ['SO-MIXED'],
        sourceLineIdentities: ['SO-MIXED:line-1'],
        vatRateBps: 0,
        taxCode: 'VAT0',
        taxLabel: 'Thuế 0%',
        taxSource: 'ERP_PPM',
        taxFetchedAt: new Date('2026-07-24T00:00:00.000Z'),
      },
      {
        sourceLineKey: '2:MONITOR',
        sku: 'MONITOR',
        sellerSku: 'MONITOR',
        productName: 'Màn hình',
        quantity: 2,
        unit: 'Cái',
        finalSellPrice: 2_690_000,
        erpRowTotal: 5_380_000,
        sourceOrderCodes: ['SO-MIXED'],
        sourceLineIdentities: ['SO-MIXED:line-2'],
        vatRateBps: 800,
        taxCode: 'VAT8',
        taxLabel: 'Thuế 8%',
        taxSource: 'ERP_PPM',
        taxFetchedAt: new Date('2026-07-24T00:00:00.000Z'),
      },
    ]);

    expect(result.items[0].unitPriceBeforeVat).toBe(5_190_000n);
    expect(result.items[0].lineBeforeVat).toBe(15_570_000n);
    expect(result.items[0].lineAfterVat).toBe(15_570_000n);
    expect(result.items[1].unitPriceBeforeVat).toBe(2_490_741n);
    expect(result.items[1].lineBeforeVat).toBe(4_981_482n);
    expect(result.items[1].lineAfterVat).toBe(5_380_000n);
    expect(result.totalBeforeVat).toBe(20_551_482n);
    expect(result.totalVatAmount).toBe(398_518n);
    expect(result.totalAfterVat).toBe(20_950_000n);
    expect(result.totalBeforeVat + result.totalVatAmount).toBe(
      result.totalAfterVat,
    );
  });

  it('rejects missing finalSellPrice instead of falling back', () => {
    expect(() =>
      calculateContractAppendix('SO-3', [
        {
          sourceLineKey: '1:SKU',
          sku: 'SKU',
          sellerSku: null,
          productName: 'Sản phẩm',
          quantity: 1,
          unit: 'Cái',
          finalSellPrice: Number.NaN,
          erpRowTotal: 1,
          sourceOrderCodes: ['SO-3'],
          sourceLineIdentities: ['SO-3:line-1'],
          vatRateBps: 800,
          taxCode: null,
          taxLabel: null,
          taxSource: 'ERP_PPM',
          taxFetchedAt: new Date(),
        },
      ]),
    ).toThrow('ERP chưa trả finalSellPrice hợp lệ');
  });

  it('uses the ERP row total exactly when unit-price multiplication differs', () => {
    const result = calculateContractAppendix('SO-ROW-TOTAL', [
      {
        sourceLineKey: '1:SKU',
        sku: 'SKU',
        sellerSku: 'SKU',
        productName: 'Sản phẩm',
        quantity: 2,
        unit: 'Cái',
        finalSellPrice: 250,
        erpRowTotal: 499,
        sourceOrderCodes: ['SO-ROW-TOTAL'],
        sourceLineIdentities: ['SO-ROW-TOTAL:line-1'],
        vatRateBps: 800,
        taxCode: 'VAT0',
        taxLabel: 'Thuế 0%',
        taxSource: 'ERP_PPM',
        taxFetchedAt: null,
      },
    ]);

    expect(result.items[0].lineAfterVat).toBe(499n);
    expect(result.items[0].lineVatAmount).toBe(37n);
    expect(result.totalAfterVat).toBe(499n);
  });

  it('fails closed when ERP row total is below the derived pre-tax line', () => {
    expect(() =>
      calculateContractAppendix('SO-4', [
        {
          sourceLineKey: '1:SKU',
          sku: 'SKU',
          sellerSku: null,
          productName: 'Sản phẩm',
          quantity: 2,
          unit: 'Cái',
          finalSellPrice: 250,
          erpRowTotal: 400,
          sourceOrderCodes: ['SO-4'],
          sourceLineIdentities: ['SO-4:line-1'],
          vatRateBps: 0,
          taxCode: null,
          taxLabel: null,
          taxSource: 'MANUAL',
          taxFetchedAt: null,
        },
      ]),
    ).toThrow('Dữ liệu thuế của sản phẩm không hợp lệ');
  });
});
