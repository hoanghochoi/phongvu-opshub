import { SalesHistoryImportService } from './sales-history-import.service';

function advisoryLockKeys(executeRaw: jest.Mock) {
  return executeRaw.mock.calls.map(([statement]) => statement.values[0]);
}

describe('SalesHistoryImportService activation lifecycle', () => {
  it('activates clean grains transactionally and emits one home invalidation', async () => {
    const firstDate = new Date('2025-08-10T00:00:00.000Z');
    const secondDate = new Date('2025-08-11T00:00:00.000Z');
    const tx = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'admin-1',
          role: 'SUPER_ADMIN',
          store: null,
          organizationAssignments: [],
        }),
      },
      salesHistoryVersion: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'version-1',
          coverage: [
            { summaryDate: secondDate, storeCode: 'CP02' },
            { summaryDate: firstDate, storeCode: 'CP01' },
          ],
        }),
      },
      salesHistoryActiveGrain: {
        findMany: jest.fn().mockResolvedValue([
          {
            summaryDate: firstDate,
            storeCode: 'CP01',
            currentVersionId: 'version-0',
          },
        ]),
        upsert: jest.fn().mockResolvedValue(undefined),
      },
      salesHistoryActivation: {
        create: jest.fn().mockResolvedValue({ id: 'activation-1' }),
      },
      salesHistoryActivationGrain: {
        createMany: jest.fn().mockResolvedValue({ count: 2 }),
      },
      domainOutboxEvent: {
        create: jest.fn().mockResolvedValue(undefined),
      },
      $queryRaw: jest.fn().mockResolvedValue([{ version: 101n }]),
      $executeRaw: jest.fn().mockResolvedValue(1),
    };
    const prisma = {
      $transaction: jest.fn(async (operation: (client: any) => unknown) =>
        operation(tx),
      ),
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);

    await expect(
      service.activate({ id: 'admin-1' }, 'version-1'),
    ).resolves.toEqual({
      versionId: 'version-1',
      status: 'ACTIVE',
      activationId: 'activation-1',
      grainCount: 2,
    });

    expect(prisma.$transaction).toHaveBeenCalledTimes(1);
    expect(tx.salesHistoryActiveGrain.upsert).toHaveBeenCalledTimes(2);
    expect(tx.salesHistoryActivationGrain.createMany).toHaveBeenCalledWith({
      data: expect.arrayContaining([
        expect.objectContaining({
          summaryDate: firstDate,
          storeCode: 'CP01',
          fromVersionId: 'version-0',
          toVersionId: 'version-1',
        }),
        expect.objectContaining({
          summaryDate: secondDate,
          storeCode: 'CP02',
          fromVersionId: null,
          toVersionId: 'version-1',
        }),
      ]),
    });
    expect(tx.domainOutboxEvent.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        eventType: 'HOME_SUMMARY_UPDATED',
        aggregateId: 'version-1',
        schemaVersion: 2,
        payload: {
          affectedDates: ['2025-08-10', '2025-08-11'],
          projectionVersion: 101,
        },
      }),
    });
    expect(tx.$queryRaw).toHaveBeenCalledTimes(1);
    expect(tx.$executeRaw).toHaveBeenCalledTimes(2);
    expect(advisoryLockKeys(tx.$executeRaw)).toEqual([
      '2025-08-10|CP01',
      '2025-08-11|CP02',
    ]);
  });

  it('rolls back only grains still pointing at the selected version', async () => {
    const firstDate = new Date('2025-08-10T00:00:00.000Z');
    const secondDate = new Date('2025-08-11T00:00:00.000Z');
    const skippedDate = new Date('2025-08-12T00:00:00.000Z');
    const tx = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'admin-1',
          role: 'SUPER_ADMIN',
          store: null,
          organizationAssignments: [],
        }),
      },
      salesHistoryActivation: {
        findFirst: jest.fn().mockResolvedValue({
          id: 'activation-1',
          grains: [
            {
              summaryDate: firstDate,
              storeCode: 'CP01',
              fromVersionId: 'version-0',
            },
            {
              summaryDate: secondDate,
              storeCode: 'CP02',
              fromVersionId: null,
            },
            {
              summaryDate: skippedDate,
              storeCode: 'CP03',
              fromVersionId: 'version-old',
            },
          ],
        }),
        create: jest.fn().mockResolvedValue({ id: 'rollback-1' }),
      },
      salesHistoryActiveGrain: {
        findMany: jest.fn().mockResolvedValue([
          {
            summaryDate: firstDate,
            storeCode: 'CP01',
            currentVersionId: 'version-1',
          },
          {
            summaryDate: secondDate,
            storeCode: 'CP02',
            currentVersionId: 'version-1',
          },
          {
            summaryDate: skippedDate,
            storeCode: 'CP03',
            currentVersionId: 'version-newer',
          },
        ]),
        update: jest.fn().mockResolvedValue(undefined),
        delete: jest.fn().mockResolvedValue(undefined),
      },
      salesHistoryActivationGrain: {
        createMany: jest.fn().mockResolvedValue({ count: 2 }),
      },
      domainOutboxEvent: {
        create: jest.fn().mockResolvedValue(undefined),
      },
      $queryRaw: jest.fn().mockResolvedValue([{ version: 102n }]),
      $executeRaw: jest.fn().mockResolvedValue(1),
    };
    const prisma = {
      $transaction: jest.fn(async (operation: (client: any) => unknown) =>
        operation(tx),
      ),
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);

    await expect(
      service.rollback({ id: 'admin-1' }, 'version-1'),
    ).resolves.toEqual({
      versionId: 'version-1',
      status: 'ROLLED_BACK',
      activationId: 'rollback-1',
      grainCount: 2,
    });

    expect(tx.salesHistoryActiveGrain.update).toHaveBeenCalledTimes(1);
    expect(tx.salesHistoryActiveGrain.update).toHaveBeenCalledWith({
      where: {
        summaryDate_storeCode: {
          summaryDate: firstDate,
          storeCode: 'CP01',
        },
      },
      data: {
        currentVersionId: 'version-0',
        activatedAt: expect.any(Date),
      },
    });
    expect(tx.salesHistoryActiveGrain.delete).toHaveBeenCalledTimes(1);
    expect(tx.salesHistoryActiveGrain.delete).toHaveBeenCalledWith({
      where: {
        summaryDate_storeCode: {
          summaryDate: secondDate,
          storeCode: 'CP02',
        },
      },
    });
    expect(tx.salesHistoryActivationGrain.createMany).toHaveBeenCalledWith({
      data: expect.not.arrayContaining([
        expect.objectContaining({ storeCode: 'CP03' }),
      ]),
    });
    expect(tx.domainOutboxEvent.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        aggregateId: 'rollback-version-1',
        payload: {
          affectedDates: ['2025-08-10', '2025-08-11'],
          projectionVersion: 102,
        },
      }),
    });
    expect(tx.$queryRaw).toHaveBeenCalledTimes(1);
    expect(tx.$executeRaw).toHaveBeenCalledTimes(3);
    expect(advisoryLockKeys(tx.$executeRaw)).toEqual([
      '2025-08-10|CP01',
      '2025-08-11|CP02',
      '2025-08-12|CP03',
    ]);
  });

  it('fails closed when fresh scope was reassigned before activation', async () => {
    const tx = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'admin-1',
          role: 'ADMIN',
          store: { storeId: 'CP01' },
          organizationAssignments: [],
        }),
      },
      salesHistoryVersion: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'version-2',
          coverage: [
            {
              summaryDate: new Date('2025-08-10T00:00:00Z'),
              storeCode: 'CP02',
            },
          ],
        }),
      },
    };
    const prisma = {
      $transaction: jest.fn(async (operation: (client: any) => unknown) =>
        operation(tx),
      ),
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);

    await expect(
      service.activate({ id: 'admin-1', role: 'SUPER_ADMIN' }, 'version-2'),
    ).rejects.toThrow('phạm vi showroom được gán');
  });

  it('fails closed when fresh scope was reassigned before rollback', async () => {
    const tx = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'admin-1',
          role: 'ADMIN',
          store: { storeId: 'CP01' },
          organizationAssignments: [],
        }),
      },
      salesHistoryActivation: {
        findFirst: jest.fn().mockResolvedValue({
          id: 'activation-1',
          grains: [
            {
              summaryDate: new Date('2025-08-10T00:00:00Z'),
              storeCode: 'CP02',
              fromVersionId: 'version-0',
            },
          ],
        }),
      },
    };
    const prisma = {
      $transaction: jest.fn(async (operation: (client: any) => unknown) =>
        operation(tx),
      ),
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);

    await expect(
      service.rollback({ id: 'admin-1' }, 'version-1'),
    ).rejects.toThrow('phạm vi showroom được gán');
  });

  it('keeps activation replay idempotent so rollback history is not overwritten', async () => {
    const date = new Date('2025-08-10T00:00:00Z');
    const tx = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'admin-1',
          role: 'SUPER_ADMIN',
          store: null,
          organizationAssignments: [],
        }),
      },
      salesHistoryVersion: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'version-1',
          coverage: [{ summaryDate: date, storeCode: 'CP01' }],
        }),
      },
      salesHistoryActiveGrain: {
        findMany: jest.fn().mockResolvedValue([
          {
            summaryDate: date,
            storeCode: 'CP01',
            currentVersionId: 'version-1',
          },
        ]),
        upsert: jest.fn(),
      },
      salesHistoryActivation: {
        findFirst: jest.fn().mockResolvedValue({ id: 'activation-original' }),
        create: jest.fn(),
      },
      $executeRaw: jest.fn().mockResolvedValue(1),
    };
    const prisma = {
      $transaction: jest.fn(async (operation: (client: any) => unknown) =>
        operation(tx),
      ),
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);

    await expect(
      service.activate({ id: 'admin-1' }, 'version-1'),
    ).resolves.toEqual({
      versionId: 'version-1',
      status: 'ACTIVE',
      activationId: 'activation-original',
      grainCount: 1,
    });
    expect(tx.salesHistoryActivation.create).not.toHaveBeenCalled();
    expect(tx.salesHistoryActiveGrain.upsert).not.toHaveBeenCalled();
  });
});

