import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { createHash, randomUUID } from 'node:crypto';
import { appendFile, open, readdir, stat, unlink } from 'node:fs/promises';
import { extname } from 'node:path';
import { join } from 'node:path';
import { safeLogError } from '../common/log-sanitizer';
import {
  organizationNodeStoreTreeInclude,
  storesForOrganizationNodeTree,
} from '../common/organization-store-scope';
import { isSuperAdminRole } from '../common/system-role';
import { PrismaService } from '../prisma/prisma.service';
import {
  ImportCancelledError,
  SalesHistoryImportParserService,
  SalesHistoryMetricKey,
  SalesHistoryParsedRow,
} from './sales-history-import-parser.service';
import {
  SALES_HISTORY_IMPORT_CHUNK_BYTES,
  SALES_HISTORY_IMPORT_DIRECTORY,
  SALES_HISTORY_IMPORT_MAX_BYTES,
} from './sales-history-import-upload.options';

const TERMINAL_JOB_STATUSES = new Set(['READY', 'FAILED', 'CANCELLED']);
const IMPORT_ARTIFACT_TTL_MS = 24 * 60 * 60 * 1000;
const IMPORT_LEASE_MS = 30 * 1000;
const IMPORT_HEARTBEAT_MS = 10 * 1000;
const IMPORT_PUMP_INTERVAL_MS = 1000;
const IMPORT_CLEANUP_INTERVAL_MS = 60 * 60 * 1000;
const IMPORT_MAX_CONCURRENCY = 1;
const IMPORT_ARTIFACT_BUDGET_BYTES = 220 * 1024 * 1024;
const HISTORY_EVENT_TYPE = 'HOME_SUMMARY_UPDATED';
const METRIC_KEYS: SalesHistoryMetricKey[] = [
  'extendedInsuranceQuantity',
  'laptopQuantity',
  'pcQuantity',
  'assembledPcQuantity',
  'appleQuantity',
  'monitorQuantity',
  'printerQuantity',
  'accessoriesQuantity',
];

type IdentityIndex = {
  storeCodes: Set<string>;
  byEmail: Map<string, string | null>;
  byPersonnelCode: Map<string, string | null>;
  userStoreCodes: Map<string, Set<string>>;
};

type StagedOrder = SalesHistoryParsedRow & { userId: string };
type FreshHistoryScope = {
  actorUserId: string;
  storeCodes: Set<string> | null;
};

