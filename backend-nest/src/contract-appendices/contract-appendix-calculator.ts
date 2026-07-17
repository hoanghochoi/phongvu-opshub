import { BadRequestException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { vietnameseContractAmountWords } from '../common/vietnamese-amount-words';

export type ContractAppendixTaxSource = 'ERP_PPM' | 'MANUAL';

export type ContractAppendixCalculationInput = {
  sourceLineKey: string;
  sku: string;
  sellerSku: string | null;
  productName: string;
  quantity: number;
  unit: string;
  finalSellPrice: number;
  vatRateBps: number;
  taxCode: string | null;
  taxLabel: string | null;
  taxSource: ContractAppendixTaxSource;
  taxFetchedAt: Date | null;
};

export type ContractAppendixCalculatedItem =
  ContractAppendixCalculationInput & {
    position: number;
    unitPriceBeforeVat: bigint;
    lineBeforeVat: bigint;
    lineVatAmount: bigint;
    lineAfterVat: bigint;
  };

export type ContractAppendixCalculation = {
  items: ContractAppendixCalculatedItem[];
  totalBeforeVat: bigint;
  totalVatAmount: bigint;
  totalAfterVat: bigint;
  amountInWords: string;
  manualTaxItemCount: number;
  quoteFingerprint: string;
};

export function calculateContractAppendix(
  orderCode: string,
  items: ContractAppendixCalculationInput[],
): ContractAppendixCalculation {
  if (items.length === 0) {
    throw new BadRequestException('Đơn hàng không có sản phẩm để tạo phụ lục.');
  }
  if (items.length > 200) {
    throw new BadRequestException(
      'Đơn hàng có quá nhiều sản phẩm. Vui lòng liên hệ quản lý để được hỗ trợ.',
    );
  }

  const calculatedItems = items.map((item, index) => {
    assertInput(item);
    const grossUnit = BigInt(item.finalSellPrice);
    const divisor = BigInt(10_000 + item.vatRateBps);
    const unitPriceBeforeVat = roundHalfUp(grossUnit * 10_000n, divisor);
    const quantity = BigInt(item.quantity);
    const lineBeforeVat = unitPriceBeforeVat * quantity;
    const lineAfterVat = grossUnit * quantity;
    const lineVatAmount = lineAfterVat - lineBeforeVat;
    if (lineVatAmount < 0n) {
      throw new BadRequestException('Dữ liệu thuế của sản phẩm không hợp lệ.');
    }
    return {
      ...item,
      position: index + 1,
      unitPriceBeforeVat,
      lineBeforeVat,
      lineVatAmount,
      lineAfterVat,
    };
  });

  const totalBeforeVat = sum(calculatedItems.map((item) => item.lineBeforeVat));
  const totalVatAmount = sum(calculatedItems.map((item) => item.lineVatAmount));
  const totalAfterVat = sum(calculatedItems.map((item) => item.lineAfterVat));
  if (totalBeforeVat + totalVatAmount !== totalAfterVat) {
    throw new Error('Contract appendix totals do not reconcile');
  }
  const totalAsNumber = safeMoneyNumber(totalAfterVat);
  const quoteFingerprint = createHash('sha256')
    .update(
      JSON.stringify({
        orderCode,
        items: calculatedItems.map((item) => ({
          sourceLineKey: item.sourceLineKey,
          sku: item.sku,
          quantity: item.quantity,
          finalSellPrice: item.finalSellPrice,
          vatRateBps: item.vatRateBps,
          taxSource: item.taxSource,
          taxCode: item.taxCode,
          taxLabel: item.taxLabel,
          productName: item.productName,
          unit: item.unit,
        })),
      }),
    )
    .digest('hex');

  return {
    items: calculatedItems,
    totalBeforeVat,
    totalVatAmount,
    totalAfterVat,
    amountInWords: vietnameseContractAmountWords(totalAsNumber),
    manualTaxItemCount: calculatedItems.filter(
      (item) => item.taxSource === 'MANUAL',
    ).length,
    quoteFingerprint,
  };
}

export function safeMoneyNumber(value: bigint): number {
  const result = Number(value);
  if (!Number.isSafeInteger(result) || result < 0) {
    throw new BadRequestException(
      'Giá trị hợp đồng vượt giới hạn hệ thống hỗ trợ.',
    );
  }
  return result;
}

function roundHalfUp(numerator: bigint, denominator: bigint) {
  if (denominator <= 0n || numerator < 0n) {
    throw new Error('roundHalfUp only accepts a positive ratio');
  }
  return (numerator * 2n + denominator) / (denominator * 2n);
}

function sum(values: bigint[]) {
  return values.reduce((total, value) => total + value, 0n);
}

function assertInput(item: ContractAppendixCalculationInput) {
  if (!item.sourceLineKey || !item.sku || !item.productName || !item.unit) {
    throw new BadRequestException('Thông tin sản phẩm chưa đầy đủ.');
  }
  if (!Number.isInteger(item.quantity) || item.quantity <= 0) {
    throw new BadRequestException('Số lượng sản phẩm không hợp lệ.');
  }
  if (!Number.isSafeInteger(item.finalSellPrice) || item.finalSellPrice < 0) {
    throw new BadRequestException(
      'ERP chưa trả finalSellPrice hợp lệ cho sản phẩm.',
    );
  }
  if (
    !Number.isInteger(item.vatRateBps) ||
    item.vatRateBps < 0 ||
    item.vatRateBps > 10_000
  ) {
    throw new BadRequestException('Thuế GTGT của sản phẩm không hợp lệ.');
  }
}
