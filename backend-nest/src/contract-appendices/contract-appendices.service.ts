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
  type SalesReportErpOrderItem,
} from '../sales-reports/sales-report-erp.service';
import {
  calculateContractAppendix,
  safeMoneyNumber,
  type ContractAppendixCalculationInput,
} from './contract-appendix-calculator';
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
  sku: string;
  sellerSku: string | null;
  productName: string;
  quantity: number;
  unit: string;
  finalSellPrice: number;
  vatRateBps: number | null;
  taxCode: string | null;
  taxLabel: string | null;
  taxSource: 'ERP_PPM' | 'MANUAL' | 'MISSING';
  taxFetchedAt: Date | null;
};

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
    this.logger.log(
      `Contract appendix preview started: user=${logFingerprint(userId)} order=${logFingerprint(dto.orderCode)} overrideCount=${dto.overrides?.length ?? 0}`,
    );
    try {
      const result = await this.buildPreview(dto, false);
      this.logger.log(
        `Contract appendix preview succeeded: user=${logFingerprint(userId)} itemCount=${result.items.length} unresolvedTaxCount=${result.unresolvedTaxCount} manualTaxItemCount=${result.manualTaxItemCount} durationMs=${Date.now() - startedAt}`,
      );
      return result;
    } catch (error) {
      this.logger.error(
        `Contract appendix preview failed: user=${logFingerprint(userId)} order=${logFingerprint(dto.orderCode)} durationMs=${Date.now() - startedAt} error=${safeLogError(error)}`,
      );
      throw error;
    }
  }

  async create(user: any, dto: CreateContractAppendixDto) {
    const startedAt = Date.now();
    const userId = this.requireUserId(user);
    this.logger.log(
      `Contract appendix create started: user=${logFingerprint(userId)} order=${logFingerprint(dto.orderCode)} overrideCount=${dto.overrides?.length ?? 0}`,
    );
    try {
      const preview = await this.buildPreview(dto, true);
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
        include: { items: { orderBy: { position: 'asc' } } },
      });
      this.logger.log(
        `Contract appendix create succeeded: user=${logFingerprint(userId)} appendix=${logFingerprint(saved.id)} itemCount=${saved.items.length} manualTaxItemCount=${saved.manualTaxItemCount} durationMs=${Date.now() - startedAt}`,
      );
      return this.serializeSnapshot(saved);
    } catch (error) {
      this.logger.error(
        `Contract appendix create failed: user=${logFingerprint(userId)} order=${logFingerprint(dto.orderCode)} durationMs=${Date.now() - startedAt} error=${safeLogError(error)}`,
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
        ? { orderCode: { contains: search, mode: 'insensitive' as const } }
        : {}),
    };
    const [rows, total] = await this.prisma.$transaction([
      this.prisma.contractAppendix.findMany({
        where,
        orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
        skip: page * limit,
        take: limit,
        include: { _count: { select: { items: true } } },
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
      include: { items: { orderBy: { position: 'asc' } } },
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

  private async buildPreview(
    dto: PreviewContractAppendixDto,
    forceTaxRefresh: boolean,
  ) {
    const overrides = this.overrideMap(dto.overrides ?? []);
    const order = await this.orderErp.lookupOrder(dto.orderCode);
    const preparedSource = order.items.map((item, index) =>
      this.prepareSourceLine(item, index, overrides),
    );
    const sourceKeys = new Set(
      preparedSource.map((item) => item.sourceLineKey),
    );
    for (const key of overrides.keys()) {
      if (!sourceKeys.has(key)) {
        throw new BadRequestException(
          'Sản phẩm đã thay đổi. Vui lòng tải lại thông tin đơn hàng.',
        );
      }
    }
    const taxBySku = await this.lookupTaxesWithManualFallback(
      preparedSource.map((item) => item.sku),
      forceTaxRefresh,
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
    const unresolvedTaxCount = lines.filter(
      (line) => line.vatRateBps === null,
    ).length;
    const terminalCode =
      process.env.ERP_PPM_TERMINAL_CODE?.trim() || ERP_PPM_TERMINAL_CODE;

    if (unresolvedTaxCount > 0) {
      const quoteVersion = this.unresolvedFingerprint(order.orderCode, lines);
      return {
        orderCode: order.orderCode,
        quoteVersion,
        terminalCode,
        sourceOrderFetchedAt: order.fetchedAt,
        items: lines.map((line, index) => ({
          ...line,
          position: index + 1,
          unitPriceBeforeVat: null,
          lineBeforeVat: null,
          lineVatAmount: null,
          lineAfterVat: line.finalSellPrice * line.quantity,
        })),
        totalBeforeVat: null,
        totalVatAmount: null,
        totalAfterVat: null,
        amountInWords: null,
        manualTaxItemCount: lines.filter((line) => line.taxSource === 'MANUAL')
          .length,
        unresolvedTaxCount,
        canSave: false,
      };
    }

    const calculation = calculateContractAppendix(
      order.orderCode,
      lines as ContractAppendixCalculationInput[],
    );
    return {
      orderCode: order.orderCode,
      quoteVersion: calculation.quoteFingerprint,
      terminalCode,
      sourceOrderFetchedAt: order.fetchedAt,
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
    index: number,
    overrides: Map<string, ContractAppendixLineOverrideDto>,
  ) {
    const sku = String(item.sku ?? item.sellerSku ?? '').trim();
    const quantity = item.quantity;
    const finalSellPrice = item.finalSellPrice;
    if (!sku) {
      throw new BadRequestException(
        `Sản phẩm dòng ${index + 1} chưa có SKU trên ERP.`,
      );
    }
    if (!Number.isInteger(quantity) || (quantity ?? 0) <= 0) {
      throw new BadRequestException(
        `Số lượng sản phẩm dòng ${index + 1} không hợp lệ.`,
      );
    }
    if (!Number.isSafeInteger(finalSellPrice) || (finalSellPrice ?? -1) < 0) {
      throw new BadRequestException(
        `ERP chưa trả finalSellPrice hợp lệ cho sản phẩm dòng ${index + 1}.`,
      );
    }
    const sourceLineKey = `${index + 1}:${sku}`;
    const override = overrides.get(sourceLineKey);
    const productName = String(override?.productName ?? item.name ?? '').trim();
    if (!productName) {
      throw new BadRequestException(
        `Sản phẩm dòng ${index + 1} chưa có tên hàng hóa.`,
      );
    }
    return {
      sourceLineKey,
      sku,
      sellerSku: item.sellerSku,
      productName: productName.slice(0, 500),
      quantity: quantity as number,
      unit:
        String(override?.unit ?? 'Cái')
          .trim()
          .slice(0, 30) || 'Cái',
      finalSellPrice: finalSellPrice as number,
    };
  }

  private async lookupTaxesWithManualFallback(
    skus: string[],
    forceRefresh: boolean,
  ) {
    try {
      const result = await this.productErp.lookupTaxes(skus, { forceRefresh });
      return new Map(result.items.map((item) => [item.sku, item]));
    } catch (error) {
      this.logger.warn(
        `Contract appendix PPM unavailable; manual tax required: skuCount=${new Set(skus).size} forceRefresh=${forceRefresh} error=${safeLogError(error)}`,
      );
      return new Map<string, ErpPpmProductTax>();
    }
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
    }
    return result;
  }

  private unresolvedFingerprint(orderCode: string, lines: PreparedLine[]) {
    return createHash('sha256')
      .update(
        JSON.stringify({
          orderCode,
          items: lines.map((line) => ({
            sourceLineKey: line.sourceLineKey,
            sku: line.sku,
            quantity: line.quantity,
            finalSellPrice: line.finalSellPrice,
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
    const items = [...row.items]
      .sort((left, right) => left.position - right.position)
      .map((item: any) => ({
        ...item,
        finalSellPrice: safeMoneyNumber(item.finalSellPrice),
        unitPriceBeforeVat: safeMoneyNumber(item.unitPriceBeforeVat),
        lineBeforeVat: safeMoneyNumber(item.lineBeforeVat),
        lineVatAmount: safeMoneyNumber(item.lineVatAmount),
        lineAfterVat: safeMoneyNumber(item.lineAfterVat),
      }));
    return {
      id: row.id,
      orderCode: row.orderCode,
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

  private requireUserId(user: any) {
    const id = String(user?.id ?? '').trim();
    if (!id) throw new BadRequestException('Không xác định được người dùng.');
    return id;
  }
}
