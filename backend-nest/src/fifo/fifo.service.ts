import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { FifoLogType } from '@prisma/client';
import { FifoLogService } from '../fifo-log/fifo-log.service';
import { PrismaService } from '../prisma/prisma.service';
import { ADMIN_POLICY_CODES } from '../policy/policy.constants';
import { PolicyService } from '../policy/policy.service';
import { isAdminRole, isSuperAdminRole } from '../common/system-role';
import {
  DISPLAY_RESERVED_BIN_TYPE,
  FifoInventoryItem,
  ManualInventoryImportResult,
  OpshubFifoInventoryService,
} from './opshub-fifo-inventory.service';

export type FifoCheckResult =
  | {
      mode: 'sku';
      query: string;
      srCode: string;
      includeExported: boolean;
      items: FifoItemResponse[];
    }
  | {
      mode: 'serial';
      query: string;
      srCode: string;
      status:
        | 'correct'
        | 'wrong'
        | 'display_reserved'
        | 'exported'
        | 'not_found';
      message: string;
      fifoDateDeltaDays?: number | null;
      fifoToleranceDays?: number;
      item?: FifoItemResponse;
      suggestedItem?: FifoItemResponse;
    };

type FifoItemResponse = {
  id: string;
  sr_code: string;
  sku: string;
  sku_name: string;
  serial_number: string | null;
  bin: string;
  zone: string;
  import_date: string;
  count: number;
  exported: boolean;
  fifo: 'yes' | null;
};

@Injectable()
export class FifoService {
  constructor(
    private prisma: PrismaService,
    private inventory: OpshubFifoInventoryService,
    private fifoLogService: FifoLogService,
    private policyService: PolicyService,
  ) {}

  async check(
    user: any,
    input: { text: string; includeExported?: boolean },
  ): Promise<FifoCheckResult> {
    const text = this.normalizeQuery(input.text);
    const srCode = await this.resolveSrCode(user);
    const includeExported = input.includeExported === true;

    const skuItems = await this.inventory.findBySku(
      srCode,
      text,
      includeExported,
    );

    if (skuItems.length > 0) {
      const result: FifoCheckResult = {
        mode: 'sku',
        query: text,
        srCode,
        includeExported,
        items: skuItems.map((item, index) => this.formatItem(item, index)),
      };
      await this.log(
        user,
        text,
        srCode,
        `SKU check: ${skuItems.length} item(s)`,
        result,
      );
      return result;
    }

    const item = await this.inventory.findBySerial(srCode, text, true);
    if (!item) {
      const result: FifoCheckResult = {
        mode: 'serial',
        query: text,
        srCode,
        status: 'not_found',
        message: 'Không tìm thấy',
      };
      await this.log(user, text, srCode, result.message, result);
      return result;
    }

    if (item.binType === DISPLAY_RESERVED_BIN_TYPE) {
      const result: FifoCheckResult = {
        mode: 'serial',
        query: text,
        srCode,
        status: 'display_reserved',
        message: 'Hàng trưng bày chỉ định',
        item: this.formatItem(item, 0),
      };
      await this.log(user, text, srCode, result.message, result);
      return result;
    }

    if (item.exported) {
      const result: FifoCheckResult = {
        mode: 'serial',
        query: text,
        srCode,
        status: 'exported',
        message: 'Đã xuất kho',
        item: this.formatItem(item, 0),
      };
      await this.log(user, text, srCode, result.message, result);
      return result;
    }

    const oldest = await this.inventory.findOldestActiveForSku(
      srCode,
      item.sku,
    );
    const toleranceDays = this.getFifoDateToleranceDays();
    const deltaDays = oldest
      ? this.diffCalendarDays(item.importDate, oldest.importDate)
      : null;
    const isCorrect =
      !oldest ||
      oldest.id === item.id ||
      (deltaDays !== null && deltaDays <= toleranceDays);
    const result: FifoCheckResult = {
      mode: 'serial',
      query: text,
      srCode,
      status: isCorrect ? 'correct' : 'wrong',
      message: isCorrect ? 'Đúng FIFO' : 'Sai FIFO',
      fifoDateDeltaDays: deltaDays,
      fifoToleranceDays: toleranceDays,
      item: this.formatItem(item, 0),
      ...(isCorrect || !oldest
        ? {}
        : { suggestedItem: this.formatItem(oldest, 0) }),
    };
    await this.log(user, text, srCode, result.message, result);
    return result;
  }

  async sort(user: any, input: { text: string }) {
    const text = this.normalizeQuery(input.text);
    const srCode = await this.resolveSrCode(user);

    let items = await this.inventory.findBySku(srCode, text, false);
    let source: 'sku' | 'bin' = 'sku';

    if (items.length === 0) {
      source = 'bin';
      items = await this.inventory.findByBin(srCode, text, false);
    }

    const result = items.map((item, index) => this.formatItem(item, index));
    await this.log(
      user,
      text,
      srCode,
      result.length > 0 ? `${result.length} item(s) found` : 'Không tìm thấy',
      { mode: 'sort', source, srCode, items: result },
      FifoLogType.FIFO_SORT,
    );

    return result;
  }