describe('SalesHistoryImportService authorization and worker lifecycle', () => {
  it('enforces artifact quota before creating an upload job', async () => {
    const tx = {
      $executeRaw: jest.fn().mockResolvedValue(1),
      salesHistoryImportJob: {
        aggregate: jest.fn().mockResolvedValue({
          _sum: { expectedBytes: BigInt(220 * 1024 * 1024) },
        }),
        create: jest.fn(),
      },
    };
    const prisma = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'admin-1',
          role: 'SUPER_ADMIN',
          store: null,
          organizationAssignments: [],
        }),
      },
      $transaction: jest.fn(async (operation: (client: any) => unknown) =>
        operation(tx),
      ),
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);

    await expect(
      service.createUpload({ id: 'admin-1' }, 'history.csv', 1024),
    ).rejects.toThrow('đang xử lý một tệp lớn khác');
    expect(advisoryLockKeys(tx.$executeRaw)).toEqual([
      'sales-history-import-upload-admission',
    ]);
    expect(tx.salesHistoryImportJob.create).not.toHaveBeenCalled();
  });

  it('rejects an upload chunk on invalid fresh scope before disk mutation', async () => {
    const prisma = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'admin-1',
          role: 'ADMIN',
          store: { storeId: 'CP01' },
          organizationAssignments: [],
        }),
      },
      salesHistoryImportJob: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'job-1',
          status: 'UPLOADING',
          requestedByUserId: 'another-admin',
          uploadedBytes: 0n,
          expectedBytes: 10n,
          version: null,
          stagedGrains: [],
        }),
      },
      $transaction: jest.fn(),
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);

    await expect(
      service.appendUploadChunk({ id: 'admin-1' }, 'job-1', 0, {
        buffer: Buffer.from('abc'),
      } as any),
    ).rejects.toThrow('chính bạn tạo');
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('rejects reading a CP02 job for a freshly scoped CP01 actor', async () => {
    const prisma = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'admin-1',
          role: 'ADMIN',
          store: { storeId: 'CP01' },
          organizationAssignments: [],
        }),
      },
      salesHistoryImportJob: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'job-1',
          requestedByUserId: 'admin-1',
          uploadedBytes: 1n,
          version: { coverage: [{ storeCode: 'CP02' }] },
          stagedGrains: [],
        }),
      },
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);

    await expect(service.getJob({ id: 'admin-1' }, 'job-1')).rejects.toThrow(
      'phạm vi showroom được gán',
    );
  });

  it('checks fresh scope again at finalization', async () => {
    const tx = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'admin-1',
          role: 'ADMIN',
          store: { storeId: 'CP01' },
          organizationAssignments: [],
        }),
      },
      salesHistoryImportGrainStage: {
        findMany: jest.fn().mockResolvedValue([
          {
            summaryDate: new Date('2025-08-10T00:00:00Z'),
            storeCode: 'CP02',
            rowCount: 1,
            invalidRows: 0,
            reasonCodes: [],
          },
        ]),
      },
      salesHistoryVersion: { create: jest.fn() },
    };
    const prisma = {
      $transaction: jest.fn(async (operation: (client: any) => unknown) =>
        operation(tx),
      ),
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);

    await expect(
      (service as any).finalizeVersion({ id: 'admin-1' }, 'job-1', 'hash'),
    ).rejects.toThrow('phạm vi showroom được gán');
    expect(tx.salesHistoryVersion.create).not.toHaveBeenCalled();
  });

  it('requires email and HRM to resolve to the same showroom-bound user', () => {
    const service = new SalesHistoryImportService({} as any, {} as any);
    const row = {
      date: '2025-08-10',
      storeCode: 'CP01',
      orderCode: 'ORDER-1',
      salespersonEmail: 'sale@phongvu.vn',
      salespersonCode: 'NV001',
      signedRevenue: 1000,
      quantities: {},
      errorCodes: [],
    };
    const mismatch = (service as any).resolveRowIdentity(row, {
      byEmail: new Map([['sale@phongvu.vn', 'user-1']]),
      byPersonnelCode: new Map([['NV001', 'user-2']]),
      userStoreCodes: new Map([
        ['user-1', new Set(['CP01'])],
        ['user-2', new Set(['CP01'])],
      ]),
    });
    expect(mismatch.userId).toBeNull();
    expect(mismatch.reasons).toContain('SALESPERSON_IDENTITY_MISMATCH');

    const wrongStore = (service as any).resolveRowIdentity(
      { ...row, salespersonCode: null },
      {
        byEmail: new Map([['sale@phongvu.vn', 'user-1']]),
        byPersonnelCode: new Map(),
        userStoreCodes: new Map([['user-1', new Set(['CP02'])]]),
      },
    );
    expect(wrongStore.reasons).toContain('SALESPERSON_STORE_MISMATCH');
  });

  it('claims queued or expired jobs with a database lease CAS', async () => {
    const stale = {
      id: 'job-1',
      status: 'PARSING',
      artifactPath: 'C:/tmp/history.csv',
      attemptCount: 1,
    };
    const tx = {
      $executeRaw: jest.fn().mockResolvedValue(1),
      salesHistoryImportJob: {
        count: jest.fn().mockResolvedValue(0),
        findFirst: jest.fn().mockResolvedValue(stale),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
        findUnique: jest.fn().mockResolvedValue({ ...stale, attemptCount: 2 }),
      },
    };
    const prisma = {
      $transaction: jest.fn(async (operation: (client: any) => unknown) =>
        operation(tx),
      ),
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);

    await expect((service as any).claimNextJob()).resolves.toMatchObject({
      id: 'job-1',
      attemptCount: 2,
    });
    expect(tx.$executeRaw).toHaveBeenCalledTimes(2);
    expect(advisoryLockKeys(tx.$executeRaw)).toEqual([
      'sales-history-import-global-claim',
      'upload:job-1',
    ]);
    expect(tx.salesHistoryImportJob.count).toHaveBeenCalledWith({
      where: {
        status: { in: ['PARSING', 'FINALIZING'] },
        leaseExpiresAt: { gt: expect.any(Date) },
      },
    });
    expect(tx.salesHistoryImportJob.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          status: 'PARSING',
          workerId: expect.any(String),
          leaseExpiresAt: expect.any(Date),
          heartbeatAt: expect.any(Date),
          attemptCount: { increment: 1 },
        }),
      }),
    );
    expect(tx.salesHistoryImportJob.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          OR: expect.arrayContaining([
            expect.objectContaining({ status: 'QUEUED' }),
          ]),
        }),
      }),
    );
  });

  it('starts only one worker within the 256 MiB artifact budget', async () => {
    const service = new SalesHistoryImportService({} as any, {} as any) as any;
    const releases: Array<() => void> = [];
    service.claimNextJob = jest
      .fn()
      .mockResolvedValueOnce({ id: 'job-1' })
      .mockResolvedValueOnce({ id: 'job-2' })
      .mockResolvedValueOnce(null);
    service.processClaimedJob = jest.fn(
      () => new Promise<void>((resolve) => releases.push(resolve)),
    );

    await service.pumpJobs();
    expect(service.processClaimedJob).toHaveBeenCalledTimes(1);
    expect(service.activeWorkers).toBe(1);
    releases.forEach((release) => release());
    await new Promise((resolve) => setTimeout(resolve, 0));
  });

  it('does not claim when one unexpired lease already holds the global slot', async () => {
    const tx = {
      $executeRaw: jest.fn().mockResolvedValue(1),
      salesHistoryImportJob: {
        count: jest.fn().mockResolvedValue(1),
        findFirst: jest.fn(),
      },
    };
    const prisma = {
      $transaction: jest.fn(async (operation: (client: any) => unknown) =>
        operation(tx),
      ),
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);

    await expect((service as any).claimNextJob()).resolves.toBeNull();
    expect(tx.$executeRaw).toHaveBeenCalledTimes(1);
    expect(advisoryLockKeys(tx.$executeRaw)).toEqual([
      'sales-history-import-global-claim',
    ]);
    expect(tx.salesHistoryImportJob.findFirst).not.toHaveBeenCalled();
  });

  it('removes stages and expires stale durable jobs during TTL cleanup', async () => {
    const orderStage = {
      deleteMany: jest.fn().mockResolvedValue({ count: 1 }),
    };
    const grainStage = {
      deleteMany: jest.fn().mockResolvedValue({ count: 1 }),
    };
    const jobTable = {
      findMany: jest.fn().mockResolvedValue([
        {
          id: 'job-expired',
          artifactPath: 'C:/missing/history.csv',
          claimToken: 4n,
        },
      ]),
      updateMany: jest
        .fn()
        .mockResolvedValueOnce({ count: 1 })
        .mockResolvedValueOnce({ count: 1 }),
    };
    const prisma = {
      salesHistoryImportJob: jobTable,
      salesHistoryImportOrderStage: orderStage,
      salesHistoryImportGrainStage: grainStage,
      $transaction: jest.fn(async (operation: (client: any) => unknown) =>
        operation({
          salesHistoryImportJob: jobTable,
          salesHistoryImportOrderStage: orderStage,
          salesHistoryImportGrainStage: grainStage,
        }),
      ),
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);

    await (service as any).cleanupStaleArtifacts();
    expect(prisma.salesHistoryImportOrderStage.deleteMany).toHaveBeenCalledWith(
      {
        where: { jobId: 'job-expired' },
      },
    );
    expect(prisma.salesHistoryImportGrainStage.deleteMany).toHaveBeenCalledWith(
      {
        where: { jobId: 'job-expired' },
      },
    );
    expect(prisma.salesHistoryImportJob.updateMany).toHaveBeenLastCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          id: 'job-expired',
          claimToken: 5n,
        }),
        data: expect.objectContaining({ status: 'FAILED', artifactPath: null }),
      }),
    );
  });

  it('fences stale worker A after worker B reclaims the job', async () => {
    const tx = {
      $queryRaw: jest.fn().mockResolvedValue([]),
      $executeRaw: jest.fn(),
    };
    const prisma = {
      $transaction: jest.fn(async (operation: (client: any) => unknown) =>
        operation(tx),
      ),
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);

    await expect(
      (service as any).stageChunk('job-1', 7n, [], {
        storeCodes: new Set(),
        byEmail: new Map(),
        byPersonnelCode: new Map(),
        userStoreCodes: new Map(),
      }),
    ).rejects.toThrow('sales_history_import_claim_lost');
    expect(tx.$executeRaw).not.toHaveBeenCalled();
  });

  it('cancels queued jobs atomically and removes their stage rows', async () => {
    const job = {
      id: 'job-queued',
      status: 'QUEUED',
      workerId: null,
      claimToken: 0n,
      requestedByUserId: 'admin-1',
      artifactPath: 'C:/missing/history.csv',
      uploadedBytes: 10n,
      version: null,
      stagedGrains: [],
    };
    const tx = {
      salesHistoryImportOrderStage: {
        deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
      },
      salesHistoryImportGrainStage: {
        deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
      },
      salesHistoryImportJob: {
        findUnique: jest
          .fn()
          .mockResolvedValueOnce(job)
          .mockResolvedValueOnce({ ...job, status: 'CANCELLED' }),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      $executeRaw: jest.fn().mockResolvedValue(1),
    };
    const prisma = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'admin-1',
          role: 'SUPER_ADMIN',
          store: null,
          organizationAssignments: [],
        }),
      },
      salesHistoryImportJob: { findUnique: jest.fn().mockResolvedValue(job) },
      $transaction: jest.fn(async (operation: (client: any) => unknown) =>
        operation(tx),
      ),
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);

    await expect(
      service.cancelJob({ id: 'admin-1' }, job.id),
    ).resolves.toMatchObject({
      id: job.id,
      status: 'CANCELLED',
    });
    expect(advisoryLockKeys(tx.$executeRaw)).toEqual([`upload:${job.id}`]);
    expect(tx.salesHistoryImportOrderStage.deleteMany).toHaveBeenCalledWith({
      where: { jobId: job.id },
    });
    expect(tx.salesHistoryImportGrainStage.deleteMany).toHaveBeenCalledWith({
      where: { jobId: job.id },
    });
    expect(tx.salesHistoryImportJob.updateMany).toHaveBeenCalledWith({
      where: {
        id: job.id,
        status: 'QUEUED',
        workerId: null,
        claimToken: 0n,
      },
      data: expect.objectContaining({
        status: 'CANCELLED',
        artifactPath: null,
      }),
    });
  });

  it('retains the artifact when another worker claims between scope read and cancellation', async () => {
    const initialJob = {
      id: 'job-racing',
      status: 'QUEUED',
      workerId: null,
      claimToken: 0n,
      requestedByUserId: 'admin-1',
      artifactPath: 'C:/missing/history.csv',
      uploadedBytes: 10n,
      version: null,
      stagedGrains: [],
    };
    const claimedJob = {
      ...initialJob,
      status: 'PARSING',
      workerId: 'worker-b',
      claimToken: 1n,
    };
    const tx = {
      salesHistoryImportOrderStage: { deleteMany: jest.fn() },
      salesHistoryImportGrainStage: { deleteMany: jest.fn() },
      salesHistoryImportJob: {
        findUnique: jest
          .fn()
          .mockResolvedValueOnce(claimedJob)
          .mockResolvedValueOnce({
            ...claimedJob,
            cancelRequestedAt: new Date('2026-08-10T00:00:00.000Z'),
          }),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      $executeRaw: jest.fn().mockResolvedValue(1),
    };
    const prisma = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'admin-1',
          role: 'SUPER_ADMIN',
          store: null,
          organizationAssignments: [],
        }),
      },
      salesHistoryImportJob: {
        findUnique: jest.fn().mockResolvedValue(initialJob),
      },
      $transaction: jest.fn(async (operation: (client: any) => unknown) =>
        operation(tx),
      ),
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);

    await expect(
      service.cancelJob({ id: 'admin-1' }, initialJob.id),
    ).resolves.toMatchObject({
      id: initialJob.id,
      status: 'PARSING',
      cancelRequested: true,
    });

    expect(tx.$executeRaw).toHaveBeenCalledTimes(1);
    expect(advisoryLockKeys(tx.$executeRaw)).toEqual([
      `upload:${initialJob.id}`,
    ]);
    expect(tx.salesHistoryImportJob.updateMany).toHaveBeenCalledWith({
      where: {
        id: initialJob.id,
        status: 'PARSING',
        workerId: 'worker-b',
        claimToken: 1n,
      },
      data: { cancelRequestedAt: expect.any(Date) },
    });
    expect(tx.salesHistoryImportOrderStage.deleteMany).not.toHaveBeenCalled();
    expect(tx.salesHistoryImportGrainStage.deleteMany).not.toHaveBeenCalled();
    expect(
      tx.salesHistoryImportJob.updateMany.mock.calls[0][0].data,
    ).not.toHaveProperty('artifactPath');
  });
});
