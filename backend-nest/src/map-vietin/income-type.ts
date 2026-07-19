export const MAP_VIETIN_INCOME_TYPE = {
  SALES: 'SALES',
  PARTNER_INTERNAL: 'PARTNER_INTERNAL',
} as const;

export type MapVietinIncomeType =
  (typeof MAP_VIETIN_INCOME_TYPE)[keyof typeof MAP_VIETIN_INCOME_TYPE];

const PARTNER_INTERNAL_COMPACT_MARKERS = [
  'NHATTIN',
  'VNPAYTT217344',
  'SHOPEEPAYMS',
  'SHOPEEWSSSELLERWITHDRAWAL',
  'GIAOHANGTIETKIEMCHUYENTIENCOD',
  'TTGDQUAVIZALOPAY',
  'DIEUTIENTUDONG',
];

const PARTNER_INTERNAL_PAYER_ACCOUNTS = new Set([
  '8637988888',
  '0302607125',
  '113000179095',
  '110600994666',
  '1011103131001',
  '0071001142275',
  '117601180666',
]);

const PARTNER_INTERNAL_RECONCILIATION_PREFIXES = [
  'BCCN',
  'BCCTY',
  'BCCP',
  'BCDKKD',
];

export function normalizeIncomeTypeContent(value: unknown): string {
  return String(value ?? '')
    .toUpperCase()
    .replace(/\s+/g, '');
}

export function classifyMapVietinIncomeType(
  content: unknown,
  storeCode?: unknown,
  payerAccount?: unknown,
): MapVietinIncomeType {
  const normalized = normalizeIncomeTypeContent(content);
  const normalizedPayerAccount = normalizeIncomeTypeContent(payerAccount);
  if (PARTNER_INTERNAL_PAYER_ACCOUNTS.has(normalizedPayerAccount)) {
    return MAP_VIETIN_INCOME_TYPE.PARTNER_INTERNAL;
  }
  if (!normalized) return MAP_VIETIN_INCOME_TYPE.SALES;
  if (
    PARTNER_INTERNAL_RECONCILIATION_PREFIXES.some((prefix) =>
      normalized.startsWith(prefix),
    )
  ) {
    return MAP_VIETIN_INCOME_TYPE.PARTNER_INTERNAL;
  }
  if (
    PARTNER_INTERNAL_COMPACT_MARKERS.some((marker) =>
      normalized.includes(marker),
    )
  ) {
    return MAP_VIETIN_INCOME_TYPE.PARTNER_INTERNAL;
  }
  const normalizedStoreCode = normalizeIncomeTypeContent(storeCode);
  if (
    normalizedStoreCode &&
    normalized.includes(`TNG${normalizedStoreCode}NOPTIEN`)
  ) {
    return MAP_VIETIN_INCOME_TYPE.PARTNER_INTERNAL;
  }
  return MAP_VIETIN_INCOME_TYPE.SALES;
}

export function mapVietinIncomeTypeLabel(value: unknown): string {
  return String(value ?? '')
    .trim()
    .toUpperCase() === MAP_VIETIN_INCOME_TYPE.PARTNER_INTERNAL
    ? 'Đối tác/Nội bộ'
    : 'Bán hàng';
}
