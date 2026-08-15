import { spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import { PrismaPg } from '@prisma/adapter-pg';
import { Prisma, PrismaClient } from '@prisma/client';
import pg from 'pg';
import { PrismaService } from '../prisma/prisma.service';
import { SALES_PRICE_CONTRACT_VERSION } from '../sales-reports/sales-report-revenue';
import { SalesReportCategoriesService } from '../sales-reports/sales-report-categories.service';
import { SalesReportsService } from '../sales-reports/sales-reports.service';
import { SalesHistoryImportParserService } from '../sales-reports/sales-history-import-parser.service';
import { SalesHistoryImportService } from '../sales-reports/sales-history-import.service';
import { HOME_SALES_KPI_CONTRACT_VERSION } from './home-summary-contract';
import { HomeSummaryProjectionService } from './home-summary-projection.service';
import { HomeSummaryService } from './home-summary.service';

const sourceUrl = process.env.OPSHUB_OPS52_POSTGRES_URL?.trim();
const describePostgres = sourceUrl ? describe : describe.skip;
const MIGRATION_TIMEOUT_MS = 60_000;

type MigrationRunResult = {
  status: number | null;
  signal: NodeJS.Signals | null;
  error?: NodeJS.ErrnoException;
};

async function requireSuccessfulMigration(
  migrate: () => MigrationRunResult,
  cleanup: () => Promise<void>,
) {
  let result: MigrationRunResult;
  try {
    result = migrate();
  } catch (error) {
    await cleanup();
    throw error;
  }
  if (result.status === 0) return;

  await cleanup();
  if (result.error?.code === 'ETIMEDOUT') {
    throw new Error(
      `OPS-52 scratch migration timed out after ${MIGRATION_TIMEOUT_MS}ms`,
    );
  }
  if (result.signal) {
    throw new Error(
      `OPS-52 scratch migration stopped by signal ${result.signal}`,
    );
  }
  throw new Error(
    `OPS-52 scratch migration failed with exit code ${String(result.status)}`,
  );
}

function restoreDatabaseUrl(previousDatabaseUrl: string | undefined) {
  if (previousDatabaseUrl === undefined) {
    delete process.env.DATABASE_URL;
    return;
  }
  process.env.DATABASE_URL = previousDatabaseUrl;
}

describe('OPS-52 PostgreSQL proof harness', () => {
  it('cleans the scratch database when migration exceeds its subprocess bound', async () => {
    const cleanup = jest.fn().mockResolvedValue(undefined);
    const timeoutError = Object.assign(new Error('spawn timed out'), {
      code: 'ETIMEDOUT',
    });

    await expect(
      requireSuccessfulMigration(
        () => ({ status: null, signal: 'SIGTERM', error: timeoutError }),
        cleanup,
      ),
    ).rejects.toThrow('scratch migration timed out after 60000ms');
    expect(cleanup).toHaveBeenCalledTimes(1);
  });

  it('restores an initially present DATABASE_URL exactly', () => {
    const originalDatabaseUrl = process.env.DATABASE_URL;
    const previousDatabaseUrl = 'postgresql://existing.example/opshub';

    try {
      process.env.DATABASE_URL = 'postgresql://scratch.example/opshub';
      restoreDatabaseUrl(previousDatabaseUrl);

      expect(process.env.DATABASE_URL).toBe(previousDatabaseUrl);
    } finally {
      restoreDatabaseUrl(originalDatabaseUrl);
    }
  });

  it('deletes DATABASE_URL when it was initially absent', () => {
    const originalDatabaseUrl = process.env.DATABASE_URL;

    try {
      process.env.DATABASE_URL = 'postgresql://scratch.example/opshub';
      restoreDatabaseUrl(undefined);

      expect(Object.hasOwn(process.env, 'DATABASE_URL')).toBe(false);
    } finally {
      restoreDatabaseUrl(originalDatabaseUrl);
    }
  });
});

describePostgres('OPS-52 Home SALES KPI PostgreSQL reconciliation', () => {
  jest.setTimeout(120_000);

  const backendRoot = path.resolve(__dirname, '..', '..');
  const databaseName = `opshub_ops52_${randomUUID().replaceAll('-', '')}`;
  const primaryAffectedDateKey = '2099-01-10';
  const stalePriceDateKey = '2099-01-11';
  const missingKpiDateKey = '2099-01-12';
  const staleKpiDateKey = '2099-01-13';
  const controlDateKey = '2099-01-14';
  const primaryAffectedDate = new Date(
    `${primaryAffectedDateKey}T00:00:00.000Z`,
  );
  const stalePriceDate = new Date(`${stalePriceDateKey}T00:00:00.000Z`);
  const missingKpiDate = new Date(`${missingKpiDateKey}T00:00:00.000Z`);
  const staleKpiDate = new Date(`${staleKpiDateKey}T00:00:00.000Z`);
  const controlDate = new Date(`${controlDateKey}T00:00:00.000Z`);
  const sourceTimestamp = new Date('2099-01-09T18:00:00.000Z');
  const previousDatabaseUrl = process.env.DATABASE_URL;
  let admin: pg.Client;
  let pool: pg.Pool;
  let prisma: PrismaClient;
  let salesReports: SalesReportsService;
  let historyImports: SalesHistoryImportService;
  let projection: HomeSummaryProjectionService;
  let created = false;

  beforeAll(async () => {
    if (!sourceUrl) return;
    if (!/^opshub_ops52_[0-9a-f]{32}$/.test(databaseName)) {
      throw new Error('Unsafe OPS-52 scratch database name');
    }
    const adminUrl = new URL(sourceUrl);
    if (!['127.0.0.1', 'localhost'].includes(adminUrl.hostname)) {
      throw new Error('OPS-52 PostgreSQL proof requires a loopback database');
    }
    adminUrl.pathname = '/postgres';
    adminUrl.searchParams.delete('schema');
    const scratchUrl = new URL(sourceUrl);
    scratchUrl.pathname = `/${databaseName}`;
    scratchUrl.searchParams.delete('schema');

    admin = new pg.Client({ connectionString: adminUrl.toString() });
    await admin.connect();
    await admin.query(`CREATE DATABASE "${databaseName}"`);
    created = true;

    const prismaMigrationRunner = path.join(
      backendRoot,
      'scripts',
      'run-prisma-migrate-deploy.mjs',
    );
    await requireSuccessfulMigration(
      () =>
        spawnSync(process.execPath, [prismaMigrationRunner], {
          cwd: backendRoot,
          env: { ...process.env, DATABASE_URL: scratchUrl.toString() },
          encoding: 'utf8',
          stdio: ['ignore', 'pipe', 'pipe'],
          timeout: MIGRATION_TIMEOUT_MS,
          killSignal: 'SIGTERM',
        }),
      async () => {
        if (created) {
          await admin.query(
            'SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = $1 AND pid <> pg_backend_pid()',
            [databaseName],
          );
          await admin.query(`DROP DATABASE "${databaseName}"`);
          created = false;
        }
        await admin.end().catch(() => undefined);
      },
    );

    process.env.DATABASE_URL = scratchUrl.toString();
    pool = new pg.Pool({ connectionString: scratchUrl.toString() });
    prisma = new PrismaClient({ adapter: new PrismaPg(pool) });
    await prisma.$connect();
    salesReports = new SalesReportsService(
      prisma as PrismaService,
      {} as any,
      {} as any,
    );
    historyImports = new SalesHistoryImportService(
      prisma as PrismaService,
      new SalesHistoryImportParserService(
        new SalesReportCategoriesService(prisma as PrismaService),
      ),
    );
    const homeSummary = new HomeSummaryService(
      prisma as PrismaService,
      salesReports,
      {} as any,
    );
    projection = new HomeSummaryProjectionService(
      prisma as PrismaService,
      homeSummary,
      { publishMessageOrThrow: jest.fn() } as any,
    );
  });

  afterAll(async () => {
    await prisma?.$disconnect().catch(() => undefined);
    await pool?.end().catch(() => undefined);
    restoreDatabaseUrl(previousDatabaseUrl);
    if (admin && created) {
      await admin.query(`DROP DATABASE "${databaseName}"`);
    }
    await admin?.end().catch(() => undefined);
  });

  it('admits a history CSV through the adapter-pg transaction advisory lock', async () => {
    const actor = await prisma.user.create({
      data: {
        email: `ops62-history-import-${randomUUID()}@example.test`,
        password: 'test-only-password',
        firstName: 'OPS-62',
        role: 'SUPER_ADMIN',
      },
    });

    await expect(
      historyImports.createUpload({ id: actor.id }, 'history.csv', 1),
    ).resolves.toMatchObject({
      status: 'UPLOADING',
      uploadedBytes: 0,
      expectedBytes: 1,
    });
  });

  it('stages one canonical order across parser chunks through adapter-pg without numeric coercion', async () => {
    const actor = await prisma.user.create({
      data: {
        email: `ops62-history-stage-${randomUUID()}@example.test`,
        password: 'test-only-password',
        firstName: 'OPS-62',
        role: 'SUPER_ADMIN',
      },
    });
    const jobId = randomUUID();
    const claimToken = 7n;
    await prisma.salesHistoryImportJob.create({
      data: {
        id: jobId,
        status: 'PARSING',
        expectedBytes: 1n,
        uploadedBytes: 1n,
        requestedByUserId: actor.id,
        workerId: (historyImports as any).workerId,
        claimToken,
      },
    });
    const quantities = (component: string, value: number) => ({
      extendedInsuranceQuantity: 0,
      laptopQuantity: 0,
      pcQuantity: 0,
      assembledPcQuantity: 0,
      appleQuantity: 0,
      monitorQuantity: 0,
      printerQuantity: 0,
      accessoriesQuantity: 0,
      cpuQuantity: 0,
      mainboardQuantity: 0,
      memoryQuantity: 0,
      storageQuantity: 0,
      caseQuantity: 0,
      psuQuantity: 0,
      [component]: value,
    });
    const row = (component: string, value: number, revenue: number) => ({
      rowNumber: 2,
      date: '2099-02-02',
      storeCode: 'CP62',
      orderCode: '25070134938050',
      salespersonEmail: actor.email,
      salespersonCode: 'OPS62',
      signedRevenue: revenue,
      quantities: quantities(component, value),
      errorCodes: [],
    });
    const identities = {
      storeCodes: new Set(['CP62']),
      byEmail: new Map([[actor.email, actor.id]]),
      byPersonnelCode: new Map([['OPS62', actor.id]]),
      userStoreCodes: new Map([[actor.id, new Set(['CP62'])]]),
    };

    await (historyImports as any).stageChunk(
      jobId,
      claimToken,
      [row('cpuQuantity', 2, 900)],
      identities,
    );
    await (historyImports as any).stageChunk(
      jobId,
      claimToken,
      [row('mainboardQuantity', 3, 1_200)],
      identities,
    );

    await expect(
      prisma.salesHistoryImportOrderStage.findFirstOrThrow({
        where: { jobId },
      }),
    ).resolves.toMatchObject({
      userId: actor.id,
      totalRevenue: 2_100n,
      cpuQuantity: 2,
      mainboardQuantity: 3,
    });

    const indexes = await prisma.$queryRaw<
      Array<{ indexname: string; indexdef: string }>
    >(Prisma.sql`
      SELECT indexname, indexdef
      FROM pg_indexes
      WHERE schemaname = current_schema()
        AND tablename = 'SalesHistoryImportOrderStage'
    `);
    expect(indexes).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          indexname: 'SalesHistoryImportOrderStage_jobId_orderHash_idx',
          indexdef: expect.stringContaining('("jobId", "orderHash")'),
        }),
      ]),
    );

    await prisma.salesHistoryImportOrderStage.createMany({
      data: Array.from({ length: 5_000 }, (_, index) => ({
        jobId,
        summaryDate: new Date('2099-02-03T00:00:00.000Z'),
        storeCode: 'CP62',
        userId: actor.id,
        orderHash: `ops62-scale-${index.toString().padStart(5, '0')}`,
        totalRevenue: 1n,
      })),
    });
    await prisma.$executeRaw(Prisma.sql`
      ANALYZE "SalesHistoryImportOrderStage"
    `);
    const explain = await prisma.$queryRaw<Array<{ 'QUERY PLAN': unknown }>>(
      Prisma.sql`
        EXPLAIN (FORMAT JSON)
        SELECT "orderHash", "userId"
        FROM "SalesHistoryImportOrderStage"
        WHERE "jobId" = ${jobId}
          AND "orderHash" IN ('ops62-scale-04999')
      `,
    );
    expect(JSON.stringify(explain)).toContain(
      'SalesHistoryImportOrderStage_jobId_orderHash_idx',
    );
  });

  it('keeps STORE orders across missing or conflicting historical identities and omits partial USER_STORE attribution', async () => {
    const actor = await prisma.user.create({
      data: {
        email: `ops62-email-primary-${randomUUID()}@example.test`,
        password: 'test-only-password',
        firstName: 'OPS-62',
        role: 'SUPER_ADMIN',
      },
    });
    const secondUser = await prisma.user.create({
      data: {
        email: `ops62-email-conflict-${randomUUID()}@example.test`,
        password: 'test-only-password',
        firstName: 'OPS-62 conflict',
        role: 'USER',
      },
    });
    const jobId = randomUUID();
    const claimToken = 9n;
    const summaryDate = new Date('2099-02-05T00:00:00.000Z');
    await prisma.salesHistoryImportJob.create({
      data: {
        id: jobId,
        status: 'PARSING',
        expectedBytes: 1n,
        uploadedBytes: 1n,
        requestedByUserId: actor.id,
        workerId: (historyImports as any).workerId,
        claimToken,
      },
    });
    const quantities = {
      extendedInsuranceQuantity: 0,
      laptopQuantity: 0,
      pcQuantity: 0,
      assembledPcQuantity: 0,
      appleQuantity: 0,
      monitorQuantity: 0,
      printerQuantity: 0,
      accessoriesQuantity: 0,
      cpuQuantity: 0,
      mainboardQuantity: 0,
      memoryQuantity: 0,
      storageQuantity: 0,
      caseQuantity: 0,
      psuQuantity: 0,
    };
    const historicalRow = (
      rowNumber: number,
      orderCode: string,
      salespersonEmail: string,
      signedRevenue: number,
    ) => ({
      rowNumber,
      date: '2099-02-05',
      storeCode: 'CP66',
      orderCode,
      salespersonEmail,
      salespersonCode: null,
      signedRevenue,
      quantities: { ...quantities, laptopQuantity: 1 },
      errorCodes: [],
    });
    const identities = {
      storeCodes: new Set(['CP66']),
      byEmail: new Map<string, string | null>([
        [actor.email.toLowerCase(), actor.id],
        [secondUser.email.toLowerCase(), secondUser.id],
      ]),
      byPersonnelCode: new Map<string, string | null>(),
    };

    await (historyImports as any).stageChunk(
      jobId,
      claimToken,
      [historicalRow(2, '25070134938060', actor.email, 1_000)],
      identities,
    );
    await (historyImports as any).stageChunk(
      jobId,
      claimToken,
      [
        historicalRow(3, '25070134938060', secondUser.email, 2_000),
        historicalRow(4, '25070134938061', 'departed@example.test', 500),
        historicalRow(5, '25070134938062', actor.email, 700),
      ],
      identities,
    );

    await expect(
      prisma.salesHistoryImportGrainStage.findUniqueOrThrow({
        where: {
          jobId_summaryDate_storeCode: {
            jobId,
            summaryDate,
            storeCode: 'CP66',
          },
        },
      }),
    ).resolves.toMatchObject({
      rowCount: 4,
      invalidRows: 0,
      reasonCodes: expect.arrayContaining(['PERSONAL_COVERAGE_INCOMPLETE']),
    });
    const stagedOrders = await prisma.salesHistoryImportOrderStage.findMany({
      where: { jobId },
      orderBy: { totalRevenue: 'asc' },
    });
    expect(stagedOrders).toHaveLength(3);
    expect(stagedOrders).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ userId: '', totalRevenue: 500n }),
        expect.objectContaining({ userId: actor.id, totalRevenue: 700n }),
        expect.objectContaining({ userId: '', totalRevenue: 3_000n }),
      ]),
    );

    const finalized = await (historyImports as any).finalizeVersion(
      { id: actor.id },
      jobId,
      'ops62-email-primary-proof',
    );
    await expect(
      prisma.salesHistoryCoverage.findUniqueOrThrow({
        where: {
          versionId_summaryDate_storeCode: {
            versionId: finalized.versionId,
            summaryDate,
            storeCode: 'CP66',
          },
        },
      }),
    ).resolves.toMatchObject({
      status: 'CLEAN',
      rowCount: 4,
      quarantinedRows: 0,
      reasonCodes: expect.arrayContaining(['PERSONAL_COVERAGE_INCOMPLETE']),
    });
    const aggregates = await prisma.salesHistoryAggregate.findMany({
      where: { versionId: finalized.versionId },
      orderBy: { dimensionType: 'asc' },
    });
    expect(aggregates).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          dimensionType: 'STORE',
          dimensionKey: '',
          totalRevenue: 4_200n,
          totalOrders: 3,
          laptopQuantity: 4,
        }),
        expect.objectContaining({
          dimensionType: 'USER_STORE',
          dimensionKey: actor.id,
          totalRevenue: 700n,
          totalOrders: 1,
          laptopQuantity: 1,
        }),
      ]),
    );
    expect(
      aggregates.some(
        (aggregate) =>
          aggregate.dimensionType === 'USER_STORE' &&
          aggregate.dimensionKey === '',
      ),
    ).toBe(false);
  });

  it('quarantines derived assembled-PC overflow while finalizing another clean grain', async () => {
    const actor = await prisma.user.create({
      data: {
        email: `ops62-history-derived-boundary-${randomUUID()}@example.test`,
        password: 'test-only-password',
        firstName: 'OPS-62',
        role: 'SUPER_ADMIN',
      },
    });
    const jobId = randomUUID();
    const claimToken = 8n;
    await prisma.salesHistoryImportJob.create({
      data: {
        id: jobId,
        status: 'PARSING',
        expectedBytes: 1n,
        uploadedBytes: 1n,
        requestedByUserId: actor.id,
        workerId: (historyImports as any).workerId,
        claimToken,
      },
    });
    const quantities = (
      assembledPcQuantity: number,
      componentQuantity: number,
    ) => ({
      extendedInsuranceQuantity: 0,
      laptopQuantity: 0,
      pcQuantity: 0,
      assembledPcQuantity,
      appleQuantity: 0,
      monitorQuantity: 0,
      printerQuantity: 0,
      accessoriesQuantity: 0,
      cpuQuantity: componentQuantity,
      mainboardQuantity: componentQuantity,
      memoryQuantity: componentQuantity,
      storageQuantity: componentQuantity,
      caseQuantity: componentQuantity,
      psuQuantity: componentQuantity,
    });
    const row = (
      storeCode: string,
      orderCode: string,
      assembledPcQuantity: number,
      componentQuantity: number,
    ) => ({
      rowNumber: 2,
      date: '2099-02-04',
      storeCode,
      orderCode,
      salespersonEmail: actor.email,
      salespersonCode: 'OPS62-BOUNDARY',
      signedRevenue: 1_000,
      quantities: quantities(assembledPcQuantity, componentQuantity),
      errorCodes: [],
    });
    const identities = {
      storeCodes: new Set(['CP64', 'CP65']),
      byEmail: new Map([[actor.email, actor.id]]),
      byPersonnelCode: new Map([['OPS62-BOUNDARY', actor.id]]),
      userStoreCodes: new Map([[actor.id, new Set(['CP64', 'CP65'])]]),
    };

    await (historyImports as any).stageChunk(
      jobId,
      claimToken,
      [
        row('CP64', '25070134938051', 1_073_741_823, 0),
        row('CP64', '25070134938052', 1_073_741_824, 0),
        row('CP65', '25070134938053', 1_073_741_824, 0),
        row('CP65', '25070134938054', 1_073_741_824, 0),
      ],
      identities,
    );

    const badGrain =
      await prisma.salesHistoryImportGrainStage.findUniqueOrThrow({
        where: {
          jobId_summaryDate_storeCode: {
            jobId,
            summaryDate: new Date('2099-02-04T00:00:00.000Z'),
            storeCode: 'CP65',
          },
        },
      });
    expect(badGrain).toMatchObject({
      invalidRows: 0,
      reasonCodes: [],
    });

    const finalized = await (historyImports as any).finalizeVersion(
      { id: actor.id },
      jobId,
      'ops62-derived-boundary-proof',
    );
    await expect(
      prisma.salesHistoryAggregate.findUniqueOrThrow({
        where: {
          versionId_summaryDate_storeCode_dimensionType_dimensionKey: {
            versionId: finalized.versionId,
            summaryDate: new Date('2099-02-04T00:00:00.000Z'),
            storeCode: 'CP64',
            dimensionType: 'STORE',
            dimensionKey: '',
          },
        },
      }),
    ).resolves.toMatchObject({
      totalRevenue: 2_000n,
      totalOrders: 2,
      assembledPcQuantity: 2_147_483_647,
    });
    await expect(
      prisma.salesHistoryCoverage.findUniqueOrThrow({
        where: {
          versionId_summaryDate_storeCode: {
            versionId: finalized.versionId,
            summaryDate: new Date('2099-02-04T00:00:00.000Z'),
            storeCode: 'CP65',
          },
        },
      }),
    ).resolves.toMatchObject({
      status: 'QUARANTINED',
      reasonCodes: expect.arrayContaining(['DATE_SHOWROOM_NUMERIC_OVERFLOW']),
    });
  });

  it('finalizes staged component facts into the canonical assembled-PC aggregate on PostgreSQL', async () => {
    const actor = await prisma.user.create({
      data: {
        email: `ops62-history-finalize-${randomUUID()}@example.test`,
        password: 'test-only-password',
        firstName: 'OPS-62',
        role: 'SUPER_ADMIN',
      },
    });
    const jobId = randomUUID();
    const summaryDate = new Date('2099-02-01T00:00:00.000Z');
    await prisma.salesHistoryImportJob.create({
      data: {
        id: jobId,
        status: 'FINALIZING',
        expectedBytes: 1n,
        uploadedBytes: 1n,
        requestedByUserId: actor.id,
      },
    });
    await prisma.salesHistoryImportGrainStage.create({
      data: {
        jobId,
        summaryDate,
        storeCode: 'CP62',
        rowCount: 12,
        invalidRows: 0,
      },
    });
    await prisma.salesHistoryImportOrderStage.createMany({
      data: [
        {
          jobId,
          summaryDate,
          storeCode: 'CP62',
          userId: actor.id,
          orderHash: 'ops62-components',
          totalRevenue: 1_000n,
          assembledPcQuantity: 1,
          cpuQuantity: 2,
          mainboardQuantity: 3,
          memoryQuantity: 4,
          storageQuantity: 5,
          caseQuantity: 6,
          psuQuantity: 7,
        },
        {
          jobId,
          summaryDate,
          storeCode: 'CP62',
          userId: actor.id,
          orderHash: 'ops62-negative-direct',
          totalRevenue: 1_000n,
          assembledPcQuantity: -1,
        },
      ],
    });

    const finalized = await (historyImports as any).finalizeVersion(
      { id: actor.id },
      jobId,
      'ops62-postgres-component-proof',
    );
    const aggregate = await prisma.salesHistoryAggregate.findUniqueOrThrow({
      where: {
        versionId_summaryDate_storeCode_dimensionType_dimensionKey: {
          versionId: finalized.versionId,
          summaryDate,
          storeCode: 'CP62',
          dimensionType: 'STORE',
          dimensionKey: '',
        },
      },
    });

    expect(aggregate).toMatchObject({
      totalRevenue: 2_000n,
      totalOrders: 2,
      assembledPcQuantity: 3,
    });
  });

  it('queues every missing or stale subordinate SALES contract grain and atomically rebuilds the primary date with purchased-only promotion KPIs', async () => {
    const now = new Date();
    const currentMetrics = {
      salesPriceContractVersion: SALES_PRICE_CONTRACT_VERSION,
      salesKpiContractVersion: HOME_SALES_KPI_CONTRACT_VERSION,
    };
    const aggregate = (
      summaryDate: Date,
      dimensionType: string,
      dimensionKey: string,
      storeCode: string,
      metrics: Prisma.InputJsonObject,
    ) => ({
      summaryDate,
      projectionKind: 'SALES',
      dimensionType,
      dimensionKey,
      storeCode,
      metrics,
      projectionVersion: 1n,
      generatedAt: now,
    });

    await prisma.homeSummaryDailyAggregate.createMany({
      data: [
        aggregate(primaryAffectedDate, 'GLOBAL', '', '', currentMetrics),
        aggregate(primaryAffectedDate, 'STORE', 'CP58', 'CP58', currentMetrics),
        aggregate(
          primaryAffectedDate,
          'USER_STORE',
          'sale.cp58@phongvu.vn',
          'CP58',
          { salesKpiContractVersion: HOME_SALES_KPI_CONTRACT_VERSION },
        ),
        aggregate(stalePriceDate, 'GLOBAL', '', '', currentMetrics),
        aggregate(stalePriceDate, 'STORE', 'CP58', 'CP58', {
          salesPriceContractVersion: SALES_PRICE_CONTRACT_VERSION - 1,
          salesKpiContractVersion: HOME_SALES_KPI_CONTRACT_VERSION,
        }),
        aggregate(
          stalePriceDate,
          'USER_STORE',
          'sale.cp58@phongvu.vn',
          'CP58',
          currentMetrics,
        ),
        aggregate(missingKpiDate, 'GLOBAL', '', '', currentMetrics),
        aggregate(missingKpiDate, 'STORE', 'CP58', 'CP58', {
          salesPriceContractVersion: SALES_PRICE_CONTRACT_VERSION,
        }),
        aggregate(
          missingKpiDate,
          'USER_STORE',
          'sale.cp58@phongvu.vn',
          'CP58',
          currentMetrics,
        ),
        aggregate(staleKpiDate, 'GLOBAL', '', '', currentMetrics),
        aggregate(staleKpiDate, 'STORE', 'CP58', 'CP58', currentMetrics),
        aggregate(staleKpiDate, 'USER_STORE', 'sale.cp58@phongvu.vn', 'CP58', {
          salesPriceContractVersion: SALES_PRICE_CONTRACT_VERSION,
          salesKpiContractVersion: HOME_SALES_KPI_CONTRACT_VERSION - 1,
        }),
        aggregate(controlDate, 'GLOBAL', '', '', currentMetrics),
        aggregate(controlDate, 'STORE', 'CP58', 'CP58', currentMetrics),
        aggregate(
          controlDate,
          'USER_STORE',
          'sale.cp58@phongvu.vn',
          'CP58',
          currentMetrics,
        ),
      ],
    });

    jest.spyOn(projection as any, 'runCycle').mockResolvedValue(undefined);
    await (projection as any).runStartupCycle();

    const queued = await prisma.homeSummaryProjectionQueue.findMany({
      where: {
        summaryDate: {
          in: [
            primaryAffectedDate,
            stalePriceDate,
            missingKpiDate,
            staleKpiDate,
            controlDate,
          ],
        },
        projectionKind: 'SALES',
      },
      orderBy: { summaryDate: 'asc' },
    });
    expect(
      queued.map(({ summaryDate }) => summaryDate.toISOString().slice(0, 10)),
    ).toEqual([
      primaryAffectedDateKey,
      stalePriceDateKey,
      missingKpiDateKey,
      staleKpiDateKey,
    ]);
    expect(
      queued.map(({ summaryDate }) => summaryDate.toISOString().slice(0, 10)),
    ).not.toContain(controlDateKey);

    await prisma.salesReportCategoryGroup.create({
      data: {
        id: 'OPS52_CATEGORY',
        catGroupName: 'OPS-52 category',
        catGroupNameVi: 'Ngành hàng OPS-52',
      },
    });
    const commonReport = {
      categoryGroupId: 'OPS52_CATEGORY',
      categoryGroupName: 'OPS-52 category',
      categoryGroupNameVi: 'Ngành hàng OPS-52',
      consultedSolutionAnswer: 'YES',
      experiencedAnswer: 'YES',
      zaloAnswer: 'YES',
      appDownloadAnswer: 'YES',
      createdByEmail: 'sale.cp58@phongvu.vn',
      storeCode: 'CP58',
      storeName: 'CP58',
      promotionCodes: ['EXAM_SCORE_EXCHANGE', 'STUDENT'],
      installmentNeed: true,
      submittedAt: sourceTimestamp,
    };
    await prisma.salesReport.create({
      data: {
        ...commonReport,
        id: 'ops52-purchased',
        reportType: 'PURCHASED',
        orderCode: 'OPS52-ORDER',
        erpOrderCreatedAt: sourceTimestamp,
        erpLifecycleStatus: 'COMPLETED',
        installmentStatus: 'SUCCESS',
        items: {
          create: [
            { categoryType: 'laptop', quantity: 1, rowTotal: 1_000_000 },
          ],
        },
      },
    });
    await prisma.salesReport.create({
      data: {
        ...commonReport,
        id: 'ops52-not-purchased',
        reportType: 'NOT_PURCHASED',
        installmentNoInstallmentReason: 'HIGH_INTEREST_OR_FEE',
      },
    });
    await prisma.salesReportErpOrderCache.create({
      data: {
        orderCode: 'OPS52-ORDER',
        orderCreatedAt: sourceTimestamp,
        paymentStatus: 'PAID',
        lifecycleStatus: 'COMPLETED',
        grandTotal: 1_000_000,
        storeCode: 'CP58',
        sourceUserEmail: 'sale.cp58@phongvu.vn',
        fetchedAt: sourceTimestamp,
      },
    });
    await prisma.homeSummaryOrderFact.create({
      data: {
        summaryDate: sourceTimestamp,
        orderCode: 'OPS52-ORDER',
        orderCreatedAt: sourceTimestamp,
        storeCode: 'CP58',
        sourceUserEmail: 'sale.cp58@phongvu.vn',
        grandTotal: 1_000_000,
        hasValidReport: true,
        reportId: 'ops52-purchased',
        reportSubmittedAt: sourceTimestamp,
        reportRevenue: 1_000_000,
        reportCreatedByEmail: 'sale.cp58@phongvu.vn',
        refreshedAt: now,
      },
    });
    await prisma.homeSummaryReportFact.createMany({
      data: [
        {
          summaryDate: sourceTimestamp,
          salesReportId: 'ops52-purchased',
          reportType: 'PURCHASED',
          orderCode: 'OPS52-ORDER',
          createdByEmail: 'sale.cp58@phongvu.vn',
          storeCode: 'CP58',
          revenue: 1_000_000,
          submittedAt: sourceTimestamp,
          refreshedAt: now,
        },
        {
          summaryDate: sourceTimestamp,
          salesReportId: 'ops52-not-purchased',
          reportType: 'NOT_PURCHASED',
          createdByEmail: 'sale.cp58@phongvu.vn',
          storeCode: 'CP58',
          submittedAt: sourceTimestamp,
          refreshedAt: now,
        },
      ],
    });

    const claimed = await prisma.$queryRaw<Array<any>>(Prisma.sql`
      UPDATE "HomeSummaryProjectionQueue"
      SET "claimedAt" = CURRENT_TIMESTAMP,
          "claimToken" = 'ops52-proof-claim',
          "leaseExpiresAt" = CURRENT_TIMESTAMP + INTERVAL '2 minutes',
          "claimedGeneration" = "dirtyGeneration",
          "attempts" = "attempts" + 1
      WHERE "summaryDate" = CAST(${primaryAffectedDateKey} AS date)
        AND "projectionKind" = 'SALES'
      RETURNING *
    `);
    expect(claimed).toHaveLength(1);
    const version = await (projection as any).finalizeProjection(
      claimed[0],
      primaryAffectedDateKey,
    );
    expect(typeof version).toBe('bigint');

    const rebuilt = await prisma.homeSummaryDailyAggregate.findMany({
      where: { summaryDate: primaryAffectedDate, projectionKind: 'SALES' },
      orderBy: [{ dimensionType: 'asc' }, { dimensionKey: 'asc' }],
    });
    expect(rebuilt.map((row) => row.dimensionType).sort()).toEqual([
      'GLOBAL',
      'STORE',
      'USER_STORE',
    ]);
    for (const row of rebuilt) {
      expect(row.metrics).toMatchObject({
        salesPriceContractVersion: SALES_PRICE_CONTRACT_VERSION,
        salesKpiContractVersion: HOME_SALES_KPI_CONTRACT_VERSION,
        examScorePromotionCount: 1,
        studentPromotionCount: 1,
        installmentNeedCount: 2,
      });
      expect(row.notPurchasedReports).toBe(1);
    }

    const retainedNotPurchasedReport =
      await prisma.salesReport.findUniqueOrThrow({
        where: { id: 'ops52-not-purchased' },
        select: { promotionCodes: true, reportType: true },
      });
    expect(retainedNotPurchasedReport).toEqual({
      reportType: 'NOT_PURCHASED',
      promotionCodes: ['EXAM_SCORE_EXCHANGE', 'STUDENT'],
    });

    const reports = await prisma.salesReport.findMany({
      where: { id: { in: ['ops52-purchased', 'ops52-not-purchased'] } },
      include: { items: true },
    });
    const summary = salesReports.summarizeSalesRevenueRows(reports);
    expect(summary.noInstallmentReasons).toEqual(
      new Map([['Khách từ chối: Lãi suất/Phí trả góp cao', 1]]),
    );
    expect(summary.installmentNeedTotalCount).toBe(2);
    expect(summary.examScorePromotionCount).toBe(1);
    expect(summary.studentPromotionCount).toBe(1);
  });
});
