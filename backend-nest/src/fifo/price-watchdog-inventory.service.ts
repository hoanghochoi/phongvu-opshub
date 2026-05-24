import {
  Injectable,
  InternalServerErrorException,
  Logger,
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
  active: string;
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
  active: 'active',
};

export type ManualInventoryItem = {
  id: string;
  srCode: string;
  srName: string | null;
  sku: string;
  skuName: string;
  serialNumber: string | null;
  serialType: string | null;
  serialTypeChangedAt: Date | null;
  brand: string | null;
  categoryId: string | null;
  categoryName: string | null;
  subcategoryId: string | null;
  subcategoryName: string | null;
  partNumber: string | null;
  unit: string | null;
  bin: string | null;
  binName: string | null;
  zone: string | null;
  binType: string | null;
  importDate: Date | null;
  count: number;
  stockType: string | null;
  purchaseStatus: string | null;
};

export type ManualInventoryImportResult = {
  importedRows: number;
  deactivatedRows: number;
  srCodes: string[];
};

@Injectable()
export class PriceWatchdogInventoryService implements OnModuleDestroy {
  private readonly logger = new Logger(PriceWatchdogInventoryService.name);
  private pool?: pg.Pool;
  private schemaReady?: Promise<void>;

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
        AND COALESCE(${config.columns.active}, true) = true
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
        AND COALESCE(${config.columns.active}, true) = true
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
        AND COALESCE(${config.columns.active}, true) = true
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
        AND COALESCE(${config.columns.active}, true) = true
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

  async importManualInventory(
    items: ManualInventoryItem[],
  ): Promise<ManualInventoryImportResult> {
    const config = this.getConfig();
    await this.ensureSchema(config);

    const srCodes = Array.from(
      new Set(items.map((item) => item.srCode)),
    ).sort();
    const importedIds = Array.from(new Set(items.map((item) => item.id)));
    const client = await this.getPool().connect();

    try {
      await client.query('BEGIN');
      for (let index = 0; index < items.length; index += 500) {
        await this.upsertManualInventoryChunk(
          client,
          config,
          items.slice(index, index + 500),
        );
      }

      let deactivatedRows = 0;
      for (const srCode of srCodes) {
        const result = await client.query(
          `
          UPDATE ${config.table}
          SET ${config.columns.active} = false,
              updated_at = now()
          WHERE UPPER(${config.columns.srCode}) = UPPER($1)
            AND NOT (${config.columns.id}::text = ANY($2::text[]))
            AND COALESCE(${config.columns.active}, true) = true
          `,
          [srCode, importedIds],
        );
        deactivatedRows += result.rowCount ?? 0;
      }

      await client.query('COMMIT');
      this.logger.log(
        `Manual inventory import succeeded: imported=${items.length} deactivated=${deactivatedRows} sr=${srCodes.join(',')}`,
      );
      return { importedRows: items.length, deactivatedRows, srCodes };
    } catch (error) {
      await client.query('ROLLBACK');
      this.logger.error('Manual inventory import failed', error);
      throw error;
    } finally {
      client.release();
    }
  }

