import {
  BadRequestException,
  ConflictException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { createHash } from 'node:crypto';
import { logFingerprint, safeLogError } from '../common/log-sanitizer';
import {
  ErpPpmProductService,
  ERP_PPM_TERMINAL_CODE,
  type ErpPpmProductTax,
} from '../erp';
import { PrismaService } from '../prisma/prisma.service';
import {
  SalesReportErpService,
  type SalesReportErpOrder,
  type SalesReportErpOrderItem,
} from '../sales-reports/sales-report-erp.service';
import {
  calculateContractAppendix,
  safeMoneyNumber,
  type ContractAppendixCalculationInput,
} from './contract-appendix-calculator';
import { vietnameseContractAmountWords } from '../common/vietnamese-amount-words';
import {
  type ContractAppendixLineOverrideDto,
  type CreateContractAppendixDto,
  type ListContractAppendicesDto,
  MANUAL_VAT_RATE_BPS,
  type PreviewContractAppendixDto,
} from './contract-appendices.dto';

const RETENTION_MS = 30 * 24 * 60 * 60 * 1000;

type PreparedLine = {
  sourceLineKey: string;
  sourceOrderCodes: string[];
  sourceLineIdentities: string[];
  sku: string;
  sellerSku: string | null;
  productName: string;
  quantity: number;
  unit: string;
  finalSellPrice: number;
  erpRowTotal: number;
  vatRateBps: number | null;
  taxCode: string | null;
  taxLabel: string | null;
  taxSource: 'ERP_PPM' | 'MANUAL' | 'MISSING';
  taxFetchedAt: Date | null;
};

type PreparedOrder = {
  orderCode: string;
  fetchedAt: Date;
  items: SalesReportErpOrderItem[];
};

class ContractAppendixOrderLookupException extends BadRequestException {
  constructor(public readonly orderCode: string) {
    super(`Không lấy được thông tin đơn hàng ${orderCode}. Vui lòng kiểm tra mã đơn rồi thử lại.`);
  }
}

@Injectable()
export class ContractAppendicesService {
  private readonly logger = new Logger(ContractAppendicesService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly orderErp: SalesReportErpService,
    private readonly productErp: ErpPpmProductService,
  ) {}

  async preview(user: any, dto: PreviewContractAppendixDto) {
    const startedAt = Date.now();
    const userId = this.requireUserId(user);
    const orderCodes = this.resolveOrderCodes(dto);
    this.logger.log(
      `Contract appendix preview started: user=${logFingerprint(userId)} orderCount=${orderCodes.length} overrideCount=${dto.overrides?.length ?? 0}`,
    );
    try {
      const result = await this.buildPreview(dto);
      this.logger.log(
        `Contract appendix preview succeeded: user=${logFingerprint(userId)} orderCount=${result.orderCodes.length} itemCount=${result.items.length} unresolvedTaxCount=${result.unresolvedTaxCount} manualTaxItemCount=${result.manualTaxItemCount} durationMs=${Date.now() - startedAt}`,
      );
      return result;
    } catch (error) {
      this.logger.error(
        `Contract appendix preview failed: user=${logFingerprint(userId)} orderCount=${orderCodes.length} durationMs=${Date.now() - startedAt} errorType=${this.errorType(error)}`,
      );
      throw error;
    }
  }

  async create(user: any, dto: CreateContractAppendixDto) {
    const startedAt = Date.now();
    const userId = this.requireUserId(user);
    const orderCodes = this.resolveOrderCodes(dto);
    this.logger.log(
      `Contract appendix create started: user=${logFingerprint(userId)} orderCount=${orderCodes.length} overrideCount=${dto.overrides?.length ?? 0}`,
    );
    try {
      const preview = await this.buildPreview(dto);
      if (preview.quoteVersion !== dto.quoteVersion) {
        throw new ConflictException(
          'Giá hoặc thuế vừa thay đổi. Vui lòng xem lại bảng mới.',
        );
      }
      if (!preview.canSave || preview.unresolvedTaxCount > 0) {
        throw new BadRequestException(
          `Chưa xác định được thuế cho ${preview.unresolvedTaxCount} sản phẩm. Vui lòng chọn thuế trước khi lưu.`,
        );
      }
      if (
        preview.totalBeforeVat === null ||
        preview.totalVatAmount === null ||
        preview.totalAfterVat === null ||
        preview.amountInWords === null
      ) {
        throw new BadRequestException(
          'Bảng phụ lục chưa đủ dữ liệu để lưu. Vui lòng xem lại.',
        );
      }

      const now = new Date();
      const expiresAt = new Date(now.getTime() + RETENTION_MS);
      const saved = await this.prisma.contractAppendix.create({
        data: {
          userId,
          orderCode: preview.orderCode,
          orderCodes: preview.orderCodes,
          terminalCode: preview.terminalCode,
          totalBeforeVat: BigInt(preview.totalBeforeVat),
          totalVatAmount: BigInt(preview.totalVatAmount),
          totalAfterVat: BigInt(preview.totalAfterVat),
          amountInWords: preview.amountInWords,
          manualTaxItemCount: preview.manualTaxItemCount,
          sourceOrderFetchedAt: preview.sourceOrderFetchedAt,
          quoteFingerprint: preview.quoteVersion,
          createdAt: now,
          expiresAt,
          sourceOrders: {
            create: preview.sourceOrders.map((source: any) => ({
              position: source.position,
              orderCode: source.orderCode,
              fetchedAt: source.fetchedAt,
            })),
          },
          items: {
            create: preview.items.map((item: any) => ({
              position: item.position,
              sourceLineKey: item.sourceLineKey,
              sku: item.sku,
              sellerSku: item.sellerSku,
              productName: item.productName,
              quantity: item.quantity,
              unit: item.unit,
              finalSellPrice: BigInt(item.finalSellPrice),
              erpRowTotal: BigInt(item.erpRowTotal ?? item.lineAfterVat),
              sourceOrderCodes: item.sourceOrderCodes,
              sourceLineIdentities: item.sourceLineIdentities,
              unitPriceBeforeVat: BigInt(item.unitPriceBeforeVat),
              vatRateBps: item.vatRateBps,
              taxCode: item.taxCode,
              taxLabel: item.taxLabel,
              taxSource: item.taxSource,
              taxFetchedAt: item.taxFetchedAt,
              lineBeforeVat: BigInt(item.lineBeforeVat),
              lineVatAmount: BigInt(item.lineVatAmount),
              lineAfterVat: BigInt(item.lineAfterVat),
            })),
          },
        },
        include: {
          sourceOrders: { orderBy: { position: 'asc' } },
          items: { orderBy: { position: 'asc' } },
        },
      });
      this.logger.log(
        `Contract appendix create succeeded: user=${logFingerprint(userId)} appendix=${logFingerprint(saved.id)} itemCount=${saved.items.length} manualTaxItemCount=${saved.manualTaxItemCount} durationMs=${Date.now() - startedAt}`,
      );
      return this.serializeSnapshot(saved);
    } catch (error) {
      this.logger.error(
        `Contract appendix create failed: user=${logFingerprint(userId)} orderCount=${orderCodes.length} durationMs=${Date.now() - startedAt} errorType=${this.errorType(error)}`,
      );
      throw error;
    }
  }

  async list(user: any, query: ListContractAppendicesDto) {
    const userId = this.requireUserId(user);
    const now = new Date();
    const page = query.page ?? 0;
    const limit = query.limit ?? 20;
    const search = String(query.query ?? '').trim();
    const where = {
      userId,
      expiresAt: { gt: now },
      ...(search
        ? {
            OR: [
              { orderCode: { contains: search, mode: 'insensitive' as const } },
              {
                sourceOrders: {
                  some: { orderCode: { contains: search, mode: 'insensitive' as const } },
                },
              },
            ],
          }
        : {}),
    };
    const [rows, total] = await this.prisma.$transaction([
      this.prisma.contractAppendix.findMany({
        where,
        orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
        skip: page * limit,
        take: limit,
        include: {
          sourceOrders: { orderBy: { position: 'asc' } },
          _count: { select: { items: true } },
        },
      }),
      this.prisma.contractAppendix.count({ where }),
    ]);
    this.logger.log(
      `Contract appendix history loaded: user=${logFingerprint(userId)} count=${rows.length} total=${total} page=${page}`,
    );
    return {
      items: rows.map((row: any) => ({
        id: row.id,
        orderCode: row.orderCode,
        orderCodes: row.orderCodes?.length ? row.orderCodes : [row.orderCode],
        sourceOrders: (row.sourceOrders ?? []).map((source: any) => ({
          position: source.position,
          orderCode: source.orderCode,
          fetchedAt: source.fetchedAt,
        })),
        itemCount: row._count.items,
        totalBeforeVat: safeMoneyNumber(row.totalBeforeVat),
        totalVatAmount: safeMoneyNumber(row.totalVatAmount),
        totalAfterVat: safeMoneyNumber(row.totalAfterVat),
        amountInWords: row.amountInWords,
        manualTaxItemCount: row.manualTaxItemCount,
        createdAt: row.createdAt,
        expiresAt: row.expiresAt,
      })),
      page,
      limit,
      total,
      hasMore: (page + 1) * limit < total,
    };
  }

  async detail(user: any, id: string) {
    const userId = this.requireUserId(user);
    const row = await this.prisma.contractAppendix.findFirst({
      where: { id, userId, expiresAt: { gt: new Date() } },
      include: {
        sourceOrders: { orderBy: { position: 'asc' } },
        items: { orderBy: { position: 'asc' } },
      },
    });
    if (!row) {
      throw new NotFoundException('Không tìm thấy phụ lục hợp đồng.');
    }
    this.logger.log(
      `Contract appendix detail loaded: user=${logFingerprint(userId)} appendix=${logFingerprint(id)} itemCount=${row.items.length}`,
    );
    return this.serializeSnapshot(row);
  }

  @Cron(CronExpression.EVERY_HOUR)
  async cleanupExpired() {
    const startedAt = Date.now();
    this.logger.debug('Contract appendix retention cleanup started');
    try {
      const result = await this.prisma.contractAppendix.deleteMany({
        where: { expiresAt: { lte: new Date() } },
      });
      this.logger.log(
        `Contract appendix retention cleanup succeeded: deletedCount=${result.count} durationMs=${Date.now() - startedAt}`,
      );
      return result.count;
    } catch (error) {
      this.logger.error(
        `Contract appendix retention cleanup failed: durationMs=${Date.now() - startedAt} error=${safeLogError(error)}`,
      );
      throw error;
    }
  }

  private async buildPreview(dto: PreviewContractAppendixDto) {
    const overrides = this.overrideMap(dto.overrides ?? []);
    const orderCodes = this.resolveOrderCodes(dto);
    const orders = await this.lookupOrdersAtomically(orderCodes);
    const preparedSource = orders.flatMap((order) =>
      order.items.map((item, index) =>
        this.prepareSourceLine(
          item,
          order.orderCode,
          index,
          overrides,
          orderCodes.length > 1,
        ),
      ),
    );
    if (preparedSource.length > 200) {
      throw new BadRequestException(
        'Các đơn hàng có quá nhiều sản phẩm. Vui lòng giảm số đơn hoặc liên hệ quản lý để được hỗ trợ.',
      );
    }
    const sourceKeys = new Set<string>();
    for (const line of preparedSource) {
      sourceKeys.add(line.sourceLineKey);
      for (const identity of line.sourceLineIdentities) sourceKeys.add(identity);
    }
    for (const key of overrides.keys()) {
      if (!sourceKeys.has(key)) {
        throw new BadRequestException(
          'Sản phẩm đã thay đổi. Vui lòng tải lại thông tin đơn hàng.',
        );
      }
    }
    const taxBySku = await this.lookupTaxesWithManualFallback(
      Array.from(new Set(preparedSource.map((item) => item.sku))),
    );
    const lines: PreparedLine[] = preparedSource.map((source) => {
      const override = overrides.get(source.sourceLineKey);
      const tax = taxBySku.get(source.sku);
      if (tax?.vatRateBps !== null && tax?.vatRateBps !== undefined) {
        return {
          ...source,
          vatRateBps: tax.vatRateBps,
          taxCode: tax.taxCode,
          taxLabel: tax.taxLabel,
          taxSource: 'ERP_PPM' as const,
          taxFetchedAt: tax.fetchedAt,
        };
      }
      if (override?.manualVatRateBps !== undefined) {
        return {
          ...source,
          vatRateBps: override.manualVatRateBps,
          taxCode: tax?.taxCode ?? null,
          taxLabel:
            tax?.taxLabel ??
            `Thuế nhập tay ${override.manualVatRateBps / 100}%`,
          taxSource: 'MANUAL' as const,
          taxFetchedAt: null,
        };
      }
      return {
        ...source,
        vatRateBps: null,
        taxCode: tax?.taxCode ?? null,
        taxLabel: tax?.taxLabel ?? null,
        taxSource: 'MISSING' as const,
        taxFetchedAt: null,
      };
    });
    const groupedLines = this.groupPreparedLines(lines);
    const unresolvedTaxCount = groupedLines.filter(
      (line) => line.vatRateBps === null,
    ).length;
    const terminalCode =
      process.env.ERP_PPM_TERMINAL_CODE?.trim() || ERP_PPM_TERMINAL_CODE;

    if (unresolvedTaxCount > 0) {
      const quoteVersion = this.unresolvedFingerprint(orderCodes, groupedLines);
      const totalAfterVat = safeMoneyNumber(
        groupedLines.reduce(
          (total, line) => total + BigInt(line.erpRowTotal),
          0n,
        ),
      );
      return {
        orderCode: orderCodes[0],
        orderCodes,
        sourceOrders: orders.map((order, index) => ({
          position: index,
          orderCode: order.orderCode,
          fetchedAt: order.fetchedAt,
        })),
        quoteVersion,
        terminalCode,
        sourceOrderFetchedAt: orders[0].fetchedAt,
        items: groupedLines.map((line, index) => ({
          ...line,
          position: index + 1,
          unitPriceBeforeVat: null,
          lineBeforeVat: null,
          lineVatAmount: null,
          lineAfterVat: line.erpRowTotal,
        })),
        totalBeforeVat: null,
        totalVatAmount: null,
        totalAfterVat,
        amountInWords: vietnameseContractAmountWords(totalAfterVat),
        manualTaxItemCount: groupedLines.filter((line) => line.taxSource === 'MANUAL')
          .length,
        unresolvedTaxCount,
        canSave: false,
      };
    }

    const calculation = calculateContractAppendix(
      orderCodes,
      groupedLines as ContractAppendixCalculationInput[],
    );
    return {
      orderCode: orderCodes[0],
      orderCodes,
      sourceOrders: orders.map((order, index) => ({
        position: index,
        orderCode: order.orderCode,
        fetchedAt: order.fetchedAt,
      })),
      quoteVersion: calculation.quoteFingerprint,
      terminalCode,
      sourceOrderFetchedAt: orders[0].fetchedAt,
      items: calculation.items.map((item) => ({
        ...item,
        finalSellPrice: item.finalSellPrice,
        unitPriceBeforeVat: safeMoneyNumber(item.unitPriceBeforeVat),
        lineBeforeVat: safeMoneyNumber(item.lineBeforeVat),
        lineVatAmount: safeMoneyNumber(item.lineVatAmount),
        lineAfterVat: safeMoneyNumber(item.lineAfterVat),
      })),
      totalBeforeVat: safeMoneyNumber(calculation.totalBeforeVat),
      totalVatAmount: safeMoneyNumber(calculation.totalVatAmount),
      totalAfterVat: safeMoneyNumber(calculation.totalAfterVat),
      amountInWords: calculation.amountInWords,
      manualTaxItemCount: calculation.manualTaxItemCount,
      unresolvedTaxCount: 0,
      canSave: true,
    };
  }

  private prepareSourceLine(
    item: SalesReportErpOrderItem,
    orderCode: string,
    index: number,
    overrides: Map<string, ContractAppendixLineOverrideDto>,
    multiOrder: boolean,
  ) {
    const sku = String(item.sku ?? item.sellerSku ?? '').trim();
    const quantity = item.quantity;
    const finalSellPrice = item.finalSellPrice;
    const erpRowTotal = item.rowTotal;
    if (!sku) {
      throw new BadRequestException(
        `Sản phẩm dòng ${index + 1} chưa có SKU trên ERP.`,
      );
    }
    if (!Number.isSafeInteger(quantity) || (quantity ?? 0) <= 0) {
      throw new BadRequestException(
        `Số lượng sản phẩm dòng ${index + 1} không hợp lệ.`,
      );
    }
    if (!Number.isSafeInteger(finalSellPrice) || (finalSellPrice ?? -1) < 0) {
      throw new BadRequestException(
        `ERP chưa trả finalSellPrice hợp lệ cho sản phẩm dòng ${index + 1}.`,
      );
    }
    if (!Number.isSafeInteger(erpRowTotal) || (erpRowTotal ?? -1) < 0) {
      throw new BadRequestException(
        `ERP chưa trả rowTotal hợp lệ cho sản phẩm dòng ${index + 1}.`,
      );
    }
    const sourceLineId = this.optionalSourceLineId(item) ?? `${index + 1}:${sku}`;
    const legacyLineKey = `${index + 1}:${sku}`;
    const sourceLineKey = multiOrder
      ? `${orderCode}:${sourceLineId}`
      : legacyLineKey;
    const sourceIdentity = `${orderCode}:${sourceLineId}`;
    const override = overrides.get(sourceLineKey) ?? overrides.get(legacyLineKey);
    const productName = String(override?.productName ?? item.name ?? '').trim();
    if (!productName) {
      throw new BadRequestException(
        `Sản phẩm dòng ${index + 1} chưa có tên hàng hóa.`,
      );
    }
    const unit = String(override?.unit ?? item.uomName ?? '')
      .trim()
      .slice(0, 30);
    if (!unit) {
      throw new BadRequestException(
        `ERP chưa trả đơn vị tính cho sản phẩm dòng ${index + 1}. Vui lòng kiểm tra lại đơn hàng.`,
      );
    }
    return {
      sourceLineKey,
      sourceOrderCodes: [orderCode],
      sourceLineIdentities: [sourceIdentity],
      sku,
      sellerSku: item.sellerSku,
      productName: productName.slice(0, 500),
      quantity: quantity as number,
      unit,
      finalSellPrice: finalSellPrice as number,
      erpRowTotal: erpRowTotal as number,
    };
  }

  private groupPreparedLines(lines: PreparedLine[]) {
    const groups = new Map<string, PreparedLine>();
    for (const line of lines) {
      const key = JSON.stringify([
        line.sku,
        line.finalSellPrice,
        line.vatRateBps,
        line.taxCode,
        line.taxLabel,
        line.taxSource,
        line.unit.trim().toLocaleLowerCase(),
      ]);
      const existing = groups.get(key);
      if (!existing) {
        groups.set(key, {
          ...line,
          sourceOrderCodes: [...line.sourceOrderCodes],
          sourceLineIdentities: [...line.sourceLineIdentities],
        });
        continue;
      }
      const quantity = existing.quantity + line.quantity;
      const erpRowTotal = existing.erpRowTotal + line.erpRowTotal;
      if (!Number.isSafeInteger(quantity) || !Number.isSafeInteger(erpRowTotal)) {
        throw new BadRequestException(
          'Tổng số lượng hoặc tổng tiền sản phẩm vượt giới hạn hệ thống hỗ trợ.',
        );
      }
      existing.quantity = quantity;
      existing.erpRowTotal = erpRowTotal;
      existing.sourceOrderCodes = Array.from(
        new Set([...existing.sourceOrderCodes, ...line.sourceOrderCodes]),
      );
      existing.sourceLineIdentities.push(...line.sourceLineIdentities);
    }
    return Array.from(groups.values());
  }

  private optionalSourceLineId(item: SalesReportErpOrderItem) {
    const raw = item.raw as Record<string, unknown> | undefined;
    const value = raw?.contractAppendixSourceLineId;
    const text = String(value ?? '').trim();
    return text || null;
  }

  private async lookupTaxesWithManualFallback(skus: string[]) {
    try {
      const result = await this.productErp.lookupTaxes(skus);
      return new Map(result.items.map((item) => [item.sku, item]));
    } catch (error) {
      this.logger.warn(
        `Contract appendix PPM unavailable; manual tax required: skuCount=${new Set(skus).size} lookupMode=live error=${safeLogError(error)}`,
      );
      return new Map<string, ErpPpmProductTax>();
    }
  }

  private resolveOrderCodes(dto: PreviewContractAppendixDto) {
    const legacy = String(dto.orderCode ?? '').trim();
    const plural = Array.isArray(dto.orderCodes)
      ? dto.orderCodes.map((value) => String(value ?? '').trim())
      : [];
    const normalizedPlural = this.uniqueOrderCodes(plural);
    if (legacy && normalizedPlural.length > 0) {
      if (
        normalizedPlural.length !== 1 ||
        normalizedPlural[0] !== this.normalizeOrderCodeValue(legacy)
      ) {
        throw new BadRequestException(
          'Danh sách mã đơn không khớp. Vui lòng chỉ dùng một cách nhập mã đơn.',
        );
      }
    }
    const orderCodes = normalizedPlural.length > 0
      ? normalizedPlural
      : this.uniqueOrderCodes(legacy ? [legacy] : []);
    if (orderCodes.length === 0) {
      throw new BadRequestException('Vui lòng nhập ít nhất một mã đơn hàng.');
    }
    if (orderCodes.length > 10) {
      throw new BadRequestException('Mỗi phụ lục chỉ được chọn tối đa 10 đơn hàng.');
    }
    return orderCodes;
  }

  private uniqueOrderCodes(values: string[]) {
    const output: string[] = [];
    const seen = new Set<string>();
    for (const value of values) {
      const normalized = this.normalizeOrderCodeValue(value);
      if (!normalized) {
        throw new BadRequestException('Mã đơn hàng không được để trống.');
      }
      if (seen.has(normalized)) {
        throw new BadRequestException('Mã đơn hàng bị trùng trong danh sách.');
      }
      seen.add(normalized);
      output.push(normalized);
    }
    return output;
  }

  private normalizeOrderCodeValue(value: string) {
    return value.trim().toUpperCase();
  }

  private async lookupOrdersAtomically(orderCodes: string[]): Promise<PreparedOrder[]> {
    const results: Array<PromiseSettledResult<SalesReportErpOrder>> = [];
    const orders: Array<SalesReportErpOrder | undefined> = [];
    const concurrency = Math.min(3, orderCodes.length);
    let cursor = 0;
    await Promise.all(
      Array.from({ length: concurrency }, async () => {
        while (true) {
          const index = cursor++;
          if (index >= orderCodes.length) return;
          try {
            const result = await this.orderErp.lookupContractAppendixOrder(
              orderCodes[index],
            );
            orders[index] = result;
            results[index] = { status: 'fulfilled', value: result };
          } catch (reason) {
            results[index] = { status: 'rejected', reason };
          }
        }
      }),
    );
    const rejectedIndex = results.findIndex(
      (result) => result?.status === 'rejected',
    );
    if (rejectedIndex >= 0) {
      throw new ContractAppendixOrderLookupException(orderCodes[rejectedIndex]);
    }
    return orders.map((order, index) => {
      if (!order) {
        throw new BadRequestException(
          `Chưa lấy được thông tin đơn hàng thứ ${index + 1}.`,
        );
      }
      return {
        orderCode: orderCodes[index],
        fetchedAt: order.fetchedAt,
        items: order.items,
      };
    });
  }

  private overrideMap(values: ContractAppendixLineOverrideDto[]) {
    const result = new Map<string, ContractAppendixLineOverrideDto>();
    for (const value of values) {
      const key = String(value.sourceLineKey ?? '').trim();
      if (result.has(key)) {
        throw new BadRequestException(
          'Mỗi sản phẩm chỉ được chỉnh sửa một lần.',
        );
      }
      if (
        value.manualVatRateBps !== undefined &&
        !MANUAL_VAT_RATE_BPS.includes(value.manualVatRateBps as any)
      ) {
        throw new BadRequestException('Mức thuế nhập tay không hợp lệ.');
      }
      result.set(key, value);
      for (const identity of value.sourceLineIdentities ?? []) {
        const normalizedIdentity = String(identity ?? '').trim();
        if (!normalizedIdentity) {
          throw new BadRequestException(
            'Nguồn sản phẩm được chỉnh sửa không hợp lệ.',
          );
        }
        if (normalizedIdentity === key) continue;
        if (result.has(normalizedIdentity)) {
          throw new BadRequestException(
            'Mỗi sản phẩm chỉ được chỉnh sửa một lần.',
          );
        }
        result.set(normalizedIdentity, value);
      }
    }
    return result;
  }

  private unresolvedFingerprint(orderCodes: string[], lines: PreparedLine[]) {
    return createHash('sha256')
      .update(
        JSON.stringify({
          orderCodes,
          items: lines.map((line) => ({
            sourceLineKey: line.sourceLineKey,
            sourceOrderCodes: line.sourceOrderCodes,
            sourceLineIdentities: line.sourceLineIdentities,
            sku: line.sku,
            quantity: line.quantity,
            finalSellPrice: line.finalSellPrice,
            erpRowTotal: line.erpRowTotal,
            vatRateBps: line.vatRateBps,
            taxSource: line.taxSource,
            taxCode: line.taxCode,
            taxLabel: line.taxLabel,
            productName: line.productName,
            unit: line.unit,
          })),
        }),
      )
      .digest('hex');
  }

  private serializeSnapshot(row: any) {
    const rawSourceOrders = Array.isArray(row.sourceOrders)
      ? row.sourceOrders
      : [];
    const sourceOrders = rawSourceOrders.length
      ? [...rawSourceOrders]
          .sort((left, right) => left.position - right.position)
          .map((source: any) => ({
            position: source.position,
            orderCode: source.orderCode,
            fetchedAt: source.fetchedAt,
          }))
      : row.orderCode
        ? [
            {
              position: 0,
              orderCode: row.orderCode,
              fetchedAt: row.sourceOrderFetchedAt,
            },
          ]
        : [];
    const storedOrderCodes = Array.isArray(row.orderCodes)
      ? row.orderCodes.filter((value: unknown) => String(value ?? '').trim())
      : [];
    const orderCodes = storedOrderCodes.length
      ? storedOrderCodes
      : sourceOrders.length
        ? sourceOrders.map((source) => source.orderCode)
        : [row.orderCode];
    const items = [...row.items]
      .sort((left, right) => left.position - right.position)
      .map((item: any) => ({
        ...item,
        finalSellPrice: this.serializeMoney(item.finalSellPrice),
        erpRowTotal: this.serializeMoney(item.erpRowTotal ?? item.lineAfterVat),
        sourceOrderCodes:
          Array.isArray(item.sourceOrderCodes) && item.sourceOrderCodes.length
            ? item.sourceOrderCodes
            : [row.orderCode],
        sourceLineIdentities:
          Array.isArray(item.sourceLineIdentities) && item.sourceLineIdentities.length
            ? item.sourceLineIdentities
            : [item.sourceLineKey],
        unitPriceBeforeVat: this.serializeMoney(item.unitPriceBeforeVat),
        lineBeforeVat: this.serializeMoney(item.lineBeforeVat),
        lineVatAmount: this.serializeMoney(item.lineVatAmount),
        lineAfterVat: this.serializeMoney(
          item.lineAfterVat ?? item.erpRowTotal,
        ),
      }));
    return {
      id: row.id,
      orderCode: row.orderCode,
      orderCodes,
      sourceOrders,
      quoteVersion: row.quoteFingerprint,
      terminalCode: row.terminalCode,
      sourceOrderFetchedAt: row.sourceOrderFetchedAt,
      items,
      totalBeforeVat: safeMoneyNumber(row.totalBeforeVat),
      totalVatAmount: safeMoneyNumber(row.totalVatAmount),
      totalAfterVat: safeMoneyNumber(row.totalAfterVat),
      amountInWords: row.amountInWords,
      manualTaxItemCount: row.manualTaxItemCount,
      unresolvedTaxCount: 0,
      canSave: true,
      createdAt: row.createdAt,
      expiresAt: row.expiresAt,
    };
  }

  private serializeMoney(value: unknown) {
    if (value === null || value === undefined) return null;
    return safeMoneyNumber(BigInt(value as any));
  }

  private errorType(error: unknown) {
    return error instanceof Error ? error.constructor.name : typeof error;
  }

  private requireUserId(user: any) {
    const id = String(user?.id ?? '').trim();
    if (!id) throw new BadRequestException('Không xác định được người dùng.');
    return id;
  }
}
