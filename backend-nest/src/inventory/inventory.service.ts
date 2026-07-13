import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { BigQuery } from '@google-cloud/bigquery';
import { PrismaService } from '../prisma/prisma.service';
import { Cron, CronExpression } from '@nestjs/schedule';
import { getDataSyncSource } from '../config/env';
import { safeLogError } from '../common/log-sanitizer';

@Injectable()
export class InventoryService implements OnModuleInit {
  private readonly logger = new Logger(InventoryService.name);
  private bigquery?: BigQuery;

  constructor(private prisma: PrismaService) {
    if (getDataSyncSource() !== 'bigquery') {
      return;
    }

    const projectId = process.env.BIGQUERY_PROJECT_ID;
    const keyFilename = process.env.BIGQUERY_KEY_FILE;

    this.bigquery = new BigQuery({
      projectId,
      ...(keyFilename ? { keyFilename } : {}),
    });
  }

  onModuleInit() {
    if (getDataSyncSource() !== 'bigquery') {
      this.logger.log(
        'DATA_SYNC_SOURCE=local, skipping BigQuery inventory sync',
      );
      return;
    }

    // Run initial sync on startup
    this.syncFromBigQuery();
  }

  // -------------------------------------------------------
  // Sync every hour from BigQuery
  // -------------------------------------------------------
  @Cron(CronExpression.EVERY_HOUR)
  async syncFromBigQuery() {
    if (getDataSyncSource() !== 'bigquery') {
      this.logger.log(
        'DATA_SYNC_SOURCE=local, skipping BigQuery inventory sync',
      );
      return;
    }

    this.logger.log('Starting BigQuery sync...');
    try {
      const projectId = process.env.BIGQUERY_PROJECT_ID;
      const datasetId = process.env.BIGQUERY_DATASET_ID;
      const tableId = process.env.BIGQUERY_TABLE_ID;

      if (!projectId || !datasetId || !tableId) {
        this.logger.warn(
          'BIGQUERY_PROJECT_ID / BIGQUERY_DATASET_ID / BIGQUERY_TABLE_ID not set, skipping sync',
        );
        return;
      }

      const query = `SELECT * FROM \`${projectId}.${datasetId}.${tableId}\``;
      const [rows] = await this.bigquery!.query({ query });

      this.logger.log(`Fetched ${rows.length} rows from BigQuery`);

      // Clear and re-insert
      await this.prisma.inventory.deleteMany();

      const data = rows
        .filter((row: any) => row.sku || row.SKU)
        .map((row: any) => ({
          sku: String(row.sku || row.SKU || '').trim(),
          skuName: String(
            row.skuName || row.sku_name || row.SKU_NAME || '',
          ).trim(),
          serialNumber:
            row.serial_number || row.serialNumber || row.SERIAL_NUMBER
              ? String(
                  row.serial_number || row.serialNumber || row.SERIAL_NUMBER,
                ).trim()
              : null,
          bin:
            row.bin_id || row.bin || row.BIN
              ? String(row.bin_id || row.bin || row.BIN).trim()
              : null,
          zone:
            row.zone || row.ZONE ? String(row.zone || row.ZONE).trim() : null,
          importDate:
            row.import_date_company ||
            row.import_date ||
            row.importDate ||
            row.IMPORT_DATE
              ? new Date(
                  row.import_date_company ||
                    row.import_date ||
                    row.importDate ||
                    row.IMPORT_DATE,
                )
              : null,
          count:
            row.qty || row.count || row.COUNT
              ? parseInt(String(row.qty || row.count || row.COUNT))
              : 1,
        }));

      if (data.length > 0) {
        await this.prisma.inventory.createMany({ data });
        this.logger.log(`Sync complete: ${data.length} records inserted`);
      } else {
        this.logger.warn('No valid rows found in BigQuery table');
      }
    } catch (error) {
      this.logger.error(`BigQuery sync failed: ${safeLogError(error)}`);
    }
  }

