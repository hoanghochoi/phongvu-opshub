export const ERP_PPM_TERMINAL_CODE = '49180_PRICE_0001';

export type ErpPpmTaxSource = 'ERP_PPM' | 'MISSING';

export type ErpPpmProductTax = {
  sku: string;
  vatRateBps: number | null;
  taxOutAmount: number | null;
  taxCode: string | null;
  taxLabel: string | null;
  source: ErpPpmTaxSource;
  fetchedAt: Date;
};

export type ErpPpmTaxLookupResult = {
  terminalCode: string;
  sellerId: string;
  requestedSkus: string[];
  items: ErpPpmProductTax[];
  missingSkus: string[];
  fetchedAt: Date;
};

export type ErpPpmTaxLookupOptions = {
  forceRefresh?: boolean;
};
