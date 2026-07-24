import {
  BadRequestException,
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import { SalesReportErpService } from '../sales-reports/sales-report-erp.service';
import {
  ERP_PPM_TERMINAL_CODE,
  ErpPpmProductTax,
  ErpPpmTaxLookupResult,
} from './erp.types';

const PPM_BATCH_SIZE = 50;
const PPM_MAX_SKUS = 500;

@Injectable()
export class ErpPpmProductService {
  private readonly logger = new Logger(ErpPpmProductService.name);

  constructor(private readonly erp: SalesReportErpService) {}

  async lookupTaxes(skuInputs: string[]): Promise<ErpPpmTaxLookupResult> {
    const requestedSkus = this.normalizeSkus(skuInputs);
    const terminalCode = this.env(
      'ERP_PPM_TERMINAL_CODE',
      ERP_PPM_TERMINAL_CODE,
    );
    const sellerId = this.env('ERP_PPM_SELLER_ID', '1');
    const startedAt = Date.now();
    const fetchedAt = new Date();

    if (requestedSkus.length === 0) {
      return {
        terminalCode,
        sellerId,
        requestedSkus,
        items: [],
        missingSkus: [],
        fetchedAt,
      };
    }

    const resolved = new Map<string, ErpPpmProductTax>();
    const batches = this.chunks(requestedSkus, PPM_BATCH_SIZE);
    this.logger.log(
      `ERP PPM tax lookup started: skuCount=${requestedSkus.length} batchCount=${batches.length} cacheMode=disabled`,
    );
    try {
      for (const batch of batches) {
        const batchItems = await this.fetchBatch(batch, terminalCode, sellerId);
        for (const item of batchItems) {
          resolved.set(item.sku, item);
        }
      }

      const items = requestedSkus.map(
        (sku) =>
          resolved.get(sku) ?? {
            sku,
            vatRateBps: null,
            taxOutAmount: null,
            taxCode: null,
            taxLabel: null,
            source: 'MISSING' as const,
            fetchedAt,
          },
      );
      const missingSkus = items
        .filter((item) => item.source === 'MISSING')
        .map((item) => item.sku);
      this.logger.log(
        `ERP PPM tax lookup succeeded: skuCount=${items.length} missingCount=${missingSkus.length} batchCount=${batches.length} durationMs=${Date.now() - startedAt}`,
      );
      return {
        terminalCode,
        sellerId,
        requestedSkus,
        items,
        missingSkus,
        fetchedAt,
      };
    } catch (error) {
      this.logger.error(
        `ERP PPM tax lookup failed: skuCount=${requestedSkus.length} batchCount=${batches.length} durationMs=${Date.now() - startedAt} errorType=${this.errorType(error)}`,
      );
      if (error instanceof ServiceUnavailableException) throw error;
      throw new ServiceUnavailableException(
        'Chưa lấy được thuế sản phẩm từ ERP. Vui lòng thử lại sau ít phút.',
      );
    }
  }

  private async fetchBatch(
    skus: string[],
    terminalCode: string,
    sellerId: string,
  ): Promise<ErpPpmProductTax[]> {
    if (skus.length === 0) return [];
    const baseUrl = this.env(
      'ERP_PPM_BASE_URL',
      'https://ppm.tekoapis.com/api',
    ).replace(/\/$/, '');
    const response = await this.erp.authorizedRequest(`${baseUrl}/products`, {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
        'X-Seller-Id': sellerId,
      },
      body: JSON.stringify({
        skus,
        terminalCode,
        _page: 1,
        _limit: skus.length,
        _sort: 'sku',
        _order: 'ascend',
        getExtraData: ['price', 'tax_out'],
      }),
    });
    if (!response.ok) {
      this.logger.warn(
        `ERP PPM products endpoint failed: status=${response.status} skuCount=${skus.length}`,
      );
      throw new ServiceUnavailableException(
        'Chưa lấy được thuế sản phẩm từ ERP. Vui lòng thử lại sau ít phút.',
      );
    }

    const body = (await response.json().catch(() => null)) as any;
    const payload = body?.result ?? body?.data?.result ?? body?.data ?? body;
    const rows = Array.isArray(payload?.results)
      ? payload.results
      : Array.isArray(payload?.products)
        ? payload.products
        : [];
    const totalItems = this.optionalNumber(
      payload?.totalItems ?? payload?.total,
    );
    if (totalItems !== null && totalItems > rows.length) {
      this.logger.warn(
        `ERP PPM products response truncated: requestedCount=${skus.length} returnedCount=${rows.length} totalItems=${totalItems}`,
      );
      throw new ServiceUnavailableException(
        'ERP trả thiếu dữ liệu thuế sản phẩm. Vui lòng thử lại.',
      );
    }

    const requested = new Set(skus);
    const bySku = new Map<string, ErpPpmProductTax>();
    const now = new Date();
    for (const row of rows) {
      const sku = this.firstText(row?.sku, row?.productSku, row?.product?.sku);
      if (!sku || !requested.has(sku)) continue;
      const item = this.normalizeTax(row, sku, now);
      const existing = bySku.get(sku);
      if (existing && !this.sameTax(existing, item)) {
        this.logger.warn(
          `ERP PPM products returned conflicting tax rows: skuLength=${sku.length}`,
        );
        throw new ServiceUnavailableException(
          'ERP trả dữ liệu thuế chưa nhất quán. Vui lòng thử lại.',
        );
      }
      bySku.set(sku, item);
    }

    return skus.map(
      (sku) =>
        bySku.get(sku) ?? {
          sku,
          vatRateBps: null,
          taxOutAmount: null,
          taxCode: null,
          taxLabel: null,
          source: 'MISSING' as const,
          fetchedAt: now,
        },
    );
  }

  private normalizeTax(
    row: any,
    sku: string,
    fetchedAt: Date,
  ): ErpPpmProductTax {
    const taxOutAmount = this.taxPercent(
      row?.taxOutAmount ??
        row?.tax_out_amount ??
        row?.taxOut?.amount ??
        row?.tax_out?.amount ??
        row?.extraData?.taxOutAmount,
    );
    const taxCode = this.firstText(
      row?.taxOutCode,
      row?.taxCode,
      row?.taxOut?.code,
      row?.tax_out?.code,
    );
    const taxLabel = this.firstText(
      row?.taxOutLabel,
      row?.taxLabel,
      row?.taxName,
      row?.taxOut?.label,
      row?.taxOut?.name,
      row?.tax_out?.label,
      row?.tax_out?.name,
    );
    const normalizedTaxAmount =
      taxOutAmount ?? (this.isKnownNonTaxable(taxCode, taxLabel) ? 0 : null);
    return {
      sku,
      vatRateBps:
        normalizedTaxAmount === null
          ? null
          : Math.round(normalizedTaxAmount * 100),
      taxOutAmount: normalizedTaxAmount,
      taxCode,
      taxLabel,
      source: normalizedTaxAmount === null ? 'MISSING' : 'ERP_PPM',
      fetchedAt,
    };
  }

  private isKnownNonTaxable(taxCode: string | null, taxLabel: string | null) {
    const value = `${taxCode ?? ''} ${taxLabel ?? ''}`
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .toUpperCase();
    return (
      /(^|[^A-Z0-9])KCT([^A-Z0-9]|$)/.test(value) ||
      value.includes('KHONG CHIU THUE') ||
      value.includes('NOT TAXABLE') ||
      value.includes('NON TAXABLE')
    );
  }

  private normalizeSkus(values: string[]) {
    if (!Array.isArray(values)) {
      throw new BadRequestException('Danh sách SKU không hợp lệ.');
    }
    const result: string[] = [];
    const seen = new Set<string>();
    for (const value of values) {
      const sku = String(value ?? '').trim();
      if (!sku) continue;
      if (sku.length > 100) {
        throw new BadRequestException('SKU sản phẩm không hợp lệ.');
      }
      if (!seen.has(sku)) {
        seen.add(sku);
        result.push(sku);
      }
    }
    if (result.length > PPM_MAX_SKUS) {
      throw new BadRequestException(
        `Mỗi lần chỉ tra tối đa ${PPM_MAX_SKUS} SKU.`,
      );
    }
    return result;
  }

  private sameTax(left: ErpPpmProductTax, right: ErpPpmProductTax) {
    return (
      left.vatRateBps === right.vatRateBps &&
      left.taxCode === right.taxCode &&
      left.taxLabel === right.taxLabel
    );
  }

  private taxPercent(value: unknown) {
    if (value === null || value === undefined || value === '') return null;
    const normalized =
      typeof value === 'string'
        ? value.trim().replace(/%$/, '').replace(',', '.')
        : value;
    if (normalized === '') return null;
    const number = Number(normalized);
    if (!Number.isFinite(number) || number < 0 || number > 100) return null;
    return Math.round(number * 100) / 100;
  }

  private optionalNumber(value: unknown) {
    if (value === null || value === undefined || value === '') return null;
    const number = Number(value);
    return Number.isFinite(number) ? number : null;
  }

  private firstText(...values: unknown[]) {
    for (const value of values) {
      const text = String(value ?? '').trim();
      if (text) return text.slice(0, 500);
    }
    return null;
  }

  private chunks(values: string[], size: number) {
    const result: string[][] = [];
    for (let index = 0; index < values.length; index += size) {
      result.push(values.slice(index, index + size));
    }
    return result;
  }

  private env(key: string, fallback: string) {
    return process.env[key]?.trim() || fallback;
  }

  private errorType(error: unknown) {
    return error instanceof Error ? error.name : typeof error;
  }
}
