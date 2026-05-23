import {
  Injectable,
  InternalServerErrorException,
  OnModuleDestroy,
} from '@nestjs/common';
import pg from 'pg';

export type FifoInventoryItem = {
  id: string;
  srCode: string;
  sku: string;
  skuName: string;
  serialNumber: string | null;
  bin: string | null;
  zone: string | null;
  importDate: Date | null;
  count: number;
  exported: boolean;
};

type InventoryColumns = {
  id: string;
  srCode: string;
  sku: string;
  skuName: string;
  serialNumber: string;
  bin: string;
  zone: string;
  importDate: string;
  count: string;
  exported: string;
};

const DEFAULT_COLUMNS: InventoryColumns = {
  id: 'id',
  srCode: 'sr_code',
  sku: 'sku',
  skuName: 'sku_name',
  serialNumber: 'serial_number',
  bin: 'bin',
  zone: 'zone',
  importDate: 'import_date',
  count: 'count',
  exported: 'exported',
};

@Injectable()
export class PriceWatchdogInventoryService implements OnModuleDestroy {
  private pool?: pg.Pool;

  async onModuleDestroy() {
    await this.pool?.end();
  }

  async findBySku(
    srCode: string,
    sku: string,
    includeExported: boolean,
  ): Promise<FifoInventoryItem[]> {
    const config = this.getConfig();
    const rows = await this.queryItems(
      `
      SELECT ${this.selectList(config.columns)}
      FROM ${config.table}
      WHERE UPPER(${config.columns.srCode}) = UPPER($1)
        AND UPPER(${config.columns.sku}) = UPPER($2)
        ${includeExported ? '' : `AND COALESCE(${config.columns.exported}, false) = false`}
      ORDER BY ${config.columns.importDate} ASC NULLS LAST, ${config.columns.id} ASC
      `,
      [srCode, sku],
    );
    return rows;
  }

  async findBySerial(
    srCode: string,
    serial: string,
    includeExported = true,
  ): Promise<FifoInventoryItem | null> {
    const config = this.getConfig();
    const rows = await this.queryItems(
      `
      SELECT ${this.selectList(config.columns)}
      FROM ${config.table}
      WHERE UPPER(${config.columns.srCode}) = UPPER($1)
        AND UPPER(${config.columns.serialNumber}) = UPPER($2)
        ${includeExported ? '' : `AND COALESCE(${config.columns.exported}, false) = false`}
      ORDER BY ${config.columns.importDate} ASC NULLS LAST, ${config.columns.id} ASC
      LIMIT 1
      `,
      [srCode, serial],
    );
    return rows[0] ?? null;
  }

  async findByBin(
    srCode: string,
    bin: string,
    includeExported: boolean,
  ): Promise<FifoInventoryItem[]> {
    const config = this.getConfig();
    const rows = await this.queryItems(
      `
      SELECT ${this.selectList(config.columns)}
      FROM ${config.table}
      WHERE UPPER(${config.columns.srCode}) = UPPER($1)
        AND UPPER(${config.columns.bin}) LIKE UPPER($2)
        ${includeExported ? '' : `AND COALESCE(${config.columns.exported}, false) = false`}
      ORDER BY ${config.columns.sku} ASC, ${config.columns.importDate} ASC NULLS LAST, ${config.columns.id} ASC
      `,
      [srCode, `%${bin}%`],
    );
    return rows;
  }

  async findOldestActiveForSku(
    srCode: string,
    sku: string,
  ): Promise<FifoInventoryItem | null> {
    const config = this.getConfig();
    const rows = await this.queryItems(
      `
      SELECT ${this.selectList(config.columns)}
      FROM ${config.table}
      WHERE UPPER(${config.columns.srCode}) = UPPER($1)
        AND UPPER(${config.columns.sku}) = UPPER($2)
        AND COALESCE(${config.columns.exported}, false) = false
      ORDER BY ${config.columns.importDate} ASC NULLS LAST, ${config.columns.id} ASC
      LIMIT 1
      `,
      [srCode, sku],
    );
    return rows[0] ?? null;
  }

