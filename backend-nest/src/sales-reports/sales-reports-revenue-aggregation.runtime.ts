import {
  canonicalRevenueForOrder,
  CanonicalRevenueLookup,
  normalizeRevenueOrderCode,
} from './sales-report-revenue';

const REPORT_TYPE_PURCHASED = 'PURCHASED';
const INSTALLMENT_SUCCESS = 'SUCCESS';
const INSTALLMENT_FAILED = 'FAILED';

export type SalesReportsRevenueAggregationCallbacks = {
  cleanPromotionCodes(value: unknown): string[];
  installmentNoInstallmentReasonLabel(code: string): string;
  normalizeSalesCategoryType(value: unknown): string;
};

export type SalesReportsRevenueAggregationSummary = {
  orderCountUnique: number;
  businessRevenue: number;
  personalRevenue: number;
  noInstallmentReasons: Map<string, number>;
  installmentNeedTotalCount: number;
  examScorePromotionCount: number;
  studentPromotionCount: number;
  successfulInstallmentOrderCount: number;
  laptopQuantity: number;
  pcQuantity: number;
  assembledPcQuantity: number;
  appleQuantity: number;
  monitorQuantity: number;
  printerQuantity: number;
  accessoriesQuantity: number;
  extendedInsuranceQuantity: number;
};

/**
 * Owns pure Sales Reports revenue/order aggregation. SalesReportsService keeps
 * the stable facade method used by Home Summary and export orchestration.
 */
export class SalesReportsRevenueAggregationRuntime {
  constructor(
    private readonly callbacks: SalesReportsRevenueAggregationCallbacks,
  ) {}

  summarize(
    rows: any[],
    canonicalRevenue: CanonicalRevenueLookup,
  ): SalesReportsRevenueAggregationSummary {
    const uniquePurchased = new Map<string, any>();
    const noInstallmentReasons = new Map<string, number>();
    const successfulInstallmentOrderKeys = new Set<string>();
    let installmentNeedTotalCount = 0;
    let examScorePromotionCount = 0;
    let studentPromotionCount = 0;

    for (const row of rows) {
      const hasInstallmentNeed = row.installmentNeed === true;
      if (hasInstallmentNeed) installmentNeedTotalCount += 1;

      if (hasInstallmentNeed && row.installmentNoInstallmentReason) {
        const reasonCode = String(row.installmentNoInstallmentReason);
        if (reasonCode !== 'NORMAL_INSTALLMENT') {
          const label =
            this.callbacks.installmentNoInstallmentReasonLabel(reasonCode);
          noInstallmentReasons.set(
            label,
            (noInstallmentReasons.get(label) ?? 0) + 1,
          );
        }
      }

      if (row.reportType !== REPORT_TYPE_PURCHASED) continue;
      const promotionCodes = this.callbacks.cleanPromotionCodes(
        row.promotionCodes,
      );
      if (promotionCodes.includes('EXAM_SCORE_EXCHANGE')) {
        examScorePromotionCount += 1;
      }
      if (promotionCodes.includes('STUDENT')) studentPromotionCount += 1;

      const key =
        normalizeRevenueOrderCode(row.orderCode) ??
        String(row.erpOrderId ?? row.id ?? '').trim();
      if (hasInstallmentNeed && key && this.isReportedInstallmentSuccess(row)) {
        successfulInstallmentOrderKeys.add(key);
      }
      if (key && !uniquePurchased.has(key)) uniquePurchased.set(key, row);
    }

    const summary: SalesReportsRevenueAggregationSummary = {
      orderCountUnique: uniquePurchased.size,
      businessRevenue: 0,
      personalRevenue: 0,
      noInstallmentReasons,
      installmentNeedTotalCount,
      examScorePromotionCount,
      studentPromotionCount,
      successfulInstallmentOrderCount: successfulInstallmentOrderKeys.size,
      laptopQuantity: 0,
      pcQuantity: 0,
      assembledPcQuantity: 0,
      appleQuantity: 0,
      monitorQuantity: 0,
      printerQuantity: 0,
      accessoriesQuantity: 0,
      extendedInsuranceQuantity: 0,
    };

    for (const row of uniquePurchased.values()) {
      const revenue = canonicalRevenueForOrder(canonicalRevenue, row.orderCode);
      if (row.customerType === 'BUSINESS') {
        summary.businessRevenue += revenue;
      } else {
        summary.personalRevenue += revenue;
      }

      const componentQuantities = new Map<string, number>();
      for (const item of Array.isArray(row.items) ? row.items : []) {
        const type = this.callbacks.normalizeSalesCategoryType(
          item?.categoryType,
        );
        if (!type) continue;
        const quantity = this.salesItemQuantity(item);
        componentQuantities.set(
          type,
          (componentQuantities.get(type) ?? 0) + quantity,
        );
        if (type === 'laptop') summary.laptopQuantity += quantity;
        if (type === 'pc') summary.pcQuantity += quantity;
        if (type === 'apple' && this.isTargetAppleItem(item)) {
          summary.appleQuantity += quantity;
        }
        if (type === 'monitor') summary.monitorQuantity += quantity;
        if (type === 'printer') summary.printerQuantity += quantity;
        if (type === 'accessories') summary.accessoriesQuantity += quantity;
        if (type === 'extendedinsurance') {
          summary.extendedInsuranceQuantity += quantity;
        }
      }
      summary.assembledPcQuantity +=
        this.assembledPcQuantity(componentQuantities);
    }

    return summary;
  }

  private assembledPcQuantity(componentQuantities: Map<string, number>) {
    const requiredTypes = [
      'cpu',
      'mainboard',
      'memory',
      'storage',
      'case',
      'psu',
    ];
    const quantities = requiredTypes.map(
      (type) => componentQuantities.get(type) ?? 0,
    );
    const minQuantity = Math.min(...quantities);
    return Number.isFinite(minQuantity) && minQuantity > 0 ? minQuantity : 0;
  }

  private salesItemQuantity(item: any) {
    const quantity = this.numberValue(item?.quantity);
    return quantity !== null && quantity > 0 ? quantity : 1;
  }

  private isTargetAppleItem(item: any) {
    const text = this.normalizeComparable(
      [item?.name, item?.productTypeName, item?.productGroupName]
        .filter(Boolean)
        .join(' '),
    );
    return ['macbook', 'iphone', 'ipad'].some((keyword) =>
      text.includes(keyword),
    );
  }

  private isReportedInstallmentSuccess(row: any) {
    const status = String(row?.installmentStatus || '')
      .trim()
      .toUpperCase();
    if (status === INSTALLMENT_SUCCESS) return true;
    if (status === INSTALLMENT_FAILED) return false;
    return (
      String(row?.installmentNoInstallmentReason || '')
        .trim()
        .toUpperCase() === 'NORMAL_INSTALLMENT'
    );
  }

  private numberValue(value: unknown) {
    if (value === undefined || value === null || value === '') return null;
    const number =
      typeof value === 'string'
        ? Number(value.replace(/,/g, ''))
        : Number(value);
    return Number.isFinite(number) ? Math.trunc(number) : null;
  }

  private normalizeComparable(value: unknown) {
    return String(value || '')
      .trim()
      .toLowerCase()
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/[^a-z0-9]+/g, ' ')
      .trim();
  }
}
