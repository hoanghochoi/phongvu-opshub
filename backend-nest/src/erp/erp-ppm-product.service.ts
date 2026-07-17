import {
  BadRequestException,
  Injectable,
  Logger,
  Optional,
  ServiceUnavailableException,
} from '@nestjs/common';
import { createHash } from 'node:crypto';
import { RedisService } from '../redis/redis.service';
import { SalesReportErpService } from '../sales-reports/sales-report-erp.service';
import {
  ERP_PPM_TERMINAL_CODE,
  ErpPpmProductTax,
  ErpPpmTaxLookupOptions,
  ErpPpmTaxLookupResult,
} from './erp.types';

type CachedTax = {
  value: ErpPpmProductTax;
  expiresAt: number;
};

const PPM_BATCH_SIZE = 50;
const PPM_MAX_SKUS = 500;
const DEFAULT_CACHE_TTL_MS = 5 * 60 * 1000;
const MISSING_CACHE_TTL_MS = 30 * 1000;

@Injectable()
export class ErpPpmProductService {
  private readonly logger = new Logger(ErpPpmProductService.name);
  private readonly cache = new Map<string, CachedTax>();

  constructor(
    private readonly erp: SalesReportErpService,
    @Optional() private readonly redis?: RedisService,
  ) {}

  async lookupTaxes(
    skuInputs: string[],
    options: ErpPpmTaxLookupOptions = {},
  ): Promise<ErpPpmTaxLookupResult> {
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
    const pending: string[] = [];
    if (!options.forceRefresh) {
      const cachedItems = await Promise.all(
        requestedSkus.map((sku) =>
          this.readCachedTax(sellerId, terminalCode, sku),
        ),
      );
      for (let index = 0; index < requestedSkus.length; index += 1) {
        const sku = requestedSkus[index];
        const cached = cachedItems[index];
        if (cached) resolved.set(sku, cached);
        else pending.push(sku);
      }
    } else {
      pending.push(...requestedSkus);
    }

    const batches = this.chunks(pending, PPM_BATCH_SIZE);
    this.logger.log(
      `ERP PPM tax lookup started: skuCount=${requestedSkus.length} cachedCount=${resolved.size} batchCount=${batches.length} forceRefresh=${Boolean(options.forceRefresh)}`,
    );
    try {
      for (const batch of batches) {
        const batchItems = await this.fetchBatch(batch, terminalCode, sellerId);
        for (const item of batchItems) {
          resolved.set(item.sku, item);
        }
        await Promise.all(
          batchItems.map((item) =>
            this.writeCachedTax(sellerId, terminalCode, item),
          ),
        );
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

  private cacheKey(sellerId: string, terminalCode: string, sku: string) {
    const digest = createHash('sha256')
      .update(`${sellerId}:${terminalCode}:${sku}`)
      .digest('hex');
    return `contract-appendix:ppm-tax:v1:${digest}`;
  }

  private async readCachedTax(
    sellerId: string,
    terminalCode: string,
    sku: string,
  ) {
    const key = this.cacheKey(sellerId, terminalCode, sku);
    const memory = this.cache.get(key);
    if (memory && memory.expiresAt > Date.now()) return memory.value;
    if (!this.redis) return null;
    try {
      const cached = await this.redis.getJson<Record<string, unknown>>(key);
      const parsed = this.parseCachedTax(cached, sku);
      if (!parsed) return null;
      const expiresAt = parsed.fetchedAt.getTime() + this.cacheTtlMsFor(parsed);
      if (expiresAt <= Date.now()) return null;
      this.cache.set(key, {
        value: parsed,
        expiresAt,
      });
      return parsed;
    } catch (error) {
      this.logger.warn(
        `ERP PPM Redis cache read skipped: errorType=${this.errorType(error)}`,
      );
      return null;
    }
  }

  private async writeCachedTax(
    sellerId: string,
    terminalCode: string,
    item: ErpPpmProductTax,
  ) {
    const ttlMs = this.cacheTtlMsFor(item);
    if (ttlMs <= 0) return;
    const key = this.cacheKey(sellerId, terminalCode, item.sku);
    this.cache.set(key, { value: item, expiresAt: Date.now() + ttlMs });
    if (!this.redis) return;
    try {
      await this.redis.setJsonWithTtl(
        key,
        { ...item, fetchedAt: item.fetchedAt.toISOString() },
        Math.max(1, Math.floor(ttlMs / 1000)),
      );
    } catch (error) {
      this.logger.warn(
        `ERP PPM Redis cache write skipped: errorType=${this.errorType(error)}`,
      );
    }
  }

  private parseCachedTax(value: unknown, expectedSku: string) {
    if (!value || typeof value !== 'object') return null;
    const row = value as Record<string, unknown>;
    if (String(row.sku ?? '') !== expectedSku) return null;
    const vatRateBps = this.optionalNumber(row.vatRateBps);
    const taxOutAmount = this.optionalNumber(row.taxOutAmount);
    const source = row.source === 'ERP_PPM' ? 'ERP_PPM' : 'MISSING';
    if (
      (vatRateBps !== null &&
        (!Number.isInteger(vatRateBps) ||
          vatRateBps < 0 ||
          vatRateBps > 10_000)) ||
      (taxOutAmount !== null && (taxOutAmount < 0 || taxOutAmount > 100)) ||
      (source === 'ERP_PPM' && (vatRateBps === null || taxOutAmount === null))
    ) {
      return null;
    }
    const fetchedAt = new Date(String(row.fetchedAt ?? ''));
    if (Number.isNaN(fetchedAt.getTime())) return null;
    return {
      sku: expectedSku,
      vatRateBps,
      taxOutAmount,
      taxCode: this.firstText(row.taxCode),
      taxLabel: this.firstText(row.taxLabel),
      source,
      fetchedAt,
    } satisfies ErpPpmProductTax;
  }

  private cacheTtlMs() {
    const configured = Number(process.env.ERP_PPM_CACHE_TTL_MS);
    if (!Number.isFinite(configured) || configured < 0) {
      return DEFAULT_CACHE_TTL_MS;
    }
    return Math.min(configured, DEFAULT_CACHE_TTL_MS);
  }

  private cacheTtlMsFor(item: ErpPpmProductTax) {
    return item.source === 'MISSING'
      ? Math.min(this.cacheTtlMs(), MISSING_CACHE_TTL_MS)
      : this.cacheTtlMs();
  }

  private env(key: string, fallback: string) {
    return process.env[key]?.trim() || fallback;
  }

  private errorType(error: unknown) {
    return error instanceof Error ? error.name : typeof error;
  }
}