@Injectable()
export class SalesHistoryImportService
  implements OnModuleInit, OnModuleDestroy
{
  private readonly logger = new Logger(SalesHistoryImportService.name);
  private readonly workerId = randomUUID();
  private activeWorkers = 0;
  private pumpScheduled = false;
  private pumpTimer?: NodeJS.Timeout;
  private cleanupTimer?: NodeJS.Timeout;

  constructor(
    private readonly prisma: PrismaService,
    private readonly parser: SalesHistoryImportParserService,
  ) {}

  onModuleInit() {
    this.schedulePump();
    void this.cleanupStaleArtifacts();
    this.pumpTimer = setInterval(
      () => this.schedulePump(),
      IMPORT_PUMP_INTERVAL_MS,
    );
    this.pumpTimer.unref?.();
    this.cleanupTimer = setInterval(
      () => void this.cleanupStaleArtifacts(),
      IMPORT_CLEANUP_INTERVAL_MS,
    );
    this.cleanupTimer.unref?.();
  }

  onModuleDestroy() {
    if (this.pumpTimer) clearInterval(this.pumpTimer);
    if (this.cleanupTimer) clearInterval(this.cleanupTimer);
  }

  async createUpload(user: any, rawFileName?: string, rawFileSize?: number) {
    const fileName = cleanText(rawFileName, 240) ?? '';
    const expectedBytes = Number(rawFileSize);
    if (
      !['.csv', '.tsv'].includes(extname(fileName).toLowerCase()) ||
      !Number.isSafeInteger(expectedBytes) ||
      expectedBytes <= 0 ||
      expectedBytes > SALES_HISTORY_IMPORT_MAX_BYTES
    ) {
      throw new BadRequestException(
        'Chọn tệp CSV/TSV không quá 200 MiB rồi thử lại.',
      );
    }
    const scope = await this.resolveFreshScope(user);
    this.assertHasTargetScope(scope);
    const requestedByUserId = cleanText(user?.id, 120);
    const artifactPath = join(
      SALES_HISTORY_IMPORT_DIRECTORY,
      `${randomUUID()}.upload`,
    );
    const job = await this.prisma.$transaction(async (tx) => {
      await tx.$queryRaw(Prisma.sql`
        SELECT pg_advisory_xact_lock(
          hashtextextended('sales-history-import-upload-admission', 0)
        )
      `);
      const reserved = await tx.salesHistoryImportJob.aggregate({
        where: {
          artifactPath: { not: null },
          status: { in: ['UPLOADING', 'QUEUED', 'PARSING', 'FINALIZING'] },
        },
        _sum: { expectedBytes: true },
      });
      const reservedBytes = Number(reserved._sum.expectedBytes ?? 0);
      if (reservedBytes + expectedBytes > IMPORT_ARTIFACT_BUDGET_BYTES) {
        throw new BadRequestException(
          'Máy chủ đang xử lý một tệp lớn khác. Vui lòng thử lại sau ít phút.',
        );
      }
      return tx.salesHistoryImportJob.create({
        data: {
          status: 'UPLOADING',
          uploadedBytes: 0n,
          expectedBytes: BigInt(expectedBytes),
          requestedByUserId,
          artifactPath,
        },
      });
    });
    this.logger.log(
      `Sales history upload admitted: jobId=${job.id} actor=${safeActor(user)} expectedBytes=${expectedBytes}`,
    );
    return this.toJobResponse(job);
  }

  async appendUploadChunk(
    user: any,
    id: string,
    offset: number,
    chunk: Express.Multer.File,
  ) {
    const bytes = chunk?.buffer;
    if (
      !Number.isSafeInteger(offset) ||
      offset < 0 ||
      !bytes?.length ||
      bytes.length > SALES_HISTORY_IMPORT_CHUNK_BYTES
    ) {
      throw new BadRequestException(
        'Phần dữ liệu tải lên chưa hợp lệ. Vui lòng tiếp tục tải lại.',
      );
    }
    const scopedJob = await this.prisma.salesHistoryImportJob.findUnique({
      where: { id },
      include: {
        version: { include: { coverage: true } },
        stagedGrains: { select: { storeCode: true } },
      },
    });
    if (!scopedJob)
      throw new NotFoundException('Không tìm thấy tác vụ nhập dữ liệu.');
    await this.assertJobScope(user, scopedJob);
    const response = await this.prisma.$transaction(async (tx) => {
      await tx.$queryRaw(Prisma.sql`
        SELECT pg_advisory_xact_lock(hashtextextended(${`upload:${id}`}, 0))
      `);
      const job = await tx.salesHistoryImportJob.findUnique({ where: { id } });
      if (!job?.artifactPath || job.status !== 'UPLOADING') {
        throw new BadRequestException(
          'Tác vụ không còn nhận dữ liệu tải lên. Hãy kiểm tra trạng thái rồi thử lại.',
        );
      }
      const currentOffset = Number(job.uploadedBytes);
      const expectedBytes = Number(job.expectedBytes);
      if (offset < currentOffset && offset + bytes.length <= currentOffset) {
        return job;
      }
      if (offset !== currentOffset || offset + bytes.length > expectedBytes) {
        throw new BadRequestException(
          'Tiến trình tải lên đã thay đổi. OpsHub sẽ tiếp tục từ phần đã nhận.',
        );
      }
      const existingSize = await stat(job.artifactPath)
        .then((value) => value.size)
        .catch(() => 0);
      if (existingSize !== offset) {
        throw new BadRequestException(
          'Tệp tạm chưa đồng bộ. Vui lòng hủy tác vụ và chọn lại tệp.',
        );
      }
      try {
        await appendFile(job.artifactPath, bytes);
        const updated = await tx.salesHistoryImportJob.updateMany({
          where: {
            id,
            status: 'UPLOADING',
            uploadedBytes: BigInt(offset),
            cancelRequestedAt: null,
          },
          data: { uploadedBytes: BigInt(offset + bytes.length) },
        });
        if (updated.count !== 1) {
          throw new Error('upload_offset_changed');
        }
      } catch (error) {
        const handle = await open(job.artifactPath, 'r+').catch(() => null);
        if (handle) {
          await handle.truncate(offset).catch(() => undefined);
          await handle.close().catch(() => undefined);
        }
        throw error;
      }
      return tx.salesHistoryImportJob.findUnique({ where: { id } });
    });
    return this.toJobResponse(response);
  }

  async completeUpload(user: any, id: string) {
    const job = await this.prisma.salesHistoryImportJob.findUnique({
      where: { id },
      include: {
        version: { include: { coverage: true } },
        stagedGrains: { select: { storeCode: true } },
      },
    });
    if (!job)
      throw new NotFoundException('Không tìm thấy tác vụ nhập dữ liệu.');
    await this.assertJobScope(user, job);
    if (job.status === 'QUEUED') return this.toJobResponse(job);
    if (job.status !== 'UPLOADING' || job.uploadedBytes !== job.expectedBytes) {
      throw new BadRequestException(
        'Tệp chưa tải xong. Vui lòng tiếp tục tải trước khi xử lý.',
      );
    }
    const updated = await this.prisma.salesHistoryImportJob.updateMany({
      where: {
        id,
        status: 'UPLOADING',
        uploadedBytes: job.expectedBytes,
        cancelRequestedAt: null,
      },
      data: { status: 'QUEUED' },
    });
    if (updated.count !== 1) {
      throw new BadRequestException(
        'Trạng thái tác vụ vừa thay đổi. Vui lòng tải lại để kiểm tra.',
      );
    }
    const queued = await this.prisma.salesHistoryImportJob.findUnique({
      where: { id },
    });
    this.logger.log(`Sales history import queued: jobId=${id}`);
    this.schedulePump();
    return this.toJobResponse(queued);
  }

  async getJob(user: any, id: string) {
    const job = await this.prisma.salesHistoryImportJob.findUnique({
      where: { id },
      include: {
        version: {
          include: {
            coverage: {
              orderBy: [{ summaryDate: 'asc' }, { storeCode: 'asc' }],
            },
          },
        },
        stagedGrains: { select: { storeCode: true } },
      },
    });
    if (!job)
      throw new NotFoundException('Không tìm thấy tác vụ nhập dữ liệu.');
    await this.assertJobScope(user, job);
    return this.toJobResponse(job);
  }

  async cancelJob(user: any, id: string) {
    const scopedJob = await this.prisma.salesHistoryImportJob.findUnique({
      where: { id },
      include: {
        version: { include: { coverage: true } },
        stagedGrains: { select: { storeCode: true } },
      },
    });
    if (!scopedJob)
      throw new NotFoundException('Không tìm thấy tác vụ nhập dữ liệu.');
    await this.assertJobScope(user, scopedJob);
    const cancelled = await this.prisma.$transaction(async (tx) => {
      await tx.$queryRaw(Prisma.sql`
        SELECT pg_advisory_xact_lock(hashtextextended(${`upload:${id}`}, 0))
      `);
      const job = await tx.salesHistoryImportJob.findUnique({ where: { id } });
      if (!job)
        throw new NotFoundException('Không tìm thấy tác vụ nhập dữ liệu.');
      if (TERMINAL_JOB_STATUSES.has(job.status)) {
        return { job, artifactPathToDelete: null as string | null };
      }

      const now = new Date();
      const unclaimed =
        (job.status === 'QUEUED' || job.status === 'UPLOADING') &&
        job.workerId == null;
      const updated = await tx.salesHistoryImportJob.updateMany({
        where: {
          id,
          status: job.status,
          workerId: job.workerId,
          claimToken: job.claimToken,
        },
        data: unclaimed
          ? {
              status: 'CANCELLED',
              cancelRequestedAt: now,
              completedAt: now,
              artifactPath: null,
            }
          : { cancelRequestedAt: now },
      });
      if (updated.count !== 1) {
        throw new BadRequestException(
          'Trạng thái tác vụ vừa thay đổi. Vui lòng tải lại để kiểm tra.',
        );
      }
      if (unclaimed) {
        await tx.salesHistoryImportOrderStage.deleteMany({
          where: { jobId: id },
        });
        await tx.salesHistoryImportGrainStage.deleteMany({
          where: { jobId: id },
        });
      }
      const result = await tx.salesHistoryImportJob.findUnique({
        where: { id },
      });
      return {
        job: result,
        artifactPathToDelete: unclaimed ? job.artifactPath : null,
      };
    });
    if (cancelled.artifactPathToDelete) {
      await unlink(cancelled.artifactPathToDelete).catch(() => undefined);
    }
    this.logger.log(`Sales history import cancellation requested: jobId=${id}`);
    return this.toJobResponse(cancelled.job);
  }

  async listVersions(user: any, limit = 20) {
    const safeLimit = Math.max(1, Math.min(Math.trunc(limit) || 20, 100));
    const scope = await this.resolveFreshScope(user);
    const versions = await this.prisma.salesHistoryVersion.findMany({
      ...(scope.storeCodes == null
        ? {}
        : {
            where: {
              coverage: {
                some: {},
                every: { storeCode: { in: Array.from(scope.storeCodes) } },
              },
            },
          }),
      orderBy: { createdAt: 'desc' },
      take: safeLimit,
      include: {
        _count: { select: { activeGrains: true } },
        activations: { orderBy: { createdAt: 'desc' }, take: 1 },
      },
    });
    return versions.map((version) => ({
      id: version.id,
      sourceHash: version.sourceHash,
      rowCount: version.rowCount,
      cleanRowCount: version.cleanRowCount,
      quarantinedRows: version.quarantinedRows,
      cleanGrainCount: version.cleanGrainCount,
      quarantineCount: version.quarantineCount,
      rangeStart: dateKey(version.rangeStart),
      rangeEnd: dateKey(version.rangeEnd),
      activeGrainCount: version._count.activeGrains,
      lastAction: version.activations[0]?.action ?? null,
      createdAt: version.createdAt,
    }));
  }

  async quarantineReport(user: any, jobId: string) {
    const job = await this.prisma.salesHistoryImportJob.findUnique({
      where: { id: jobId },
      include: {
        version: { include: { coverage: true } },
        stagedGrains: { select: { storeCode: true } },
      },
    });
    if (!job)
      throw new NotFoundException('Không tìm thấy tác vụ nhập dữ liệu.');
    await this.assertJobScope(user, job);
    const rows = (job.version?.coverage ?? []).filter(
      (grain) => grain.status === 'QUARANTINED',
    );
    const lines = [
      'Ngày,Showroom,Số dòng cách ly,Mã nguyên nhân',
      ...rows.map((grain) =>
        [
          dateKey(grain.summaryDate),
          csvCell(grain.storeCode),
          String(grain.quarantinedRows),
          csvCell(grain.reasonCodes.join('|')),
        ].join(','),
      ),
    ];
    return Buffer.from(`\uFEFF${lines.join('\r\n')}`, 'utf8');
  }

  async activate(user: any, versionId: string) {
    const startedAt = Date.now();
    this.logger.log(
      `Sales history activation started: versionId=${versionId} actor=${safeActor(user)}`,
    );
    const result = await this.prisma.$transaction(async (tx) => {
      const version = await tx.salesHistoryVersion.findUnique({
        where: { id: versionId },
        include: { coverage: { where: { status: 'CLEAN' } } },
      });
      if (!version)
        throw new NotFoundException('Không tìm thấy phiên bản dữ liệu.');
      if (version.coverage.length === 0) {
        throw new BadRequestException(
          'Phiên bản chưa có phạm vi sạch để kích hoạt.',
        );
      }
      const grains = version.coverage.map((item) => ({
        summaryDate: item.summaryDate,
        storeCode: item.storeCode,
      }));
      await this.assertStoreScope(
        user,
        grains.map((grain) => grain.storeCode),
        tx,
      );
      await this.lockActiveGrains(tx, grains);
      const existing = await tx.salesHistoryActiveGrain.findMany({
        where: { OR: grains },
      });
      const existingByKey = new Map(
        existing.map((item) => [
          grainKey(item.summaryDate, item.storeCode),
          item,
        ]),
      );
      if (
        grains.every(
          (grain) =>
            existingByKey.get(grainKey(grain.summaryDate, grain.storeCode))
              ?.currentVersionId === versionId,
        )
      ) {
        const previous = await tx.salesHistoryActivation.findFirst({
          where: { versionId, action: 'ACTIVATE' },
          orderBy: { createdAt: 'desc' },
        });
        if (!previous) {
          throw new BadRequestException(
            'Phiên bản đang hoạt động nhưng thiếu lịch sử kích hoạt. Vui lòng liên hệ quản trị viên.',
          );
        }
        return {
          activationId: previous.id,
          grainCount: grains.length,
        };
      }
      const activation = await tx.salesHistoryActivation.create({
        data: {
          versionId,
          action: 'ACTIVATE',
          actorUserId: cleanText(user?.id, 120),
          grainCount: grains.length,
        },
      });
      await tx.salesHistoryActivationGrain.createMany({
        data: grains.map((grain) => ({
          activationId: activation.id,
          summaryDate: grain.summaryDate,
          storeCode: grain.storeCode,
          fromVersionId:
            existingByKey.get(grainKey(grain.summaryDate, grain.storeCode))
              ?.currentVersionId ?? null,
          toVersionId: versionId,
        })),
      });
      for (const grain of grains) {
        await tx.salesHistoryActiveGrain.upsert({
          where: {
            summaryDate_storeCode: {
              summaryDate: grain.summaryDate,
              storeCode: grain.storeCode,
            },
          },
          create: { ...grain, currentVersionId: versionId },
          update: {
            currentVersionId: versionId,
            activatedAt: new Date(),
          },
        });
      }
      await this.enqueueHomeInvalidation(
        tx,
        versionId,
        grains.map((item) => item.summaryDate),
      );
      return { activationId: activation.id, grainCount: grains.length };
    });
    this.logger.log(
      `Sales history activation succeeded: versionId=${versionId} grains=${result.grainCount} durationMs=${Date.now() - startedAt}`,
    );
    return { versionId, status: 'ACTIVE', ...result };
  }

  async rollback(user: any, versionId: string) {
    const startedAt = Date.now();
    this.logger.log(
      `Sales history rollback started: versionId=${versionId} actor=${safeActor(user)}`,
    );
    const result = await this.prisma.$transaction(async (tx) => {
      const latest = await tx.salesHistoryActivation.findFirst({
        where: { versionId, action: 'ACTIVATE' },
        orderBy: { createdAt: 'desc' },
        include: { grains: true },
      });
      if (!latest) {
        throw new BadRequestException(
          'Phiên bản chưa có lần kích hoạt để hoàn tác.',
        );
      }
      const candidates = latest.grains.map((grain) => ({
        summaryDate: grain.summaryDate,
        storeCode: grain.storeCode,
        previousVersionId: grain.fromVersionId,
      }));
      await this.assertStoreScope(
        user,
        candidates.map((grain) => grain.storeCode),
        tx,
      );
      await this.lockActiveGrains(tx, candidates);
      const active = await tx.salesHistoryActiveGrain.findMany({
        where: {
          OR: candidates.map(({ summaryDate, storeCode }) => ({
            summaryDate,
            storeCode,
          })),
        },
      });
      const activeByKey = new Map(
        active.map((item) => [
          grainKey(item.summaryDate, item.storeCode),
          item,
        ]),
      );
      const restorable = candidates.filter(
        (grain) =>
          activeByKey.get(grainKey(grain.summaryDate, grain.storeCode))
            ?.currentVersionId === versionId,
      );
      if (restorable.length === 0) {
        throw new BadRequestException(
          'Phiên bản không còn phạm vi đang hoạt động để hoàn tác.',
        );
      }
      const activation = await tx.salesHistoryActivation.create({
        data: {
          versionId,
          action: 'ROLLBACK',
          actorUserId: cleanText(user?.id, 120),
          grainCount: restorable.length,
        },
      });
      await tx.salesHistoryActivationGrain.createMany({
        data: restorable.map((grain) => ({
          activationId: activation.id,
          summaryDate: grain.summaryDate,
          storeCode: grain.storeCode,
          fromVersionId: versionId,
          toVersionId: grain.previousVersionId,
        })),
      });
      for (const grain of restorable) {
        if (grain.previousVersionId) {
          await tx.salesHistoryActiveGrain.update({
            where: {
              summaryDate_storeCode: {
                summaryDate: grain.summaryDate,
                storeCode: grain.storeCode,
              },
            },
            data: {
              currentVersionId: grain.previousVersionId,
              activatedAt: new Date(),
            },
          });
        } else {
          await tx.salesHistoryActiveGrain.delete({
            where: {
              summaryDate_storeCode: {
                summaryDate: grain.summaryDate,
                storeCode: grain.storeCode,
              },
            },
          });
        }
      }
      await this.enqueueHomeInvalidation(
        tx,
        `rollback-${versionId}`,
        restorable.map((item) => item.summaryDate),
      );
      return { activationId: activation.id, grainCount: restorable.length };
    });
    this.logger.log(
      `Sales history rollback succeeded: versionId=${versionId} grains=${result.grainCount} durationMs=${Date.now() - startedAt}`,
    );
    return { versionId, status: 'ROLLED_BACK', ...result };
  }

  private schedulePump() {
    if (this.pumpScheduled) return;
    this.pumpScheduled = true;
    queueMicrotask(() => {
      this.pumpScheduled = false;
      void this.pumpJobs();
    });
  }

  private async pumpJobs() {
    while (this.activeWorkers < IMPORT_MAX_CONCURRENCY) {
      const claimed = await this.claimNextJob().catch((error) => {
        this.logger.warn(
          `Sales history job claim failed: workerId=${this.workerId} error=${safeLogError(error)}`,
        );
        return null;
      });
      if (!claimed) return;
      this.activeWorkers += 1;
      void this.processClaimedJob(claimed).finally(() => {
        this.activeWorkers -= 1;
        this.schedulePump();
      });
    }
  }

  private claimableJobsWhere(now: Date) {
    return {
      artifactPath: { not: null },
      cancelRequestedAt: null,
      OR: [
        { status: 'QUEUED' },
        {
          AND: [
            { status: { in: ['PARSING', 'FINALIZING'] } },
            { OR: [{ leaseExpiresAt: null }, { leaseExpiresAt: { lt: now } }] },
          ],
        },
      ],
    };
  }

  private async claimNextJob() {
    return this.prisma.$transaction(async (tx) => {
      const now = new Date();
      await tx.$queryRaw(Prisma.sql`
        SELECT pg_advisory_xact_lock(
          hashtextextended('sales-history-import-global-claim', 0)
        )
      `);
      const globallyClaimed = await tx.salesHistoryImportJob.count({
        where: {
          status: { in: ['PARSING', 'FINALIZING'] },
          leaseExpiresAt: { gt: now },
        },
      });
      if (globallyClaimed >= IMPORT_MAX_CONCURRENCY) return null;
      const candidate = await tx.salesHistoryImportJob.findFirst({
        where: this.claimableJobsWhere(now),
        orderBy: { createdAt: 'asc' },
      });
      if (!candidate?.artifactPath) return null;
      await tx.$queryRaw(Prisma.sql`
        SELECT pg_advisory_xact_lock(
          hashtextextended(${`upload:${candidate.id}`}, 0)
        )
      `);
      const leaseExpiresAt = new Date(now.getTime() + IMPORT_LEASE_MS);
      const claimed = await tx.salesHistoryImportJob.updateMany({
        where: { id: candidate.id, ...this.claimableJobsWhere(now) },
        data: {
          status: 'PARSING',
          workerId: this.workerId,
          leaseExpiresAt,
          heartbeatAt: now,
          attemptCount: { increment: 1 },
          claimToken: { increment: 1 },
        },
      });
      if (claimed.count !== 1) return null;
      return tx.salesHistoryImportJob.findUnique({
        where: { id: candidate.id },
      });
    });
  }

  private async processClaimedJob(job: any) {
    if (!job?.artifactPath) return;
    const heartbeat = setInterval(
      () => void this.heartbeatJob(job.id, job.claimToken),
      IMPORT_HEARTBEAT_MS,
    );
    heartbeat.unref?.();
    try {
      await this.processJob(
        job.id,
        job.artifactPath,
        job.claimToken,
        job.attemptCount > 1,
      );
    } finally {
      clearInterval(heartbeat);
    }
  }

  private async heartbeatJob(jobId: string, claimToken: bigint) {
    const now = new Date();
    await this.prisma.salesHistoryImportJob
      .updateMany({
        where: {
          id: jobId,
          workerId: this.workerId,
          claimToken,
          status: { in: ['PARSING', 'FINALIZING'] },
        },
        data: {
          heartbeatAt: now,
          leaseExpiresAt: new Date(now.getTime() + IMPORT_LEASE_MS),
        },
      })
      .catch((error) => {
        this.logger.warn(
          `Sales history heartbeat failed: jobId=${jobId} error=${safeLogError(error)}`,
        );
      });
  }

  private async processJob(
    jobId: string,
    filePath: string,
    claimToken: bigint,
    resumed: boolean,
  ) {
    const startedAt = Date.now();
    this.logger.log(`Sales history parsing started: jobId=${jobId}`);
    try {
      if (resumed) {
        await this.withClaim(jobId, claimToken, async (tx) => {
          await tx.salesHistoryImportOrderStage.deleteMany({
            where: { jobId },
          });
          await tx.salesHistoryImportGrainStage.deleteMany({
            where: { jobId },
          });
        });
      }
      const actor = await this.actorForJob(jobId, claimToken);
      const scope = await this.resolveFreshScope(actor);
      this.assertHasTargetScope(scope);
      await this.updateClaimedJob(jobId, claimToken, {
        status: 'PARSING',
        startedAt: new Date(),
        failureCode: null,
        failureMessage: null,
      });
      const identities = await this.loadIdentityIndex();
      let processedRows = 0;
      const metadata = await this.parser.parse(
        filePath,
        async (rows) => {
          await this.stageChunk(jobId, claimToken, rows, identities);
          processedRows += rows.length;
          await this.updateClaimedJob(jobId, claimToken, {
            totalRows: processedRows,
          });
        },
        () => this.isCancelled(jobId, claimToken),
      );
      if (await this.isCancelled(jobId, claimToken)) {
        throw new ImportCancelledError();
      }
      await this.updateClaimedJob(jobId, claimToken, {
        status: 'FINALIZING',
        sourceHash: metadata.sourceHash,
        encoding: metadata.encoding,
        delimiter: metadata.delimiter === '\t' ? 'TAB' : 'COMMA',
        totalRows: metadata.totalRows,
      });
      const result = await this.finalizeVersion(
        actor,
        jobId,
        metadata.sourceHash,
        claimToken,
      );
      this.logger.log(
        `Sales history parsing succeeded: jobId=${jobId} versionId=${result.versionId} rows=${metadata.totalRows} cleanGrains=${result.cleanGrains} quarantinedGrains=${result.quarantinedGrains} durationMs=${Date.now() - startedAt}`,
      );
    } catch (error) {
      if (error instanceof ImportClaimLostError) {
        this.logger.warn(
          `Sales history stale worker stopped: jobId=${jobId} claimToken=${claimToken.toString()}`,
        );
        return;
      }
      const cancelled = error instanceof ImportCancelledError;
      const message = cancelled
        ? 'Đã hủy nhập dữ liệu.'
        : this.userFailureMessage(error);
      await this.withClaim(jobId, claimToken, async (tx) => {
        await tx.salesHistoryImportOrderStage.deleteMany({
          where: { jobId },
        });
        await tx.salesHistoryImportGrainStage.deleteMany({
          where: { jobId },
        });
        await tx.salesHistoryImportJob.updateMany({
          where: { id: jobId, workerId: this.workerId, claimToken },
          data: {
            status: cancelled ? 'CANCELLED' : 'FAILED',
            failureCode: cancelled ? 'CANCELLED' : errorCode(error),
            failureMessage: message,
            completedAt: new Date(),
          },
        });
      }).catch((cleanupError) => {
        this.logger.error(
          `Sales history job cleanup failed: jobId=${jobId} error=${safeLogError(cleanupError)}`,
        );
      });
      this.logger.error(
        `Sales history parsing ${cancelled ? 'cancelled' : 'failed'}: jobId=${jobId} durationMs=${Date.now() - startedAt} error=${safeLogError(error)}`,
      );
    } finally {
      const released = await this.prisma.salesHistoryImportJob
        .updateMany({
          where: {
            id: jobId,
            workerId: this.workerId,
            claimToken,
            artifactPath: filePath,
          },
          data: {
            artifactPath: null,
            workerId: null,
            leaseExpiresAt: null,
            heartbeatAt: null,
          },
        })
        .catch(() => ({ count: 0 }));
      if (released.count === 1) {
        await unlink(filePath).catch(() => undefined);
      }
    }
  }

  private async loadIdentityIndex(): Promise<IdentityIndex> {
    const [stores, users, reportIdentities, orderIdentities] =
      await Promise.all([
        this.prisma.store.findMany({ select: { storeId: true } }),
        this.prisma.user.findMany({
          select: {
            id: true,
            email: true,
            store: { select: { storeId: true } },
            organizationAssignments: {
              where: { isActive: true },
              include: {
                organizationNode: {
                  include: organizationNodeStoreTreeInclude(),
                },
              },
            },
          },
        }),
        this.prisma.salesReport.findMany({
          where: {
            createdByUserId: { not: null },
            createdByPersonnelCode: { not: null },
          },
          distinct: ['createdByUserId', 'createdByPersonnelCode'],
          select: { createdByUserId: true, createdByPersonnelCode: true },
        }),
        this.prisma.homeSummaryOrderFact.findMany({
          where: { sourceUserId: { not: null } },
          distinct: ['sourceUserId', 'consultantCustomId', 'sellerId'],
          select: {
            sourceUserId: true,
            consultantCustomId: true,
            sellerId: true,
          },
        }),
      ]);
    const byEmail = new Map<string, string | null>();
    const byPersonnelCode = new Map<string, string | null>();
    const userStoreCodes = new Map<string, Set<string>>();
    for (const user of users) {
      addUniqueIdentity(byEmail, user.email.toLowerCase(), user.id);
      const userStores = new Set<string>();
      const directStore = normalizeStoreCode(user.store?.storeId);
      if (directStore) userStores.add(directStore);
      for (const assignment of user.organizationAssignments ?? []) {
        for (const store of storesForOrganizationNodeTree(
          assignment.organizationNode,
        )) {
          const storeCode = normalizeStoreCode(store.storeId);
          if (storeCode) userStores.add(storeCode);
        }
      }
      userStoreCodes.set(user.id, userStores);
    }
    for (const row of reportIdentities) {
      if (row.createdByUserId && row.createdByPersonnelCode) {
        addUniqueIdentity(
          byPersonnelCode,
          row.createdByPersonnelCode.toUpperCase(),
          row.createdByUserId,
        );
      }
    }
    for (const row of orderIdentities) {
      if (!row.sourceUserId) continue;
      if (row.consultantCustomId) {
        addUniqueIdentity(
          byPersonnelCode,
          row.consultantCustomId.toUpperCase(),
          row.sourceUserId,
        );
      }
      if (row.sellerId) {
        addUniqueIdentity(
          byPersonnelCode,
          row.sellerId.toUpperCase(),
          row.sourceUserId,
        );
      }
    }
    return {
      storeCodes: new Set(
        stores.map((store) => store.storeId.trim().toUpperCase()),
      ),
      byEmail,
      byPersonnelCode,
      userStoreCodes,
    };
  }

  private async stageChunk(
    jobId: string,
    claimToken: bigint,
    rows: SalesHistoryParsedRow[],
    identities: IdentityIndex,
  ) {
    return this.withClaim(jobId, claimToken, async (tx) => {
      const grainUpdates = new Map<
        string,
        {
          date: string;
          storeCode: string;
          rows: number;
          invalid: number;
          reasons: Set<string>;
        }
      >();
      const validOrders: StagedOrder[] = [];
      for (const row of rows) {
        const { reasons, userId } = this.resolveRowIdentity(row, identities);
        if (!identities.storeCodes.has(row.storeCode))
          reasons.add('UNKNOWN_STORE');
        const key = `${row.date}|${row.storeCode}`;
        const grain = grainUpdates.get(key) ?? {
          date: row.date,
          storeCode: row.storeCode,
          rows: 0,
          invalid: 0,
          reasons: new Set<string>(),
        };
        grain.rows += 1;
        if (reasons.size > 0) {
          grain.invalid += 1;
          reasons.forEach((reason) => grain.reasons.add(reason));
        } else {
          validOrders.push({ ...row, userId: userId! });
        }
        grainUpdates.set(key, grain);
      }
      const grainSql = Array.from(grainUpdates.values()).map(
        (grain) =>
          Prisma.sql`(
        gen_random_uuid()::text, ${jobId}, CAST(${grain.date} AS date),
        ${grain.storeCode}, ${grain.rows}, ${grain.invalid},
        ${Array.from(grain.reasons)}::text[],
        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      )`,
      );
      if (grainSql.length > 0) {
        await tx.$executeRaw(Prisma.sql`
        INSERT INTO "SalesHistoryImportGrainStage" (
          "id", "jobId", "summaryDate", "storeCode", "rowCount",
          "invalidRows", "reasonCodes", "createdAt", "updatedAt"
        ) VALUES ${Prisma.join(grainSql)}
        ON CONFLICT ("jobId", "summaryDate", "storeCode") DO UPDATE SET
          "rowCount" = "SalesHistoryImportGrainStage"."rowCount" + EXCLUDED."rowCount",
          "invalidRows" = "SalesHistoryImportGrainStage"."invalidRows" + EXCLUDED."invalidRows",
          "reasonCodes" = ARRAY(
            SELECT DISTINCT unnest("SalesHistoryImportGrainStage"."reasonCodes" || EXCLUDED."reasonCodes")
          ),
          "updatedAt" = CURRENT_TIMESTAMP
      `);
      }
      const orderSql = validOrders.map((row) => {
        const orderHash = createHash('sha256')
          .update(`${row.date}|${row.storeCode}|${row.orderCode}`)
          .digest('hex');
        return Prisma.sql`(
        gen_random_uuid()::text, ${jobId}, CAST(${row.date} AS date),
        ${row.storeCode}, ${row.userId}, ${orderHash}, ${row.signedRevenue!},
        ${row.quantities.extendedInsuranceQuantity!}, ${row.quantities.laptopQuantity!},
        ${row.quantities.pcQuantity!}, ${row.quantities.assembledPcQuantity!},
        ${row.quantities.appleQuantity!}, ${row.quantities.monitorQuantity!},
        ${row.quantities.printerQuantity!}, ${row.quantities.accessoriesQuantity!},
        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      )`;
      });
      if (orderSql.length > 0) {
        await tx.$executeRaw(Prisma.sql`
        INSERT INTO "SalesHistoryImportOrderStage" (
          "id", "jobId", "summaryDate", "storeCode", "userId", "orderHash",
          "totalRevenue", "extendedInsuranceQuantity", "laptopQuantity",
          "pcQuantity", "assembledPcQuantity", "appleQuantity",
          "monitorQuantity", "printerQuantity", "accessoriesQuantity",
          "createdAt", "updatedAt"
        ) VALUES ${Prisma.join(orderSql)}
        ON CONFLICT ("jobId", "summaryDate", "storeCode", "userId", "orderHash")
        DO UPDATE SET
          "totalRevenue" = "SalesHistoryImportOrderStage"."totalRevenue" + EXCLUDED."totalRevenue",
          "extendedInsuranceQuantity" = "SalesHistoryImportOrderStage"."extendedInsuranceQuantity" + EXCLUDED."extendedInsuranceQuantity",
          "laptopQuantity" = "SalesHistoryImportOrderStage"."laptopQuantity" + EXCLUDED."laptopQuantity",
          "pcQuantity" = "SalesHistoryImportOrderStage"."pcQuantity" + EXCLUDED."pcQuantity",
          "assembledPcQuantity" = "SalesHistoryImportOrderStage"."assembledPcQuantity" + EXCLUDED."assembledPcQuantity",
          "appleQuantity" = "SalesHistoryImportOrderStage"."appleQuantity" + EXCLUDED."appleQuantity",
          "monitorQuantity" = "SalesHistoryImportOrderStage"."monitorQuantity" + EXCLUDED."monitorQuantity",
          "printerQuantity" = "SalesHistoryImportOrderStage"."printerQuantity" + EXCLUDED."printerQuantity",
          "accessoriesQuantity" = "SalesHistoryImportOrderStage"."accessoriesQuantity" + EXCLUDED."accessoriesQuantity",
          "updatedAt" = CURRENT_TIMESTAMP
      `);
      }
    });
  }

  private resolveRowIdentity(
    row: SalesHistoryParsedRow,
    identities: IdentityIndex,
  ) {
    const reasons = new Set(row.errorCodes);
    const emailUser = row.salespersonEmail
      ? identities.byEmail.get(row.salespersonEmail)
      : undefined;
    const codeUser = row.salespersonCode
      ? identities.byPersonnelCode.get(row.salespersonCode)
      : undefined;
    if (emailUser === null || codeUser === null)
      reasons.add('AMBIGUOUS_SALESPERSON');
    if (
      row.salespersonEmail &&
      row.salespersonCode &&
      (!emailUser || !codeUser || emailUser !== codeUser)
    ) {
      reasons.add('SALESPERSON_IDENTITY_MISMATCH');
    }
    const userId =
      row.salespersonEmail && row.salespersonCode
        ? emailUser && codeUser && emailUser === codeUser
          ? emailUser
          : null
        : emailUser || codeUser || null;
    if (!userId) reasons.add('UNKNOWN_SALESPERSON');
    if (userId && !identities.userStoreCodes.get(userId)?.has(row.storeCode)) {
      reasons.add('SALESPERSON_STORE_MISMATCH');
    }
    return { reasons, userId };
  }

  private async finalizeVersion(
    user: any,
    jobId: string,
    sourceHash: string,
    claimToken?: bigint,
  ) {
    return this.prisma.$transaction(async (tx) => {
      if (claimToken !== undefined) {
        await this.assertClaim(tx, jobId, claimToken);
      }
      const grains = await tx.salesHistoryImportGrainStage.findMany({
        where: { jobId },
        orderBy: [{ summaryDate: 'asc' }, { storeCode: 'asc' }],
      });
      if (grains.length === 0)
        throw new BadRequestException('Tệp chưa có phạm vi hợp lệ.');
      const clean = grains.filter((grain) => grain.invalidRows === 0);
      const quarantined = grains.filter((grain) => grain.invalidRows > 0);
      if (clean.length === 0) {
        throw new BadRequestException(
          'Không có phạm vi ngày/showroom sạch để tạo phiên bản. Vui lòng sửa tệp rồi thử lại.',
        );
      }
      await this.assertStoreScope(
        user,
        grains.map((grain) => grain.storeCode),
        tx,
      );
      const cleanRows = clean.reduce((sum, grain) => sum + grain.rowCount, 0);
      const quarantinedRows = quarantined.reduce(
        (sum, grain) => sum + grain.rowCount,
        0,
      );
      const version = await tx.salesHistoryVersion.create({
        data: {
          sourceHash,
          rowCount: cleanRows + quarantinedRows,
          cleanRowCount: cleanRows,
          quarantinedRows,
          cleanGrainCount: clean.length,
          quarantineCount: quarantined.length,
          rangeStart: grains[0].summaryDate,
          rangeEnd: grains[grains.length - 1].summaryDate,
          createdByUserId: (
            await tx.salesHistoryImportJob.findUnique({ where: { id: jobId } })
          )?.requestedByUserId,
        },
      });
      await tx.salesHistoryCoverage.createMany({
        data: grains.map((grain) => ({
          versionId: version.id,
          summaryDate: grain.summaryDate,
          storeCode: grain.storeCode,
          status: grain.invalidRows === 0 ? 'CLEAN' : 'QUARANTINED',
          rowCount: grain.rowCount,
          quarantinedRows: grain.invalidRows === 0 ? 0 : grain.rowCount,
          reasonCodes: grain.reasonCodes,
        })),
      });
      await tx.$executeRaw(Prisma.sql`
        WITH clean_grains AS (
          SELECT "summaryDate", "storeCode"
          FROM "SalesHistoryImportGrainStage"
          WHERE "jobId" = ${jobId} AND "invalidRows" = 0
        ), contributing_orders AS (
          SELECT stage.*
          FROM "SalesHistoryImportOrderStage" stage
          JOIN clean_grains grain USING ("summaryDate", "storeCode")
          WHERE stage."jobId" = ${jobId} AND stage."totalRevenue" > 0
        ), dimensions AS (
          SELECT grain."summaryDate", grain."storeCode", 'STORE'::text AS "dimensionType",
                 ''::text AS "dimensionKey",
                 COALESCE(SUM(item."totalRevenue"), 0)::bigint AS "totalRevenue",
                 COUNT(item."orderHash")::integer AS "totalOrders",
                 COALESCE(SUM(GREATEST(item."extendedInsuranceQuantity", 0)), 0)::integer AS "extendedInsuranceQuantity",
                 COALESCE(SUM(GREATEST(item."laptopQuantity", 0)), 0)::integer AS "laptopQuantity",
                 COALESCE(SUM(GREATEST(item."pcQuantity", 0)), 0)::integer AS "pcQuantity",
                 COALESCE(SUM(GREATEST(item."assembledPcQuantity", 0)), 0)::integer AS "assembledPcQuantity",
                 COALESCE(SUM(GREATEST(item."appleQuantity", 0)), 0)::integer AS "appleQuantity",
                 COALESCE(SUM(GREATEST(item."monitorQuantity", 0)), 0)::integer AS "monitorQuantity",
                 COALESCE(SUM(GREATEST(item."printerQuantity", 0)), 0)::integer AS "printerQuantity",
                 COALESCE(SUM(GREATEST(item."accessoriesQuantity", 0)), 0)::integer AS "accessoriesQuantity"
          FROM clean_grains grain
          LEFT JOIN contributing_orders item USING ("summaryDate", "storeCode")
          GROUP BY grain."summaryDate", grain."storeCode"
          UNION ALL
          SELECT item."summaryDate", item."storeCode", 'USER_STORE', item."userId",
                 SUM(item."totalRevenue")::bigint, COUNT(item."orderHash")::integer,
                 SUM(GREATEST(item."extendedInsuranceQuantity", 0))::integer,
                 SUM(GREATEST(item."laptopQuantity", 0))::integer,
                 SUM(GREATEST(item."pcQuantity", 0))::integer,
                 SUM(GREATEST(item."assembledPcQuantity", 0))::integer,
                 SUM(GREATEST(item."appleQuantity", 0))::integer,
                 SUM(GREATEST(item."monitorQuantity", 0))::integer,
                 SUM(GREATEST(item."printerQuantity", 0))::integer,
                 SUM(GREATEST(item."accessoriesQuantity", 0))::integer
          FROM contributing_orders item
          GROUP BY item."summaryDate", item."storeCode", item."userId"
        )
        INSERT INTO "SalesHistoryAggregate" (
          "id", "versionId", "summaryDate", "storeCode", "dimensionType",
          "dimensionKey", "totalRevenue", "totalOrders",
          "extendedInsuranceQuantity", "laptopQuantity", "pcQuantity",
          "assembledPcQuantity", "appleQuantity", "monitorQuantity",
          "printerQuantity", "accessoriesQuantity", "createdAt"
        ) SELECT gen_random_uuid()::text, ${version.id}, "summaryDate", "storeCode",
                 "dimensionType", "dimensionKey", "totalRevenue", "totalOrders",
                 "extendedInsuranceQuantity", "laptopQuantity", "pcQuantity",
                 "assembledPcQuantity", "appleQuantity", "monitorQuantity",
                 "printerQuantity", "accessoriesQuantity", CURRENT_TIMESTAMP
          FROM dimensions
      `);
      await tx.salesHistoryImportOrderStage.deleteMany({ where: { jobId } });
      await tx.salesHistoryImportGrainStage.deleteMany({ where: { jobId } });
      await tx.salesHistoryImportJob.updateMany({
        where: {
          id: jobId,
          ...(claimToken === undefined
            ? {}
            : { workerId: this.workerId, claimToken }),
        },
        data: {
          status: 'READY',
          versionId: version.id,
          cleanRows,
          quarantinedRows,
          cleanGrains: clean.length,
          quarantinedGrains: quarantined.length,
          completedAt: new Date(),
        },
      });
      return {
        versionId: version.id,
        cleanGrains: clean.length,
        quarantinedGrains: quarantined.length,
      };
    });
  }

  private async enqueueHomeInvalidation(
    tx: Prisma.TransactionClient,
    sourceId: string,
    dates: Date[],
  ) {
    const affectedDates = Array.from(new Set(dates.map(dateKey))).sort();
    const rows = await tx.$queryRaw<Array<{ version: bigint }>>(Prisma.sql`
      SELECT nextval('home_summary_projection_version_seq') AS version
    `);
    const version = rows[0]?.version;
    if (!version) throw new Error('Home summary version sequence unavailable');
    await tx.domainOutboxEvent.create({
      data: {
        eventType: HISTORY_EVENT_TYPE,
        aggregateType: 'SALES_HISTORY_VERSION',
        aggregateId: sourceId,
        dedupeKey: `home-summary-history:${sourceId}:${version.toString()}`,
        schemaVersion: 2,
        payload: { affectedDates, projectionVersion: Number(version) },
      },
    });
  }

  private async lockActiveGrains(
    tx: Prisma.TransactionClient,
    grains: Array<{ summaryDate: Date; storeCode: string }>,
  ) {
    for (const grain of [...grains].sort((left, right) =>
      grainKey(left.summaryDate, left.storeCode).localeCompare(
        grainKey(right.summaryDate, right.storeCode),
      ),
    )) {
      await tx.$queryRaw(Prisma.sql`
        SELECT pg_advisory_xact_lock(
          hashtextextended(${grainKey(grain.summaryDate, grain.storeCode)}, 0)
        )
      `);
    }
  }

  private async assertClaim(
    tx: Prisma.TransactionClient,
    jobId: string,
    claimToken: bigint,
  ) {
    const rows = await tx.$queryRaw<Array<{ id: string }>>(Prisma.sql`
      SELECT "id"
      FROM "SalesHistoryImportJob"
      WHERE "id" = ${jobId}
        AND "workerId" = ${this.workerId}
        AND "claimToken" = ${claimToken}
      FOR UPDATE
    `);
    if (rows.length !== 1) throw new ImportClaimLostError();
  }

  private async withClaim<T>(
    jobId: string,
    claimToken: bigint,
    operation: (tx: Prisma.TransactionClient) => Promise<T>,
  ) {
    return this.prisma.$transaction(async (tx) => {
      await this.assertClaim(tx, jobId, claimToken);
      return operation(tx);
    });
  }

  private async updateClaimedJob(
    jobId: string,
    claimToken: bigint,
    data: Prisma.SalesHistoryImportJobUpdateManyMutationInput,
  ) {
    const updated = await this.prisma.salesHistoryImportJob.updateMany({
      where: { id: jobId, workerId: this.workerId, claimToken },
      data,
    });
    if (updated.count !== 1) throw new ImportClaimLostError();
  }

  private async isCancelled(jobId: string, claimToken: bigint) {
    const job = await this.prisma.salesHistoryImportJob.findUnique({
      where: { id: jobId },
      select: { cancelRequestedAt: true, workerId: true, claimToken: true },
    });
    if (job?.workerId !== this.workerId || job.claimToken !== claimToken) {
      throw new ImportClaimLostError();
    }
    return job?.cancelRequestedAt != null;
  }

  private async actorForJob(jobId: string, claimToken: bigint) {
    const job = await this.prisma.salesHistoryImportJob.findUnique({
      where: { id: jobId },
      select: {
        requestedByUserId: true,
        workerId: true,
        claimToken: true,
      },
    });
    if (job?.workerId !== this.workerId || job.claimToken !== claimToken) {
      throw new ImportClaimLostError();
    }
    if (!job?.requestedByUserId) {
      throw new ForbiddenException(
        'Không xác định được người yêu cầu nhập dữ liệu. Vui lòng tải lại tệp.',
      );
    }
    return { id: job.requestedByUserId };
  }

  private async resolveFreshScope(
    user: any,
    client: Prisma.TransactionClient | PrismaService = this.prisma,
  ): Promise<FreshHistoryScope> {
    const actorUserId = cleanText(user?.id, 120);
    if (!actorUserId) {
      throw new ForbiddenException(
        'Không xác định được tài khoản. Vui lòng đăng nhập lại.',
      );
    }
    const savedUser = await client.user.findUnique({
      where: { id: actorUserId },
      include: {
        store: true,
        organizationAssignments: {
          where: { isActive: true },
          orderBy: [
            { isPrimary: Prisma.SortOrder.desc },
            { createdAt: Prisma.SortOrder.asc },
          ],
          include: {
            organizationNode: {
              include: organizationNodeStoreTreeInclude(),
            },
          },
        },
      },
    });
    if (!savedUser) {
      throw new ForbiddenException(
        'Tài khoản không còn hoạt động. Vui lòng đăng nhập lại.',
      );
    }
    if (isSuperAdminRole(savedUser.role)) {
      return { actorUserId, storeCodes: null };
    }
    const storeCodes = new Set<string>();
    const directStore = normalizeStoreCode(savedUser.store?.storeId);
    if (directStore) storeCodes.add(directStore);
    for (const assignment of savedUser.organizationAssignments ?? []) {
      for (const store of storesForOrganizationNodeTree(
        assignment.organizationNode,
      )) {
        const storeCode = normalizeStoreCode(store.storeId);
        if (storeCode) storeCodes.add(storeCode);
      }
    }
    return { actorUserId, storeCodes };
  }

  private assertHasTargetScope(scope: FreshHistoryScope) {
    if (scope.storeCodes != null && scope.storeCodes.size === 0) {
      throw new ForbiddenException(
        'Tài khoản chưa được gán showroom để nhập dữ liệu lịch sử.',
      );
    }
  }

  private async assertStoreScope(
    user: any,
    storeCodes: string[],
    client: Prisma.TransactionClient | PrismaService = this.prisma,
  ) {
    const scope = await this.resolveFreshScope(user, client);
    this.assertHasTargetScope(scope);
    if (scope.storeCodes == null) return scope;
    const invalid = Array.from(
      new Set(storeCodes.map(normalizeStoreCode).filter(Boolean)),
    ).find((storeCode) => !scope.storeCodes!.has(storeCode));
    if (invalid) {
      throw new ForbiddenException(
        'Chỉ được xử lý dữ liệu lịch sử trong phạm vi showroom được gán.',
      );
    }
    return scope;
  }

  private async assertJobScope(user: any, job: any) {
    const storeCodes = [
      ...(job?.version?.coverage ?? []).map((grain: any) => grain.storeCode),
      ...(job?.stagedGrains ?? []).map((grain: any) => grain.storeCode),
    ];
    if (storeCodes.length > 0) {
      await this.assertStoreScope(user, storeCodes);
      return;
    }
    const scope = await this.resolveFreshScope(user);
    this.assertHasTargetScope(scope);
    if (
      scope.storeCodes != null &&
      cleanText(job?.requestedByUserId, 120) !== scope.actorUserId
    ) {
      throw new ForbiddenException(
        'Chỉ được xem tác vụ đang chờ do chính bạn tạo.',
      );
    }
  }

  private userFailureMessage(error: unknown) {
    if (error instanceof BadRequestException) {
      const response = error.getResponse();
      if (typeof response === 'string') return response.slice(0, 500);
      if (response && typeof response === 'object') {
        const message = (response as { message?: unknown }).message;
        if (typeof message === 'string') return message.slice(0, 500);
      }
    }
    return 'Chưa phân tích được tệp. Vui lòng kiểm tra dữ liệu rồi thử lại.';
  }

  private toJobResponse(job: any) {
    const coverage = Array.isArray(job?.version?.coverage)
      ? job.version.coverage.map((grain: any) => ({
          date: dateKey(grain.summaryDate),
          storeCode: grain.storeCode,
          status: grain.status,
          rowCount: grain.rowCount,
          quarantinedRows: grain.quarantinedRows,
          reasonCodes: grain.reasonCodes,
        }))
      : undefined;
    return {
      id: job.id,
      status: job.status,
      uploadedBytes: Number(job.uploadedBytes ?? 0),
      expectedBytes: Number(job.expectedBytes ?? job.uploadedBytes ?? 0),
      totalRows: job.totalRows,
      cleanRows: job.cleanRows,
      quarantinedRows: job.quarantinedRows,
      cleanGrains: job.cleanGrains,
      quarantinedGrains: job.quarantinedGrains,
      failureMessage: job.failureMessage,
      versionId: job.versionId,
      cancelRequested: job.cancelRequestedAt != null,
      createdAt: job.createdAt,
      completedAt: job.completedAt,
      ...(coverage ? { coverage } : {}),
    };
  }

  private async cleanupStaleArtifacts() {
    const cutoff = Date.now() - IMPORT_ARTIFACT_TTL_MS;
    try {
      for (const name of await readdir(SALES_HISTORY_IMPORT_DIRECTORY)) {
        const path = join(SALES_HISTORY_IMPORT_DIRECTORY, name);
        const info = await stat(path);
        if (info.isFile() && info.mtimeMs < cutoff) await unlink(path);
      }
      const expired = await this.prisma.salesHistoryImportJob.findMany({
        where: {
          status: { in: ['UPLOADING', 'QUEUED', 'PARSING', 'FINALIZING'] },
          updatedAt: { lt: new Date(cutoff) },
        },
        select: { id: true, artifactPath: true, claimToken: true },
      });
      for (const job of expired) {
        const claimed = await this.prisma.$transaction(async (tx) => {
          const claim = await tx.salesHistoryImportJob.updateMany({
            where: {
              id: job.id,
              claimToken: job.claimToken,
              status: {
                in: ['UPLOADING', 'QUEUED', 'PARSING', 'FINALIZING'],
              },
              updatedAt: { lt: new Date(cutoff) },
            },
            data: {
              workerId: this.workerId,
              claimToken: { increment: 1 },
            },
          });
          if (claim.count !== 1) return false;
          const cleanupToken = job.claimToken + 1n;
          await tx.salesHistoryImportOrderStage.deleteMany({
            where: { jobId: job.id },
          });
          await tx.salesHistoryImportGrainStage.deleteMany({
            where: { jobId: job.id },
          });
          const finished = await tx.salesHistoryImportJob.updateMany({
            where: {
              id: job.id,
              workerId: this.workerId,
              claimToken: cleanupToken,
            },
            data: {
              status: 'FAILED',
              failureCode: 'IMPORT_EXPIRED',
              failureMessage:
                'Tác vụ đã hết hạn. Vui lòng chọn tệp và thử lại.',
              completedAt: new Date(),
              artifactPath: null,
              workerId: null,
              leaseExpiresAt: null,
              heartbeatAt: null,
            },
          });
          return finished.count === 1;
        });
        if (claimed && job.artifactPath) {
          await unlink(job.artifactPath).catch(() => undefined);
        }
      }
    } catch (error) {
      this.logger.warn(
        `Sales history artifact cleanup skipped: error=${safeLogError(error)}`,
      );
    }
  }
}

