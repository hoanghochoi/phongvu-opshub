import {
  Injectable,
  InternalServerErrorException,
  Logger,
  OnModuleDestroy,
} from '@nestjs/common';
import { BigQuery } from '@google-cloud/bigquery';
import { Cron } from '@nestjs/schedule';
import pg from 'pg';

export const DISPLAY_RESERVED_BIN_TYPE = 'Hàng trưng bày chỉ định';

export type FifoInventoryItem = {
  id: string;
  srCode: string;
  sku: string;
  skuName: string;
  serialNumber: string | null;
  bin: string | null;
  zone: string | null;
  binType: string | null;
  importDate: Date | null;
  dateImportCompany: Date | null;
  dateImportSite: Date | null;
  count: number;
  exported: boolean;
  source: string | null;
};

export type CanonicalInventoryItem = {
  itemKey: string;
  serial: string | null;
  sku: string;
  skuName: string;
  branchId: string;
  branchName: string | null;
  brand: string | null;
  categoryId: string | null;
  categoryName: string | null;
  subCategoryId: string | null;
  subCategoryName: string | null;
  subcatIdLowestLevel: string | null;
  subcatNameLowestLevel: string | null;
  location: string | null;
  binType: string | null;
  binZone: string | null;
  dateImportCompany: Date | null;
  dateImportSite: Date | null;
  agingCompany: number | null;
  badStockCompany: string | null;
  agingSite: number | null;
  stockDaySite: number | null;
  badStockSite: string | null;
  stockDayCompany: number | null;
  purchaseStatus: string | null;
  inventory: number;
  inventoryAmount: number | null;
  manualPayload?: Record<string, unknown> | null;
};

export type ManualInventoryItem = CanonicalInventoryItem;
export type BigQueryInventoryItem = CanonicalInventoryItem;

export type ManualInventoryImportResult = {
  importedRows: number;
  deactivatedRows: number;
  srCodes: string[];
};

export type BigQueryInventorySyncResult = {
  importedRows: number;
  deactivatedRows: number;
  skippedRows: number;
  srCodes: string[];
};

type FifoTableConfig = {
  table: string;
  columns: Record<string, string>;
};

const TABLE_COLUMNS = [
  ['id', 'text'],
  ['Serial', 'text'],
  ['SKU', 'text'],
  ['SKU_name', 'text'],
  ['Branch_ID', 'text'],
  ['Branch_name', 'text'],
  ['Brand', 'text'],
  ['Category_ID', 'text'],
  ['Category_name', 'text'],
  ['SubCategory_ID', 'text'],
  ['SubCategory_name', 'text'],
  ['Subcat_ID_lowest_level', 'text'],
  ['Subcat_name_lowest_level', 'text'],
  ['Location', 'text'],
  ['BIN_type', 'text'],
  ['BIN_zone', 'text'],
  ['Date_import_company', 'date'],
  ['Aging_company', 'integer'],
  ['Bad_stock_company', 'text'],
  ['Date_import_site', 'date'],
  ['Aging_site', 'integer'],
  ['Stock_day_site', 'integer'],
  ['Bad_stock_site', 'text'],
  ['Stock_day_company', 'integer'],
  ['Purchase_status', 'text'],
  ['Inventory', 'double precision'],
  ['Inventory_amount', 'double precision'],
  ['opshub_item_key', 'text'],
  ['opshub_source', 'text'],
  ['opshub_active', 'boolean'],
  ['opshub_exported', 'boolean'],
  ['opshub_synced_at', 'timestamptz'],
  ['opshub_manual_payload', 'jsonb'],
  ['opshub_created_at', 'timestamptz'],
  ['opshub_updated_at', 'timestamptz'],
  ['sr_code', 'text'],
  ['sku', 'text'],
  ['sku_name', 'text'],
  ['serial_number', 'text'],
  ['bin', 'text'],
  ['zone', 'text'],
  ['import_date', 'date'],
  ['count', 'integer'],
  ['source', 'text'],
  ['active', 'boolean'],
  ['exported', 'boolean'],
] as const;

