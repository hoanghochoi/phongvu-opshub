export const MAP_VIETIN_INCOME_TYPE = {
  SALES: 'SALES',
  PARTNER_INTERNAL: 'PARTNER_INTERNAL',
} as const;

export type MapVietinIncomeType =
  (typeof MAP_VIETIN_INCOME_TYPE)[keyof typeof MAP_VIETIN_INCOME_TYPE];

const PARTNER_INTERNAL_MARKERS = [
  /\bSO GD GOC\b/,
  /\bRECESS\b/,
  /\bVNSHOP\b/,
  /\bSHOPEE(?:PAY)?\b/,
  /\bVNPAY\b/,
  /\bZALOPAY\b/,
  /\bGIAOHANGTIETKIEM\b/,
  /\bNHAT TIN\b/,
  /\bTHEO LO EMB\b/,
  /\bKHDN\b/,
  /\b(?:TT|CHUYEN TIEN) COD\b/,
];

// BC CN25 / BC CP74 / BC CTY ... là mã đối soát nội bộ, không phải mã đơn.
const INTERNAL_RECONCILIATION_MARKER = /^BC\s+(?:CN|CP|CTY|DKKD)[A-Z0-9]*\b/;

export function normalizeIncomeTypeContent(value: unknown): string {
  return String(value ?? '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/Đ/g, 'D')
    .replace(/đ/g, 'd')
    .toUpperCase()
    .replace(/[^A-Z0-9]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

export function classifyMapVietinIncomeType(
  content: unknown,
): MapVietinIncomeType {
  const normalized = normalizeIncomeTypeContent(content);
  if (!normalized) return MAP_VIETIN_INCOME_TYPE.SALES;
  if (INTERNAL_RECONCILIATION_MARKER.test(normalized)) {
    return MAP_VIETIN_INCOME_TYPE.PARTNER_INTERNAL;
  }
  if (PARTNER_INTERNAL_MARKERS.some((marker) => marker.test(normalized))) {
    return MAP_VIETIN_INCOME_TYPE.PARTNER_INTERNAL;
  }
  return MAP_VIETIN_INCOME_TYPE.SALES;
}

export function mapVietinIncomeTypeLabel(value: unknown): string {
  return String(value ?? '').trim().toUpperCase() ===
          MAP_VIETIN_INCOME_TYPE.PARTNER_INTERNAL
      ? 'Đối tác/Nội bộ'
      : 'Bán hàng';
}