class ImportClaimLostError extends Error {
  constructor() {
    super('sales_history_import_claim_lost');
    this.name = 'ImportClaimLostError';
  }
}

function addUniqueIdentity(
  index: Map<string, string | null>,
  rawKey: string,
  userId: string,
) {
  const key = rawKey.trim();
  if (!key) return;
  const previous = index.get(key);
  index.set(key, previous === undefined || previous === userId ? userId : null);
}

function dateKey(value: Date) {
  return new Date(value).toISOString().slice(0, 10);
}

function grainKey(date: Date, storeCode: string) {
  return `${dateKey(date)}|${storeCode}`;
}

function cleanText(value: unknown, max: number) {
  const text = String(value ?? '').trim();
  return text ? text.slice(0, max) : null;
}

function normalizeStoreCode(value: unknown) {
  return String(value ?? '')
    .trim()
    .toUpperCase();
}

function safeActor(user: any) {
  const id = cleanText(user?.id, 80);
  return id ? `userId:${id}` : 'unknown';
}

function errorCode(error: unknown) {
  if (error instanceof BadRequestException) return 'INVALID_IMPORT_FILE';
  return error instanceof Error ? error.name.slice(0, 80) : 'IMPORT_FAILED';
}

function csvCell(value: string) {
  return `"${value.replace(/"/g, '""')}"`;
}
