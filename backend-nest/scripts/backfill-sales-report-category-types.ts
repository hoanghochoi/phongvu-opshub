import 'dotenv/config';
import { Injectable, Module } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { mkdir, open, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { PrismaService } from '../src/prisma/prisma.service';
import { SalesReportCategoriesService } from '../src/sales-reports/sales-report-categories.service';
import {
  SalesReportCategoryBackfillPlan,
  SalesReportCategoryBackfillService,
} from '../src/sales-reports/sales-report-category-backfill.service';
import { SalesReportErpService } from '../src/sales-reports/sales-report-erp.service';
import { SalesReportsBigQuerySyncService } from '../src/sales-reports/sales-reports-bigquery-sync.service';

@Injectable()
class BackfillBigQuerySyncService extends SalesReportsBigQuerySyncService {
  constructor(prisma: PrismaService) {
    super(prisma);
  }

  onApplicationBootstrap() {
    // Operator CLI must not run the application's startup synchronization.
  }
}

@Module({
  providers: [
    PrismaService,
    SalesReportErpService,
    SalesReportCategoriesService,
    {
      provide: SalesReportsBigQuerySyncService,
      useClass: BackfillBigQuerySyncService,
    },
    SalesReportCategoryBackfillService,
  ],
})
class SalesReportCategoryBackfillCliModule {}

type ProgressStage =
  'DB_STARTED' | 'DB_APPLIED' | 'HOME_ENQUEUED' | 'BIGQUERY_SYNCED';

type ProgressEvent = {
  stage: ProgressStage;
  at: string;
  planHash: string;
  db?: Record<string, unknown>;
  dates?: string[];
  bigQuery?: Record<string, unknown>;
};

function parseArgs(argv: string[]) {
  const args: {
    apply: boolean;
    checkpoint: string;
    expectedPlanHash?: string;
    pageSize: number;
    batchSize: number;
  } = {
    apply: false,
    checkpoint: path.resolve(
      process.cwd(),
      'artifacts',
      'ops-13-sales-report-category-backfill.plan.json',
    ),
    pageSize: 100,
    batchSize: 50,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === '--apply') args.apply = true;
    else if (value === '--checkpoint')
      args.checkpoint = path.resolve(argv[++index]);
    else if (value === '--expected-plan-hash')
      args.expectedPlanHash = argv[++index];
    else if (value === '--page-size') args.pageSize = Number(argv[++index]);
    else if (value === '--batch-size') args.batchSize = Number(argv[++index]);
    else throw new Error(`Unknown argument: ${value}`);
  }
  if (args.apply && !args.expectedPlanHash) {
    throw new Error('--expected-plan-hash is required with --apply');
  }
  return args;
}

async function writeOnce(filePath: string, body: string) {
  await mkdir(path.dirname(filePath), { recursive: true });
  const handle = await open(filePath, 'wx');
  try {
    await handle.writeFile(body, 'utf8');
  } finally {
    await handle.close();
  }
}

async function appendProgress(filePath: string, event: ProgressEvent) {
  await mkdir(path.dirname(filePath), { recursive: true });
  await writeFile(filePath, `${JSON.stringify(event)}\n`, {
    encoding: 'utf8',
    flag: 'a',
  });
}

async function readProgress(filePath: string) {
  try {
    const body = await readFile(filePath, 'utf8');
    const events = body
      .split(/\r?\n/)
      .filter(Boolean)
      .map((line) => JSON.parse(line) as ProgressEvent);
    return events[events.length - 1] ?? null;
  } catch (error: any) {
    if (error?.code === 'ENOENT') return null;
    throw error;
  }
}

