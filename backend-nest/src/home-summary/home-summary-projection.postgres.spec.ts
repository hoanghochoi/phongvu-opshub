import { spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import { PrismaPg } from '@prisma/adapter-pg';
import { Prisma, PrismaClient } from '@prisma/client';
import pg from 'pg';
import { PrismaService } from '../prisma/prisma.service';
import { SALES_PRICE_CONTRACT_VERSION } from '../sales-reports/sales-report-revenue';
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

    const prismaCli = path.join(
      backendRoot,
      'node_modules',
      'prisma',
      'build',
      'index.js',
    );
    await requireSuccessfulMigration(
      () =>
        spawnSync(process.execPath, [prismaCli, 'migrate', 'deploy'], {
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
      new SalesHistoryImportParserService(),
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