  async setExported(
    srCode: string,
    inventoryId: string,
    exported: boolean,
  ): Promise<FifoInventoryItem | null> {
    const config = this.getConfig();
    const rows = await this.queryItems(
      `
      UPDATE ${config.table}
      SET ${config.columns.exported} = $3
      WHERE ${config.columns.id}::text = $1
        AND UPPER(${config.columns.srCode}) = UPPER($2)
      RETURNING ${this.selectList(config.columns)}
      `,
      [inventoryId, srCode, exported],
    );
    return rows[0] ?? null;
  }

  private async queryItems(
    query: string,
    params: Array<string | boolean>,
  ): Promise<FifoInventoryItem[]> {
    const result = await this.getPool().query(query, params);
    return result.rows.map((row: Record<string, unknown>) => ({
      id: String(row.id ?? ''),
      srCode: String(row.srCode ?? ''),
      sku: String(row.sku ?? ''),
      skuName: String(row.skuName ?? ''),
      serialNumber: row.serialNumber ? String(row.serialNumber) : null,
      bin: row.bin ? String(row.bin) : null,
      zone: row.zone ? String(row.zone) : null,
      importDate: row.importDate ? new Date(String(row.importDate)) : null,
      count: Number(row.count ?? 1),
      exported: Boolean(row.exported),
    }));
  }

  private selectList(columns: InventoryColumns) {
    return [
      `${columns.id}::text AS "id"`,
      `${columns.srCode}::text AS "srCode"`,
      `${columns.sku}::text AS "sku"`,
      `${columns.skuName}::text AS "skuName"`,
      `${columns.serialNumber}::text AS "serialNumber"`,
      `${columns.bin}::text AS "bin"`,
      `${columns.zone}::text AS "zone"`,
      `${columns.importDate} AS "importDate"`,
      `${columns.count}::integer AS "count"`,
      `COALESCE(${columns.exported}, false) AS "exported"`,
    ].join(', ');
  }

  private getPool() {
    if (this.pool) return this.pool;

    const connectionString = process.env.PRICE_WATCHDOG_DATABASE_URL?.trim();
    if (!connectionString) {
      throw new InternalServerErrorException(
        'PRICE_WATCHDOG_DATABASE_URL is not configured',
      );
    }

    this.pool = new pg.Pool({ connectionString });
    return this.pool;
  }

  private getConfig() {
    const table = this.identifier(
      process.env.PRICE_WATCHDOG_INVENTORY_TABLE || 'inventory',
      'PRICE_WATCHDOG_INVENTORY_TABLE',
    );
    const columns: InventoryColumns = {
      id: this.column('ID_COLUMN', DEFAULT_COLUMNS.id),
      srCode: this.column('SR_COLUMN', DEFAULT_COLUMNS.srCode),
      sku: this.column('SKU_COLUMN', DEFAULT_COLUMNS.sku),
      skuName: this.column('SKU_NAME_COLUMN', DEFAULT_COLUMNS.skuName),
      serialNumber: this.column('SERIAL_COLUMN', DEFAULT_COLUMNS.serialNumber),
      bin: this.column('BIN_COLUMN', DEFAULT_COLUMNS.bin),
      zone: this.column('ZONE_COLUMN', DEFAULT_COLUMNS.zone),
      importDate: this.column('IMPORT_DATE_COLUMN', DEFAULT_COLUMNS.importDate),
      count: this.column('COUNT_COLUMN', DEFAULT_COLUMNS.count),
      exported: this.column('EXPORTED_COLUMN', DEFAULT_COLUMNS.exported),
    };
    return { table, columns };
  }

  private column(suffix: string, fallback: string) {
    return this.identifier(
      process.env[`PRICE_WATCHDOG_INVENTORY_${suffix}`] || fallback,
      `PRICE_WATCHDOG_INVENTORY_${suffix}`,
    );
  }

  private identifier(value: string, envName: string) {
    const parts = value
      .split('.')
      .map((part) => part.trim())
      .filter(Boolean);
    if (
      parts.length === 0 ||
      parts.some((part) => !/^[A-Za-z_][A-Za-z0-9_]*$/.test(part))
    ) {
      throw new InternalServerErrorException(`Invalid ${envName}`);
    }
    return parts.map((part) => `"${part}"`).join('.');
  }
}