async function run() {
  const args = parseArgs(process.argv.slice(2));
  const progressPath = `${args.checkpoint}.progress.jsonl`;
  const app = await NestFactory.createApplicationContext(
    SalesReportCategoryBackfillCliModule,
    {
      logger: false,
    },
  );
  try {
    const service = app.get(SalesReportCategoryBackfillService);
    let plan: SalesReportCategoryBackfillPlan;
    if (args.apply) {
      plan = JSON.parse(
        await readFile(args.checkpoint, 'utf8'),
      ) as SalesReportCategoryBackfillPlan;
      if (
        plan.version !== 2 ||
        !plan.createdAt ||
        Number.isNaN(new Date(plan.createdAt).getTime()) ||
        !Number.isInteger(plan.pageSize) ||
        plan.pageSize < 1 ||
        !Number.isInteger(plan.candidateCount) ||
        plan.candidateCount < 0 ||
        !Array.isArray(plan.affectedDates) ||
        plan.affectedDates.some(
          (date) =>
            typeof date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(date),
        ) ||
        typeof plan.planHash !== 'string' ||
        !/^[a-f0-9]{64}$/.test(plan.planHash)
      ) {
        throw new Error('Checkpoint metadata is invalid');
      }
      if (args.expectedPlanHash !== plan.planHash) {
        throw new Error(
          'Checkpoint planHash does not match --expected-plan-hash',
        );
      }
    } else {
      plan = await service.buildPlan(args.pageSize);
      await writeOnce(args.checkpoint, `${JSON.stringify(plan, null, 2)}\n`);
      await writeOnce(
        `${args.checkpoint}.manifest.json`,
        `${JSON.stringify(
          {
            createdAt: new Date().toISOString(),
            planHash: plan.planHash,
            candidates: plan.candidateCount,
            lastCandidateId: plan.lastCandidateId,
            affectedDates: plan.affectedDates,
            checkpoint: path.basename(args.checkpoint),
          },
          null,
          2,
        )}\n`,
      );
      console.log(
        JSON.stringify({
          event: 'ops13_category_backfill_plan_ready',
          mode: 'dry-run',
          planHash: plan.planHash,
          candidates: plan.candidateCount,
          lastCandidateId: plan.lastCandidateId,
          affectedDates: plan.affectedDates.length,
          checkpoint: args.checkpoint,
        }),
      );
      return;
    }

    const latest = await readProgress(progressPath);
    if (latest && latest.planHash !== plan.planHash) {
      throw new Error('Progress planHash does not match checkpoint planHash');
    }
    let dbResult: Record<string, any> = latest?.db ?? {};
    const stageOrder: Record<ProgressStage, number> = {
      DB_STARTED: 1,
      DB_APPLIED: 2,
      HOME_ENQUEUED: 3,
      BIGQUERY_SYNCED: 4,
    };
    let latestStage = latest ? stageOrder[latest.stage] : 0;
    const resumingDatabase = latestStage === stageOrder.DB_STARTED;
    if (latestStage < stageOrder.DB_STARTED) {
      await service.verifyPlan(plan);
      await appendProgress(progressPath, {
        stage: 'DB_STARTED',
        at: new Date().toISOString(),
        planHash: plan.planHash,
      });
      latestStage = stageOrder.DB_STARTED;
    }
    if (latestStage < stageOrder.DB_APPLIED) {
      dbResult = await service.applyDatabase(plan, args.batchSize, {
        verifyPlan: false,
        resume: resumingDatabase,
      });
      await appendProgress(progressPath, {
        stage: 'DB_APPLIED',
        at: new Date().toISOString(),
        planHash: plan.planHash,
        db: dbResult,
      });
      latestStage = stageOrder.DB_APPLIED;
    }
    if (Number(dbResult.updated ?? 0) === 0 && !resumingDatabase) {
      console.log(
        JSON.stringify({
          event: 'ops13_category_backfill_succeeded',
          mode: 'apply',
          stage: 'DB_APPLIED',
          planHash: plan.planHash,
          updated: 0,
        }),
      );
      return;
    }
    if (latestStage < stageOrder.HOME_ENQUEUED) {
      const dates = Array.isArray(dbResult.affectedDates)
        ? dbResult.affectedDates
        : [];
      await service.enqueueHomeProjection(dates);
      await appendProgress(progressPath, {
        stage: 'HOME_ENQUEUED',
        at: new Date().toISOString(),
        planHash: plan.planHash,
        db: dbResult,
        dates,
      });
      latestStage = stageOrder.HOME_ENQUEUED;
    }
    if (latestStage < stageOrder.BIGQUERY_SYNCED) {
      const bigQuery = await service.syncBigQuery();
      await appendProgress(progressPath, {
        stage: 'BIGQUERY_SYNCED',
        at: new Date().toISOString(),
        planHash: plan.planHash,
        db: dbResult,
        dates: dbResult.affectedDates,
        bigQuery: {
          reportRows: bigQuery.reportRows,
          itemRows: bigQuery.itemRows,
          durationMs: bigQuery.durationMs,
        },
      });
      latestStage = stageOrder.BIGQUERY_SYNCED;
    }
    console.log(
      JSON.stringify({
        event: 'ops13_category_backfill_succeeded',
        mode: 'apply',
        stage: 'BIGQUERY_SYNCED',
        planHash: plan.planHash,
        updated: dbResult.updated,
        affectedDates: dbResult.affectedDates?.length ?? 0,
      }),
    );
  } finally {
    await app.close();
  }
}

if (require.main === module) {
  run().catch((error) => {
    console.error(
      JSON.stringify({
        event: 'ops13_category_backfill_failed',
        error: String(error?.message ?? error).slice(0, 500),
      }),
    );
    process.exitCode = 1;
  });
}