  private async queryItems(
    query: string,
    params: Array<string | boolean>,
  ): Promise<FifoInventoryItem[]> {
    await this.ensureSchema(this.getConfig());
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

  private async upsertManualInventoryChunk(
    client: pg.PoolClient,
    config: ReturnType<PriceWatchdogInventoryService['getConfig']>,
    items: ManualInventoryItem[],
  ) {
    if (items.length === 0) return;

    const values: unknown[] = [];
    const placeholders = items.map((item, index) => {
      const base = index * 23;
      values.push(
        item.id,
        item.srCode,
        item.srName,
        item.sku,
        item.skuName,
        item.serialNumber,
        item.serialType,
        item.serialTypeChangedAt,
        item.brand,
        item.categoryId,
        item.categoryName,
        item.subcategoryId,
        item.subcategoryName,
        item.partNumber,
        item.unit,
        item.bin,
        item.binName,
        item.zone,
        item.binType,
        item.importDate,
        item.count,
        item.stockType,
        item.purchaseStatus,
      );
      return `(${Array.from({ length: 23 }, (_, offset) => `$${base + offset + 1}`).join(', ')}, 'manual', now(), true, now())`;
    });

    await client.query(
      `
      INSERT INTO ${config.table} (
        ${config.columns.id},
        ${config.columns.srCode},
        sr_name,
        ${config.columns.sku},
        ${config.columns.skuName},
        ${config.columns.serialNumber},
        serial_type,
        serial_type_changed_at,
        brand,
        category_id,
        category_name,
        subcategory_id,
        subcategory_name,
        part_number,
        unit,
        ${config.columns.bin},
        bin_name,
        ${config.columns.zone},
        bin_type,
        ${config.columns.importDate},
        ${config.columns.count},
        stock_type,
        purchase_status,
        source,
        source_updated_at,
        ${config.columns.active},
        updated_at
      )
      VALUES ${placeholders.join(', ')}
      ON CONFLICT (${config.columns.id}) DO UPDATE SET
        ${config.columns.srCode} = EXCLUDED.${config.columns.srCode},
        sr_name = EXCLUDED.sr_name,
        ${config.columns.sku} = EXCLUDED.${config.columns.sku},
        ${config.columns.skuName} = EXCLUDED.${config.columns.skuName},
        ${config.columns.serialNumber} = EXCLUDED.${config.columns.serialNumber},
        serial_type = EXCLUDED.serial_type,
        serial_type_changed_at = EXCLUDED.serial_type_changed_at,
        brand = EXCLUDED.brand,
        category_id = EXCLUDED.category_id,
        category_name = EXCLUDED.category_name,
        subcategory_id = EXCLUDED.subcategory_id,
        subcategory_name = EXCLUDED.subcategory_name,
        part_number = EXCLUDED.part_number,
        unit = EXCLUDED.unit,
        ${config.columns.bin} = EXCLUDED.${config.columns.bin},
        bin_name = EXCLUDED.bin_name,
        ${config.columns.zone} = EXCLUDED.${config.columns.zone},
        bin_type = EXCLUDED.bin_type,
        ${config.columns.importDate} = EXCLUDED.${config.columns.importDate},
        ${config.columns.count} = EXCLUDED.${config.columns.count},
        stock_type = EXCLUDED.stock_type,
        purchase_status = EXCLUDED.purchase_status,
        source = EXCLUDED.source,
        source_updated_at = EXCLUDED.source_updated_at,
        ${config.columns.active} = true,
        updated_at = now()
      `,
      values,
    );
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
      active: this.column('ACTIVE_COLUMN', DEFAULT_COLUMNS.active),
    };
    return { table, columns };
  }

  private async ensureSchema(
    config: ReturnType<PriceWatchdogInventoryService['getConfig']>,
  ) {
    if (!this.schemaReady) {
      this.schemaReady = this.createSchema(config);
    }
    return this.schemaReady;
  }