  // -------------------------------------------------------
  // Lookup by SKU (for Chat/Sort feature)
  // Returns sorted by importDate ASC (FIFO order)
  // -------------------------------------------------------
  async lookupBySku(sku: string) {
    const items = await this.prisma.inventory.findMany({
      where: { sku: { contains: sku, mode: 'insensitive' } },
      orderBy: { importDate: 'asc' }, // FIFO: oldest first
    });
    return this.formatFifoResponse(items);
  }

  // -------------------------------------------------------
  // Lookup by BIN code (for Sort feature)
  // -------------------------------------------------------
  async lookupByBin(bin: string) {
    const items = await this.prisma.inventory.findMany({
      where: { bin: { contains: bin, mode: 'insensitive' } },
      orderBy: { importDate: 'asc' },
    });
    return this.formatFifoResponse(items);
  }

  // -------------------------------------------------------
  // Lookup by serial number
  // -------------------------------------------------------
  async lookupBySerial(serial: string) {
    return this.prisma.inventory.findFirst({
      where: { serialNumber: { equals: serial, mode: 'insensitive' } },
    });
  }

  // -------------------------------------------------------
  // FIFO Check by SKU: return the oldest (qty+1) items
  // Default qty=1 → returns 2 items
  // -------------------------------------------------------
  async fifoCheckBySku(sku: string, qty: number = 1) {
    const items = await this.prisma.inventory.findMany({
      where: { sku: { equals: sku, mode: 'insensitive' } },
      orderBy: { importDate: 'asc' },
      take: qty + 1,
    });

    return this.formatFifoResponse(items);
  }

  // -------------------------------------------------------
  // FIFO Check by Serial: check if this serial is the oldest
  // for its SKU group → return true/false
  // -------------------------------------------------------
  async fifoCheckBySerial(serial: string) {
    // Find the item with this serial
    const item = await this.prisma.inventory.findFirst({
      where: { serialNumber: { equals: serial, mode: 'insensitive' } },
    });

    if (!item) {
      return { found: false, message: `Không tìm thấy serial: ${serial}` };
    }

    // Find the oldest item for the same SKU
    const oldestItem = await this.prisma.inventory.findFirst({
      where: { sku: { equals: item.sku, mode: 'insensitive' } },
      orderBy: { importDate: 'asc' },
    });

    const isOldest = oldestItem?.serialNumber === item.serialNumber;
    const formatted = this.formatFifoResponse([item])[0];

    const result: any = {
      found: true,
      is_oldest: isOldest,
      message: isOldest
        ? `✅ Đúng FIFO`
        : `❌ Sai FIFO — Cần lấy sản phẩm cũ hơn trước`,
      item: formatted,
    };

    // When wrong FIFO, suggest the correct (oldest) item
    if (!isOldest && oldestItem) {
      result.suggested_item = this.formatFifoResponse([oldestItem])[0];
    }

    return result;
  }

  // -------------------------------------------------------
  // Format helper: dd/MM/yyyy
  // -------------------------------------------------------
  private formatDateDDMMYYYY(date: Date): string {
    const d = date.getDate().toString().padStart(2, '0');
    const m = (date.getMonth() + 1).toString().padStart(2, '0');
    const y = date.getFullYear();
    return `${d}/${m}/${y}`;
  }

  private formatFifoResponse(items: any[]) {
    return items.map((item, index) => {
      const importDate = item.importDate
        ? this.formatDateDDMMYYYY(new Date(item.importDate))
        : 'N/A';
      return {
        sku: item.sku,
        sku_name: item.skuName,
        serial_number: item.serialNumber,
        bin: item.bin || '',
        zone: item.zone || '',
        import_date: importDate,
        count: item.count,
        fifo: index === 0 ? 'yes' : null, // first item is FIFO-correct
      };
    });
  }
}