const UPSERT_COLUMNS = [
  'id',
  'opshub_item_key',
  'Serial',
  'SKU',
  'SKU_name',
  'Branch_ID',
  'Branch_name',
  'Brand',
  'Category_ID',
  'Category_name',
  'SubCategory_ID',
  'SubCategory_name',
  'Subcat_ID_lowest_level',
  'Subcat_name_lowest_level',
  'Location',
  'BIN_type',
  'BIN_zone',
  'Date_import_company',
  'Aging_company',
  'Bad_stock_company',
  'Date_import_site',
  'Aging_site',
  'Stock_day_site',
  'Bad_stock_site',
  'Stock_day_company',
  'Purchase_status',
  'Inventory',
  'Inventory_amount',
  'opshub_source',
  'opshub_active',
  'opshub_manual_payload',
  'sr_code',
  'sku',
  'sku_name',
  'serial_number',
  'bin',
  'zone',
  'import_date',
  'count',
  'source',
  'active',
  'exported',
] as const;

const BIGQUERY_SELECT_COLUMNS = [
  'Serial',
  'SKU',
  'SKU_name',
  'Branch_ID',
  'Branch_name',
  'Brand',
  'Category_ID',
  'Category_name',
  'SubCategory_ID',
  'SubCategory_name',
  'Subcat_ID_lowest_level',
  'Subcat_name_lowest_level',
  'Location',
  'BIN_type',
  'BIN_zone',
  'Date_import_company',
  'Aging_company',
  'Bad_stock_company',
  'Date_import_site',
  'Aging_site',
  'Stock_day_site',
  'Bad_stock_site',
  'Stock_day_company',
  'Purchase_status',
  'Inventory',
  'Inventory_amount',
] as const;

@Injectable()
export class OpshubFifoInventoryService implements OnModuleDestroy {
  private readonly logger = new Logger(OpshubFifoInventoryService.name);
  private pool?: pg.Pool;
  private schemaReady?: Promise<void>;

  async onModuleDestroy() {
    await this.pool?.end();
  }

  @Cron('0 8 * * *', { timeZone: 'Asia/Ho_Chi_Minh' })
  async syncFromBigQuery(): Promise<BigQueryInventorySyncResult> {
    const startedAt = Date.now();
    const bigQuery = this.createBigQueryClient();
    if (!bigQuery) {
      this.logger.warn(
        'FIFO BigQuery sync skipped: BIGQUERY_PROJECT_ID / dataset / table is not configured',
      );
      return { importedRows: 0, deactivatedRows: 0, skippedRows: 0, srCodes: [] };
    }

    const { client, tablePath } = bigQuery;
    this.logger.log(`FIFO BigQuery sync started: table=${tablePath}`);

    try {
      const [rows] = await client.query({
        query: `SELECT ${BIGQUERY_SELECT_COLUMNS.map((column) => `\`${column}\``).join(', ')} FROM \`${tablePath}\``,
      });
      const mapped = this.mapBigQueryRows(rows as Array<Record<string, unknown>>);
      if (mapped.items.length === 0) {
        this.logger.warn(
          `FIFO BigQuery sync skipped deactivation because no valid rows were mapped: fetched=${rows.length} skipped=${mapped.skippedRows}`,
        );
        return {
          importedRows: 0,
          deactivatedRows: 0,
          skippedRows: mapped.skippedRows,
          srCodes: [],
        };
      }

