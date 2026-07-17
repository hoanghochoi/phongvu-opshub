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
        vatRateBps: 800,
        taxCode: '8',
        taxLabel: 'Thuế 8%',
        taxSource: 'ERP_PPM',
        taxFetchedAt: new Date('2026-07-17T00:00:00.000Z'),
      },
    ]);

    expect(result.items[0].unitPriceBeforeVat).toBe(2_080_469n);
    expect(result.items[0].lineBeforeVat).toBe(4_160_938n);
    expect(result.items[0].lineAfterVat).toBe(4_493_814n);
    expect(result.items[0].lineVatAmount).toBe(332_876n);
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
          vatRateBps: 800,
          taxCode: null,
          taxLabel: null,
          taxSource: 'ERP_PPM',
          taxFetchedAt: new Date(),
        },
      ]),
    ).toThrow('ERP chưa trả finalSellPrice hợp lệ');
  });
});