  async setExported(
    user: any,
    input: { inventoryId: string; exported: boolean },
  ) {
    const inventoryId = this.normalizeInventoryId(input.inventoryId);
    const srCode = await this.resolveSrCode(user);
    const item = await this.inventory.setExported(
      srCode,
      inventoryId,
      input.exported,
    );
    if (!item) {
      throw new NotFoundException('Không tìm thấy sản phẩm trong SR của bạn');
    }

    const result = {
      status: 'success',
      srCode,
      exported: input.exported,
      item: this.formatItem(item, 0),
    };
    await this.log(
      user,
      item.serialNumber || item.sku,
      srCode,
      input.exported ? 'Marked exported' : 'Unmarked exported',
      {
        action: 'FIFO_EXPORT',
        srCode,
        inventoryId: item.id,
        sku: item.sku,
        serialNumber: item.serialNumber,
        exported: input.exported,
      },
    );
    return result;
  }

  async importManualInventory(
    user: any,
    items: Parameters<OpshubFifoInventoryService['importManualInventory']>[0],
    meta: { fileName?: string; totalRows: number; skippedRows: number },
  ): Promise<
    ManualInventoryImportResult & { skippedRows: number; totalRows: number }
  > {
    await this.assertInventoryImportAdmin(user);
    const result = await this.inventory.importManualInventory(items);
    await this.log(
      user,
      meta.fileName || 'manual-inventory-upload',
      result.srCodes.join(','),
      `Manual inventory import: ${result.importedRows} row(s)`,
      {
        action: 'FIFO_MANUAL_INVENTORY_IMPORT',
        fileName: meta.fileName,
        totalRows: meta.totalRows,
        importedRows: result.importedRows,
        skippedRows: meta.skippedRows,
        deactivatedRows: result.deactivatedRows,
        srCodes: result.srCodes,
      },
      FifoLogType.FIFO_SORT,
    );
    return {
      ...result,
      skippedRows: meta.skippedRows,
      totalRows: meta.totalRows,
    };
  }

  private async resolveSrCode(user: any) {
    if (!user?.storeId) {
      throw new ForbiddenException('User chưa được gán SR/showroom');
    }

    const store = await this.prisma.store.findUnique({
      where: { id: user.storeId },
      select: { storeId: true },
    });
    if (!store?.storeId) {
      throw new ForbiddenException('Không tìm thấy showroom của tài khoản này');
    }
    return store.storeId.trim().toUpperCase();
  }

  private normalizeQuery(value: string) {
    const text = String(value || '')
      .trim()
      .toUpperCase();
    if (!text) throw new BadRequestException('Vui lòng nhập SKU hoặc serial');
    return text;
  }

  private normalizeInventoryId(value: string) {
    const text = String(value || '').trim();
    if (!text) throw new BadRequestException('Missing inventory id');
    return text;
  }

  private getFifoDateToleranceDays() {
    const raw = process.env.FIFO_DATE_TOLERANCE_DAYS?.trim() || '20';
    const parsed = Number(raw);
    return Number.isFinite(parsed) && parsed >= 0 ? Math.floor(parsed) : 20;
  }

  private diffCalendarDays(current: Date | null, oldest: Date | null) {
    if (!current || !oldest) return null;
    const currentUtc = Date.UTC(
      current.getUTCFullYear(),
      current.getUTCMonth(),
      current.getUTCDate(),
    );
    const oldestUtc = Date.UTC(
      oldest.getUTCFullYear(),
      oldest.getUTCMonth(),
      oldest.getUTCDate(),
    );
    return Math.abs(Math.round((currentUtc - oldestUtc) / 86_400_000));
  }

  private assertInventoryImportAdmin(user: any) {
    if (!isAdminRole(user?.role) && !isSuperAdminRole(user?.role)) {
      throw new ForbiddenException('Bạn không có quyền cập nhật tồn kho');
    }
  }

  private formatItem(item: FifoInventoryItem, index: number): FifoItemResponse {
    return {
      id: item.id,
      sr_code: item.srCode,
      sku: item.sku,
      sku_name: item.skuName,
      serial_number: item.serialNumber,
      bin: item.bin || '',
      zone: item.zone || '',
      import_date: item.importDate
        ? this.formatDateDDMMYYYY(item.importDate)
        : 'N/A',
      count: item.count,
      exported: item.exported,
      fifo: !item.exported && index === 0 ? 'yes' : null,
    };
  }

  private formatDateDDMMYYYY(date: Date): string {
    const d = date.getDate().toString().padStart(2, '0');
    const m = (date.getMonth() + 1).toString().padStart(2, '0');
    const y = date.getFullYear();
    return `${d}/${m}/${y}`;
  }

  private async log(
    user: any,
    query: string,
    srCode: string,
    result: string,
    resultJson: unknown,
    type: FifoLogType = FifoLogType.FIFO_CHECK,
  ) {
    if (!user?.email) return;
    await this.fifoLogService.createLog(
      type,
      query,
      result,
      { srCode, result: resultJson },
      user.email,
    );
  }
}