  private async createSchema(
    config: ReturnType<PriceWatchdogInventoryService['getConfig']>,
  ) {
    const pool = this.getPool();
    await pool.query(`
      CREATE TABLE IF NOT EXISTS ${config.table} (
        ${config.columns.id} text PRIMARY KEY,
        ${config.columns.srCode} text NOT NULL,
        sr_name text,
        ${config.columns.sku} text NOT NULL,
        ${config.columns.skuName} text NOT NULL DEFAULT '',
        ${config.columns.serialNumber} text,
        serial_type text,
        serial_type_changed_at timestamptz,
        brand text,
        category_id text,
        category_name text,
        subcategory_id text,
        subcategory_name text,
        part_number text,
        unit text,
        ${config.columns.bin} text,
        bin_name text,
        ${config.columns.zone} text,
        bin_type text,
        ${config.columns.importDate} timestamptz,
        ${config.columns.count} integer NOT NULL DEFAULT 1,
        stock_type text,
        purchase_status text,
        source text NOT NULL DEFAULT 'manual',
        source_updated_at timestamptz,
        ${config.columns.exported} boolean NOT NULL DEFAULT false,
        ${config.columns.active} boolean NOT NULL DEFAULT true,
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
      )
    `);
    await pool.query(
      `ALTER TABLE ${config.table} ADD COLUMN IF NOT EXISTS ${config.columns.exported} boolean NOT NULL DEFAULT false`,
    );
    await pool.query(
      `ALTER TABLE ${config.table} ADD COLUMN IF NOT EXISTS ${config.columns.active} boolean NOT NULL DEFAULT true`,
    );
    await pool.query(
      `ALTER TABLE ${config.table} ADD COLUMN IF NOT EXISTS sr_name text`,
    );
    await pool.query(
      `ALTER TABLE ${config.table} ADD COLUMN IF NOT EXISTS serial_type text`,
    );
    await pool.query(
      `ALTER TABLE ${config.table} ADD COLUMN IF NOT EXISTS serial_type_changed_at timestamptz`,
    );
    await pool.query(
      `ALTER TABLE ${config.table} ADD COLUMN IF NOT EXISTS brand text`,
    );
    await pool.query(
      `ALTER TABLE ${config.table} ADD COLUMN IF NOT EXISTS category_id text`,
    );
    await pool.query(
      `ALTER TABLE ${config.table} ADD COLUMN IF NOT EXISTS category_name text`,
    );
    await pool.query(
      `ALTER TABLE ${config.table} ADD COLUMN IF NOT EXISTS subcategory_id text`,
    );
    await pool.query(
      `ALTER TABLE ${config.table} ADD COLUMN IF NOT EXISTS subcategory_name text`,
    );
    await pool.query(
      `ALTER TABLE ${config.table} ADD COLUMN IF NOT EXISTS part_number text`,
    );
    await pool.query(
      `ALTER TABLE ${config.table} ADD COLUMN IF NOT EXISTS unit text`,
    );
    await pool.query(
      `ALTER TABLE ${config.table} ADD COLUMN IF NOT EXISTS bin_name text`,
    );
    await pool.query(
      `ALTER TABLE ${config.table} ADD COLUMN IF NOT EXISTS bin_type text`,
    );
    await pool.query(
      `ALTER TABLE ${config.table} ADD COLUMN IF NOT EXISTS stock_type text`,
    );
    await pool.query(
      `ALTER TABLE ${config.table} ADD COLUMN IF NOT EXISTS purchase_status text`,
    );
    await pool.query(
      `ALTER TABLE ${config.table} ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'manual'`,
    );
    await pool.query(
      `ALTER TABLE ${config.table} ADD COLUMN IF NOT EXISTS source_updated_at timestamptz`,
    );
    await pool.query(
      `ALTER TABLE ${config.table} ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now()`,
    );
    await pool.query(
      `ALTER TABLE ${config.table} ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now()`,
    );
    await pool.query(
      `CREATE INDEX IF NOT EXISTS inventory_sr_sku_active_exported_import_date_idx ON ${config.table} (${config.columns.srCode}, ${config.columns.sku}, ${config.columns.active}, ${config.columns.exported}, ${config.columns.importDate})`,
    );
    await pool.query(
      `CREATE INDEX IF NOT EXISTS inventory_sr_serial_active_idx ON ${config.table} (${config.columns.srCode}, ${config.columns.serialNumber}, ${config.columns.active})`,
    );
    await pool.query(
      `CREATE INDEX IF NOT EXISTS inventory_sr_bin_active_idx ON ${config.table} (${config.columns.srCode}, ${config.columns.bin}, ${config.columns.active})`,
    );
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