      const result = await this.importBigQueryInventory(mapped.items);
      this.logger.log(
        `FIFO BigQuery sync succeeded: fetched=${rows.length} imported=${result.importedRows} deactivated=${result.deactivatedRows} skipped=${mapped.skippedRows} sr=${result.srCodes.join(',')} durationMs=${Date.now() - startedAt}`,
      );
      return { ...result, skippedRows: mapped.skippedRows };
    } catch (error) {
      this.logger.error(
        `FIFO BigQuery sync failed: table=${tablePath} durationMs=${Date.now() - startedAt} error=${errorMessage(error)}`,
      );
      throw error;
    }
  }

  async findBySku(
    srCode: string,
    sku: string,
    includeExported: boolean,
  ): Promise<FifoInventoryItem[]> {
    const config = this.getConfig();
    return this.queryItems(
      `
      SELECT ${this.selectList(config.columns)}
      FROM ${config.table}
      WHERE UPPER(${config.columns.Branch_ID}) = UPPER($1)
        AND UPPER(${config.columns.SKU}) = UPPER($2)
        ${this.activeFifoWhere(config, includeExported)}
      ${this.fifoOrderBy(config)}
      `,
      [srCode, sku],
    );
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
      WHERE UPPER(${config.columns.Branch_ID}) = UPPER($1)
        AND UPPER(${config.columns.Serial}) = UPPER($2)
        AND COALESCE(${config.columns.opshub_active}, true) = true
        AND COALESCE(${config.columns.Inventory}, 0) > 0
        ${includeExported ? '' : `AND COALESCE(${config.columns.opshub_exported}, false) = false`}
      ${this.fifoOrderBy(config)}
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
    return this.queryItems(
      `
      SELECT ${this.selectList(config.columns)}
      FROM ${config.table}
      WHERE UPPER(${config.columns.Branch_ID}) = UPPER($1)
        AND (
          UPPER(${config.columns.Location}) LIKE UPPER($2)
          OR UPPER(${config.columns.BIN_zone}) LIKE UPPER($2)
        )
        ${this.activeFifoWhere(config, includeExported)}
      ORDER BY ${config.columns.SKU} ASC, COALESCE(${config.columns.Date_import_company}, ${config.columns.Date_import_site}) ASC NULLS LAST, ${config.columns.Serial} ASC NULLS LAST, ${config.columns.opshub_item_key} ASC
      `,
      [srCode, `%${bin}%`],
    );
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
      WHERE UPPER(${config.columns.Branch_ID}) = UPPER($1)
        AND UPPER(${config.columns.SKU}) = UPPER($2)
        ${this.activeFifoWhere(config, false)}
      ${this.fifoOrderBy(config)}
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
      SET ${config.columns.opshub_exported} = $3,
          ${config.columns.opshub_updated_at} = now()
      WHERE ${config.columns.opshub_item_key}::text = $1
        AND UPPER(${config.columns.Branch_ID}) = UPPER($2)
      RETURNING ${this.selectList(config.columns)}
      `,
      [inventoryId, srCode, exported],
    );
    return rows[0] ?? null;
  }

  async importManualInventory(
    items: ManualInventoryItem[],
  ): Promise<ManualInventoryImportResult> {
    const result = await this.importInventoryItems(items, 'manual', false);
    this.logger.log(
      `Manual inventory import succeeded: imported=${result.importedRows} deactivated=0 sr=${result.srCodes.join(',')}`,
    );
    return result;
  }

  async importBigQueryInventory(
    items: BigQueryInventoryItem[],
  ): Promise<Omit<BigQueryInventorySyncResult, 'skippedRows'>> {
    return this.importInventoryItems(items, 'bigquery', true);
  }

  private async importInventoryItems(
    items: CanonicalInventoryItem[],
    source: 'manual' | 'bigquery',
    deactivateMissingBigQueryRows: boolean,
  ): Promise<Omit<BigQueryInventorySyncResult, 'skippedRows'>> {
    const config = this.getConfig();
    await this.ensureSchema(config);

    const srCodes = Array.from(new Set(items.map((item) => item.branchId))).sort();
    const importedIds = Array.from(new Set(items.map((item) => item.itemKey)));
    const client = await this.getPool().connect();

    try {
      await client.query('BEGIN');
      for (let index = 0; index < items.length; index += 500) {
        await this.upsertInventoryChunk(
          client,
          config,
          items.slice(index, index + 500),
          source,
        );
      }

      let deactivatedRows = 0;
      if (deactivateMissingBigQueryRows) {
        for (const srCode of srCodes) {
          const result = await client.query(
            `
            UPDATE ${config.table}
            SET ${config.columns.opshub_active} = false,
                ${config.columns.opshub_updated_at} = now()
            WHERE UPPER(${config.columns.Branch_ID}) = UPPER($1)
              AND ${config.columns.opshub_source} = 'bigquery'
              AND NOT (${config.columns.opshub_item_key}::text = ANY($2::text[]))
              AND COALESCE(${config.columns.opshub_active}, true) = true
            `,
            [srCode, importedIds],
          );
          deactivatedRows += result.rowCount ?? 0;
        }
      }

      await client.query('COMMIT');
      return { importedRows: items.length, deactivatedRows, srCodes };
    } catch (error) {
      await client.query('ROLLBACK');
      this.logger.error(
        `FIFO ${source} inventory import failed: error=${errorMessage(error)}`,
      );
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
      binType: row.binType ? String(row.binType) : null,
      importDate: row.importDate ? new Date(String(row.importDate)) : null,
      dateImportCompany: row.dateImportCompany
        ? new Date(String(row.dateImportCompany))
        : null,
      dateImportSite: row.dateImportSite
        ? new Date(String(row.dateImportSite))
        : null,
      count: Number(row.count ?? 1),
      exported: Boolean(row.exported),
      source: row.source ? String(row.source) : null,
    }));
  }

  private async upsertInventoryChunk(
    client: pg.PoolClient,
    config: FifoTableConfig,
    items: CanonicalInventoryItem[],
    source: 'manual' | 'bigquery',
  ) {
    if (items.length === 0) return;

    const values: unknown[] = [];
    const placeholders = items.map((item, index) => {
      const base = index * UPSERT_COLUMNS.length;
      values.push(
        item.itemKey,
        item.itemKey,
        item.serial,
        item.sku,
        item.skuName,
        item.branchId,
        item.branchName,
        item.brand,
        item.categoryId,
        item.categoryName,
        item.subCategoryId,
        item.subCategoryName,
        item.subcatIdLowestLevel,
        item.subcatNameLowestLevel,
        item.location,
        item.binType,
        item.binZone,
        item.dateImportCompany,
        item.agingCompany,
        item.badStockCompany,
        item.dateImportSite,
        item.agingSite,
        item.stockDaySite,
        item.badStockSite,
        item.stockDayCompany,
        item.purchaseStatus,
        item.inventory,
        item.inventoryAmount,
        source,
        item.inventory > 0,
        item.manualPayload ? JSON.stringify(item.manualPayload) : null,
        item.branchId,
        item.sku,
        item.skuName,
        item.serial,
        item.location,
        item.binZone,
        item.dateImportCompany ?? item.dateImportSite,
        Math.max(1, Math.round(item.inventory)),
        source,
        item.inventory > 0,
        false,
      );
      return `(${Array.from(
        { length: UPSERT_COLUMNS.length },
        (_, offset) => `$${base + offset + 1}`,
      ).join(', ')}, false, now(), now(), now())`;
    });

    const updateColumns = UPSERT_COLUMNS.filter(
      (column) => column !== 'id' && column !== 'opshub_item_key',
    );
    const updates = updateColumns
      .map((column) => `${config.columns[column]} = EXCLUDED.${config.columns[column]}`)
      .concat([
        `${config.columns.opshub_exported} = COALESCE(target.${config.columns.opshub_exported}, false)`,
        `${config.columns.exported} = COALESCE(target.${config.columns.exported}, false)`,
        `${config.columns.opshub_synced_at} = now()`,
        `${config.columns.opshub_updated_at} = now()`,
      ]);

    await client.query(
      `
      INSERT INTO ${config.table} AS target (
        ${UPSERT_COLUMNS.map((column) => config.columns[column]).join(', ')},
        ${config.columns.opshub_exported},
        ${config.columns.opshub_synced_at},
        ${config.columns.opshub_created_at},
        ${config.columns.opshub_updated_at}
      )
      VALUES ${placeholders.join(', ')}
      ON CONFLICT (${config.columns.opshub_item_key}) DO UPDATE SET
        ${updates.join(',\n        ')}
      `,
      values,
    );
  }

  private createBigQueryClient() {
    const projectId = firstEnvValue([
      'BIGQUERY_PROJECT_ID',
      'PRICE_WATCHDOG_BIGQUERY_PROJECT_ID',
    ]);
    const datasetId =
      firstEnvValue(['BIGQUERY_FIFO_DATASET_ID', 'BIGQUERY_DATASET_ID']) ||
      firstEnvValue(['PRICE_WATCHDOG_BIGQUERY_DATASET']);
    const tableId =
      firstEnvValue(['BIGQUERY_FIFO_TABLE_ID', 'BIGQUERY_TABLE_ID']) ||
      firstEnvValue(['PRICE_WATCHDOG_BIGQUERY_TABLE']);
    if (!projectId || !datasetId || !tableId) return null;

    const keyFilename = firstEnvValue([
      'BIGQUERY_KEY_FILE',
      'GOOGLE_APPLICATION_CREDENTIALS',
    ]);
    return {
      client: new BigQuery({
        projectId,
        ...(keyFilename ? { keyFilename } : {}),
      }),
      tablePath: `${projectId}.${datasetId}.${tableId}`,
    };
  }

  private mapBigQueryRows(rows: Array<Record<string, unknown>>) {
    const byId = new Map<string, BigQueryInventoryItem>();
    let skippedRows = 0;

    rows.forEach((row, index) => {
      const item = rowToCanonicalItem(row, index + 1, 'bigquery');
      if (!item) {
        skippedRows += 1;
        return;
      }
      byId.set(item.itemKey, item);
    });

    return { items: Array.from(byId.values()), skippedRows };
  }

  private selectList(columns: Record<string, string>) {
    return [
      `${columns.opshub_item_key}::text AS "id"`,
      `${columns.Branch_ID}::text AS "srCode"`,
      `${columns.SKU}::text AS "sku"`,
      `${columns.SKU_name}::text AS "skuName"`,
      `${columns.Serial}::text AS "serialNumber"`,
      `${columns.Location}::text AS "bin"`,
      `${columns.BIN_zone}::text AS "zone"`,
      `${columns.BIN_type}::text AS "binType"`,
      `${columns.Date_import_company} AS "dateImportCompany"`,
      `${columns.Date_import_site} AS "dateImportSite"`,
      `COALESCE(${columns.Date_import_company}, ${columns.Date_import_site}) AS "importDate"`,
      `COALESCE(${columns.Inventory}, 0)::integer AS "count"`,
      `COALESCE(${columns.opshub_exported}, false) AS "exported"`,
      `${columns.opshub_source}::text AS "source"`,
    ].join(', ');
  }

  private activeFifoWhere(config: FifoTableConfig, includeExported: boolean) {
    return `
        AND COALESCE(${config.columns.opshub_active}, true) = true
        AND COALESCE(${config.columns.Inventory}, 0) > 0
        AND COALESCE(${config.columns.BIN_type}, '') <> '${DISPLAY_RESERVED_BIN_TYPE.replace(/'/g, "''")}'
        ${includeExported ? '' : `AND COALESCE(${config.columns.opshub_exported}, false) = false`}
    `;
  }

  private fifoOrderBy(config: FifoTableConfig) {
    return `ORDER BY COALESCE(${config.columns.Date_import_company}, ${config.columns.Date_import_site}) ASC NULLS LAST, ${config.columns.Serial} ASC NULLS LAST, ${config.columns.opshub_item_key} ASC`;
  }

  private getPool() {
    if (this.pool) return this.pool;

    const connectionString =
      process.env.OPSHUB_FIFO_DATABASE_URL?.trim() ||
      process.env.DATABASE_URL?.trim();
    if (!connectionString) {
      throw new InternalServerErrorException(
        'DATABASE_URL is not configured for FIFO inventory',
      );
    }

    this.pool = new pg.Pool({ connectionString });
    return this.pool;
  }

  private getConfig(): FifoTableConfig {
    const table = this.identifier(
      process.env.OPSHUB_FIFO_INVENTORY_TABLE || 'fifo_inventory',
      'OPSHUB_FIFO_INVENTORY_TABLE',
    );
    const columns = Object.fromEntries(
      TABLE_COLUMNS.map(([column]) => [column, this.identifier(column, column)]),
    );
    return { table, columns };
  }

  private async ensureSchema(config: FifoTableConfig) {
    if (!this.schemaReady) {
      this.schemaReady = this.createSchema(config);
    }
    return this.schemaReady;
  }

  private async createSchema(config: FifoTableConfig) {
    const pool = this.getPool();
    await pool.query(`
      CREATE TABLE IF NOT EXISTS ${config.table} (
        ${config.columns.id} text PRIMARY KEY,
        ${config.columns.opshub_item_key} text UNIQUE,
        ${config.columns.Serial} text,
        ${config.columns.SKU} text,
        ${config.columns.SKU_name} text,
        ${config.columns.Branch_ID} text,
        ${config.columns.Branch_name} text,
        ${config.columns.Brand} text,
        ${config.columns.Category_ID} text,
        ${config.columns.Category_name} text,
        ${config.columns.SubCategory_ID} text,
        ${config.columns.SubCategory_name} text,
        ${config.columns.Subcat_ID_lowest_level} text,
        ${config.columns.Subcat_name_lowest_level} text,
        ${config.columns.Location} text,
        ${config.columns.BIN_type} text,
        ${config.columns.BIN_zone} text,
        ${config.columns.Date_import_company} date,
        ${config.columns.Aging_company} integer,
        ${config.columns.Bad_stock_company} text,
        ${config.columns.Date_import_site} date,
        ${config.columns.Aging_site} integer,
        ${config.columns.Stock_day_site} integer,
        ${config.columns.Bad_stock_site} text,
        ${config.columns.Stock_day_company} integer,
        ${config.columns.Purchase_status} text,
        ${config.columns.Inventory} double precision NOT NULL DEFAULT 0,
        ${config.columns.Inventory_amount} double precision,
        ${config.columns.opshub_source} text NOT NULL DEFAULT 'manual',
        ${config.columns.opshub_active} boolean NOT NULL DEFAULT true,
        ${config.columns.opshub_exported} boolean NOT NULL DEFAULT false,
        ${config.columns.opshub_synced_at} timestamptz,
        ${config.columns.opshub_manual_payload} jsonb,
        ${config.columns.opshub_created_at} timestamptz NOT NULL DEFAULT now(),
        ${config.columns.opshub_updated_at} timestamptz NOT NULL DEFAULT now()
      )
    `);

    for (const [column, type] of TABLE_COLUMNS) {
      const defaultClause = column === 'Inventory' ? ' NOT NULL DEFAULT 0' : '';
      await pool.query(
        `ALTER TABLE ${config.table} ADD COLUMN IF NOT EXISTS ${config.columns[column]} ${type}${defaultClause}`,
      );
    }

    await pool.query(
      `CREATE UNIQUE INDEX IF NOT EXISTS fifo_inventory_opshub_item_key_uidx ON ${config.table} (${config.columns.opshub_item_key})`,
    );
    await pool.query(
      `CREATE INDEX IF NOT EXISTS fifo_inventory_branch_sku_active_fifo_date_idx ON ${config.table} (${config.columns.Branch_ID}, ${config.columns.SKU}, ${config.columns.opshub_active}, ${config.columns.opshub_exported}, ${config.columns.Date_import_company}, ${config.columns.Date_import_site})`,
    );
    await pool.query(
      `CREATE INDEX IF NOT EXISTS fifo_inventory_branch_serial_active_idx ON ${config.table} (${config.columns.Branch_ID}, ${config.columns.Serial}, ${config.columns.opshub_active})`,
    );
    await pool.query(
      `CREATE INDEX IF NOT EXISTS fifo_inventory_branch_location_active_idx ON ${config.table} (${config.columns.Branch_ID}, ${config.columns.Location}, ${config.columns.opshub_active})`,
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

export function rowToCanonicalItem(
  row: Record<string, unknown>,
  rowNumber: number,
  source: 'manual' | 'bigquery',
): CanonicalInventoryItem | null {
  const sku = readText(row, ['SKU', 'Mã sản phẩm']);
  const branchId = readText(row, ['Branch_ID', 'Mã chi nhánh']).toUpperCase();
  if (!sku || !branchId) return null;

  const serial = readText(row, ['Serial', 'Số Serial']) || null;
  const location = readText(row, ['Location', 'Mã Bin']) || null;
  const binZone = readText(row, ['BIN_zone', 'Zone']) || null;
  const itemKey = serial
    ? `${branchId}:${serial.toUpperCase()}`
    : `${branchId}:${sku}:${location || binZone || 'NO_LOCATION'}:${rowNumber}`;

  return {
    itemKey,
    serial,
    sku,
    skuName: readText(row, ['SKU_name', 'Tên sản phẩm']),
    branchId,
    branchName: readText(row, ['Branch_name', 'Tên chi nhánh']) || null,
    brand: readText(row, ['Brand', 'Thương hiệu']) || null,
    categoryId: readText(row, ['Category_ID', 'Mã ngành hàng']) || null,
    categoryName: readText(row, ['Category_name', 'Tên ngành hàng']) || null,
    subCategoryId: readText(row, ['SubCategory_ID', 'Mã nhóm sản phẩm']) || null,
    subCategoryName:
      readText(row, ['SubCategory_name', 'Tên nhóm sản phẩm']) || null,
    subcatIdLowestLevel: readText(row, ['Subcat_ID_lowest_level']) || null,
    subcatNameLowestLevel:
      readText(row, ['Subcat_name_lowest_level']) || null,
    location,
    binType: normalizeBinType(readText(row, ['BIN_type', 'Loại hàng'])) || null,
    binZone,
    dateImportCompany: parseInventoryDate(readRaw(row, ['Date_import_company'])),
    dateImportSite: parseInventoryDate(
      readRaw(row, ['Date_import_site', 'Ngày nhập kho']),
    ),
    agingCompany: parseNullableInteger(readRaw(row, ['Aging_company'])),
    badStockCompany: readText(row, ['Bad_stock_company']) || null,
    agingSite: parseNullableInteger(readRaw(row, ['Aging_site'])),
    stockDaySite: parseNullableInteger(readRaw(row, ['Stock_day_site'])),
    badStockSite: readText(row, ['Bad_stock_site']) || null,
    stockDayCompany: parseNullableInteger(readRaw(row, ['Stock_day_company'])),
    purchaseStatus: readText(row, ['Purchase_status']) || null,
    inventory: parseInventoryNumber(readRaw(row, ['Inventory', 'Số lượng']), 1),
    inventoryAmount: parseNullableNumber(readRaw(row, ['Inventory_amount'])),
    manualPayload: source === 'manual' ? buildManualPayload(row) : null,
  };
}

function buildManualPayload(row: Record<string, unknown>) {
  return {
    part_number: readText(row, ['Part number']) || null,
    unit: readText(row, ['ĐVT']) || null,
    serial_type: readText(row, ['Loại Serial']) || null,
    serial_type_changed_at:
      readText(row, ['Ngày đánh dấu chuyển loại Serial']) || null,
    bin_name: readText(row, ['Tên Bin']) || null,
    product_volume: readText(row, ['Tổng thể tích sản phẩm']) || null,
    bin_volume: readText(row, ['Thể tích Bin']) || null,
  };
}

function readRaw(row: Record<string, unknown>, keys: string[]) {
  for (const key of keys) {
    if (row[key] !== undefined && row[key] !== null) return row[key];
  }
  return undefined;
}

function readText(row: Record<string, unknown>, keys: string[]) {
  const value = readRaw(row, keys);
  if (value === undefined || value === null) return '';
  if (value instanceof Date) return value.toISOString().trim();
  if (typeof value === 'object' && 'value' in value) {
    return String((value as { value?: unknown }).value ?? '').trim();
  }
  return String(value).trim();
}

function normalizeBinType(value: string) {
  const text = value.trim();
  if (!text) return '';
  if (text === 'Hàng bán') return 'Hàng bán mới tại kho';
  return text;
}

function parseInventoryNumber(value: unknown, fallback: number) {
  const parsed = parseNullableNumber(value);
  return parsed === null ? fallback : parsed;
}

function parseNullableNumber(value: unknown) {
  if (value === undefined || value === null || value === '') return null;
  if (typeof value === 'object' && 'value' in value) {
    return parseNullableNumber((value as { value?: unknown }).value);
  }
  const count = Number(String(value).trim().replace(',', '.'));
  return Number.isFinite(count) ? count : null;
}

function parseNullableInteger(value: unknown) {
  const parsed = parseNullableNumber(value);
  return parsed === null ? null : Math.round(parsed);
}

function parseInventoryDate(value: unknown) {
  if (value === undefined || value === null || value === '') return null;
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value;
  if (typeof value === 'object' && 'value' in value) {
    return parseInventoryDate((value as { value?: unknown }).value);
  }

  const text = String(value).trim();
  if (!text) return null;
  const formulaNumber = /^=\s*([0-9]+(?:\.[0-9]+)?)/.exec(text);
  if (formulaNumber) return excelSerialToDate(Number(formulaNumber[1]));

  const numeric = Number(text);
  if (Number.isFinite(numeric) && numeric > 20_000 && numeric < 80_000) {
    return excelSerialToDate(numeric);
  }

  const ddmmyyyy = /^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})$/.exec(text);
  if (ddmmyyyy) {
    const day = Number(ddmmyyyy[1]);
    const month = Number(ddmmyyyy[2]) - 1;
    const year =
      ddmmyyyy[3].length === 2
        ? 2000 + Number(ddmmyyyy[3])
        : Number(ddmmyyyy[3]);
    return new Date(Date.UTC(year, month, day));
  }

  const parsed = new Date(text);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function excelSerialToDate(serial: number) {
  const epoch = Date.UTC(1899, 11, 30);
  return new Date(epoch + Math.floor(serial) * 86_400_000);
}

function firstEnvValue(keys: string[]) {
  for (const key of keys) {
    const value = process.env[key]?.trim();
    if (value) return value;
  }
  return '';
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error);
}
