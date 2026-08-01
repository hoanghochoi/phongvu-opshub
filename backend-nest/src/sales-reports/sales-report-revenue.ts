export const SALES_PRICE_CONTRACT_VERSION = 2;
export const SALES_REVENUE_SOURCE = 'ERP_ORDER_CACHE_GRAND_TOTAL';

export type CanonicalRevenueCacheRow = {
  orderCode: unknown;
  grandTotal: unknown;
};

export type CanonicalRevenueLookup = {
  values: Map<string, number>;
  presentCodes: Set<string>;
  invalidCodes: Set<string>;
};

export function normalizeRevenueOrderCode(value: unknown) {
  const normalized = String(value ?? '')
    .trim()
    .toUpperCase()
    .replace(/\s+/g, '');
  return normalized || null;
}

export function canonicalVatIncludedRevenue(value: unknown) {
  return typeof value === 'number' && Number.isSafeInteger(value) && value > 0
    ? value
    : null;
}

export function buildCanonicalRevenueLookup(
  rows: CanonicalRevenueCacheRow[],
): CanonicalRevenueLookup {
  const values = new Map<string, number>();
  const presentCodes = new Set<string>();
  const invalidCodes = new Set<string>();
  for (const row of rows) {
    const orderCode = normalizeRevenueOrderCode(row.orderCode);
    if (!orderCode) continue;
    presentCodes.add(orderCode);
    const revenue = canonicalVatIncludedRevenue(row.grandTotal);
    if (revenue === null) {
      if (!values.has(orderCode)) invalidCodes.add(orderCode);
      continue;
    }
    values.set(orderCode, revenue);
    invalidCodes.delete(orderCode);
  }
  return { values, presentCodes, invalidCodes };
}

export function canonicalRevenueForOrder(
  lookup: CanonicalRevenueLookup,
  orderCode: unknown,
) {
  const normalized = normalizeRevenueOrderCode(orderCode);
  return normalized ? (lookup.values.get(normalized) ?? 0) : 0;
}
