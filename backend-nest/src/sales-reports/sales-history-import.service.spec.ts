jest.mock('node:fs/promises', () => {
  const actual = jest.requireActual('node:fs/promises');
  return {
    ...actual,
    open: jest.fn(actual.open),
    unlink: jest.fn(actual.unlink),
  };
});

import { access, open, rm, stat, unlink } from 'node:fs/promises';
import { createHash } from 'node:crypto';
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
      salesHistoryImportJob: {
        findUnique: jest.fn().mockResolvedValue(null),
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

  it('creates the admitted artifact before accepting the first chunk at offset zero', async () => {
    let admittedJob: any;
    const tx = {
      $executeRaw: jest.fn().mockResolvedValue(1),
      salesHistoryImportJob: {
        aggregate: jest.fn().mockResolvedValue({
          _sum: { expectedBytes: 0n },
        }),
        create: jest.fn(({ data }) => {
          admittedJob = {
            id: 'job-1',
            ...data,
            totalRows: null,
            cleanRows: null,
            quarantinedRows: null,
            cleanGrains: null,
            quarantinedGrains: null,
            failureMessage: null,
            versionId: null,
            cancelRequestedAt: null,
            createdAt: new Date(),
            completedAt: null,
          };
          return admittedJob;
        }),
        findUnique: jest
          .fn()
          .mockImplementationOnce(() => admittedJob)
          .mockImplementationOnce(() => ({
            ...admittedJob,
            uploadedBytes: 3n,
          })),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
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
      salesHistoryImportJob: {
        findUnique: jest.fn().mockImplementation(() => ({
          ...admittedJob,
          version: null,
          stagedGrains: [],
        })),
      },
      $transaction: jest.fn(async (operation: (client: any) => unknown) =>
        operation(tx),
      ),
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);

    try {
      await service.createUpload({ id: 'admin-1' }, 'history.csv', 3);
      await expect(access(admittedJob.artifactPath)).resolves.toBeUndefined();
      if (process.platform !== 'win32') {
        expect((await stat(admittedJob.artifactPath)).mode & 0o077).toBe(0);
      }

      await expect(
        service.appendUploadChunk({ id: 'admin-1' }, admittedJob.id, 0, {
          buffer: Buffer.from('abc'),
        } as any),
      ).resolves.toMatchObject({ id: admittedJob.id, uploadedBytes: 3 });
    } finally {
      if (admittedJob?.artifactPath) {
        await rm(admittedJob.artifactPath, { force: true });
        await expect(access(admittedJob.artifactPath)).rejects.toMatchObject({
          code: 'ENOENT',
        });
      }
    }
  });

  it('removes the newly created artifact when persisting its upload job fails', async () => {
    const mockOpen = jest.mocked(open);
    const mockUnlink = jest.mocked(unlink);
    const close = jest.fn().mockResolvedValue(undefined);
    mockOpen.mockClear();
    mockUnlink.mockClear();
    mockOpen.mockImplementationOnce(async () => ({ close }) as any);
    mockUnlink.mockImplementationOnce(async () => undefined);
    const tx = {
      $executeRaw: jest.fn().mockResolvedValue(1),
      salesHistoryImportJob: {
        aggregate: jest.fn().mockResolvedValue({
          _sum: { expectedBytes: 0n },
        }),
        create: jest.fn().mockRejectedValue(new Error('database unavailable')),
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
      salesHistoryImportJob: {
        findUnique: jest.fn().mockResolvedValue(null),
      },
      $transaction: jest.fn(async (operation: (client: any) => unknown) =>
        operation(tx),
      ),
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);

    await expect(
      service.createUpload({ id: 'admin-1' }, 'history.csv', 3),
    ).rejects.toThrow('database unavailable');
    expect(mockOpen).toHaveBeenCalledWith(expect.any(String), 'wx', 0o600);
    expect(close).toHaveBeenCalledTimes(1);
    expect(mockUnlink).toHaveBeenCalledWith(expect.any(String));
  });

  it('recovers a committed admission when the transaction result is ambiguous', async () => {
    const actualFs = jest.requireActual(
      'node:fs/promises',
    ) as typeof import('node:fs/promises');
    const mockOpen = jest.mocked(open);
    const mockUnlink = jest.mocked(unlink);
    let admittedJob: any;
    mockOpen.mockClear();
    mockUnlink.mockClear();
    mockOpen.mockImplementation(actualFs.open);
    mockUnlink.mockImplementation(actualFs.unlink);
    const tx = {
      $executeRaw: jest.fn().mockResolvedValue(1),
      salesHistoryImportJob: {
        aggregate: jest.fn().mockResolvedValue({
          _sum: { expectedBytes: 0n },
        }),
        create: jest.fn(({ data }) => {
          admittedJob = {
            ...data,
            totalRows: null,
            cleanRows: null,
            quarantinedRows: null,
            cleanGrains: null,
            quarantinedGrains: null,
            failureMessage: null,
            versionId: null,
            cancelRequestedAt: null,
            createdAt: new Date(),
            completedAt: null,
          };
          return admittedJob;
        }),
        findUnique: jest
          .fn()
          .mockImplementationOnce(() => admittedJob)
          .mockImplementationOnce(() => ({
            ...admittedJob,
            uploadedBytes: 3n,
          })),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
    };
    let transactionCalls = 0;
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
        findUnique: jest.fn().mockImplementation(() => admittedJob),
      },
      $transaction: jest.fn(async (operation: (client: any) => unknown) => {
        const result = await operation(tx);
        if (transactionCalls++ === 0) {
          throw new Error('transaction result unavailable');
        }
        return result;
      }),
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);

    try {
      const recovered = await service.createUpload(
        { id: 'admin-1' },
        'history.csv',
        3,
      );
      expect(recovered.id).toBe(admittedJob.id);
      expect(tx.salesHistoryImportJob.create).toHaveBeenCalledTimes(1);
      expect(mockUnlink).not.toHaveBeenCalled();
      await expect(access(admittedJob.artifactPath)).resolves.toBeUndefined();

      await expect(
        service.appendUploadChunk({ id: 'admin-1' }, recovered.id, 0, {
          buffer: Buffer.from('abc'),
        } as any),
      ).resolves.toMatchObject({ id: recovered.id, uploadedBytes: 3 });
    } finally {
      if (admittedJob?.artifactPath) {
        await rm(admittedJob.artifactPath, { force: true });
      }
      mockOpen.mockImplementation(actualFs.open);
      mockUnlink.mockImplementation(actualFs.unlink);
    }
  });

  it('retains the artifact when ambiguous admission reconciliation is unavailable', async () => {
    const actualFs = jest.requireActual(
      'node:fs/promises',
    ) as typeof import('node:fs/promises');
    const mockOpen = jest.mocked(open);
    const mockUnlink = jest.mocked(unlink);
    let admittedJob: any;
    mockOpen.mockClear();
    mockUnlink.mockClear();
    mockOpen.mockImplementation(actualFs.open);
    mockUnlink.mockImplementation(actualFs.unlink);
    const tx = {
      $executeRaw: jest.fn().mockResolvedValue(1),
      salesHistoryImportJob: {
        aggregate: jest.fn().mockResolvedValue({
          _sum: { expectedBytes: 0n },
        }),
        create: jest.fn(({ data }) => {
          admittedJob = {
            ...data,
            totalRows: null,
            cleanRows: null,
            quarantinedRows: null,
            cleanGrains: null,
            quarantinedGrains: null,
            failureMessage: null,
            versionId: null,
            cancelRequestedAt: null,
            createdAt: new Date(),
            completedAt: null,
          };
          return admittedJob;
        }),
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
      salesHistoryImportJob: {
        findUnique: jest
          .fn()
          .mockRejectedValue(new Error('reconciliation unavailable')),
      },
      $transaction: jest.fn(async (operation: (client: any) => unknown) => {
        await operation(tx);
        throw new Error('transaction result unavailable');
      }),
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);

    try {
      await expect(
        service.createUpload({ id: 'admin-1' }, 'history.csv', 3),
      ).rejects.toThrow('transaction result unavailable');
      expect(tx.salesHistoryImportJob.create).toHaveBeenCalledTimes(1);
      expect(prisma.salesHistoryImportJob.findUnique).toHaveBeenCalledWith({
        where: { id: admittedJob.id },
      });
      expect(mockUnlink).not.toHaveBeenCalled();
      await expect(access(admittedJob.artifactPath)).resolves.toBeUndefined();
    } finally {
      if (admittedJob?.artifactPath) {
        await rm(admittedJob.artifactPath, { force: true });
      }
      mockOpen.mockImplementation(actualFs.open);
      mockUnlink.mockImplementation(actualFs.unlink);
    }
  });

  it('removes only the generated artifact when reconciliation finds another path', async () => {
    const mockOpen = jest.mocked(open);
    const mockUnlink = jest.mocked(unlink);
    const close = jest.fn().mockResolvedValue(undefined);
    let admittedJob: any;
    let generatedArtifactPath: string | undefined;
    const persistedArtifactPath = 'C:/tmp/existing-other.upload';
    mockOpen.mockClear();
    mockUnlink.mockClear();
    mockOpen.mockImplementationOnce(async (path) => {
      generatedArtifactPath = String(path);
      return { close } as any;
    });
    mockUnlink.mockResolvedValueOnce(undefined);
    const tx = {
      $executeRaw: jest.fn().mockResolvedValue(1),
      salesHistoryImportJob: {
        aggregate: jest.fn().mockResolvedValue({
          _sum: { expectedBytes: 0n },
        }),
        create: jest.fn(({ data }) => {
          admittedJob = { ...data };
          return admittedJob;
        }),
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
      salesHistoryImportJob: {
        findUnique: jest.fn().mockImplementation(() => ({
          ...admittedJob,
          artifactPath: persistedArtifactPath,
        })),
      },
      $transaction: jest.fn(async (operation: (client: any) => unknown) => {
        await operation(tx);
        throw new Error('transaction result unavailable');
      }),
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);

    await expect(
      service.createUpload({ id: 'admin-1' }, 'history.csv', 3),
    ).rejects.toThrow('transaction result unavailable');
    expect(tx.salesHistoryImportJob.create).toHaveBeenCalledTimes(1);
    expect(mockUnlink).toHaveBeenCalledTimes(1);
    expect(mockUnlink).toHaveBeenCalledWith(generatedArtifactPath);
    expect(mockUnlink).not.toHaveBeenCalledWith(persistedArtifactPath);
  });

  it('compensates a database admission failure by unlinking the exact real artifact', async () => {
    const actualFs = jest.requireActual(
      'node:fs/promises',
    ) as typeof import('node:fs/promises');
    const mockOpen = jest.mocked(open);
    const mockUnlink = jest.mocked(unlink);
    let artifactPath: string | undefined;
    mockOpen.mockClear();
    mockUnlink.mockClear();
    mockOpen.mockImplementation(async (path, flags, mode) => {
      artifactPath = String(path);
      return actualFs.open(path, flags, mode);
    });
    mockUnlink.mockImplementation(actualFs.unlink);
    const tx = {
      $executeRaw: jest.fn().mockResolvedValue(1),
      salesHistoryImportJob: {
        aggregate: jest.fn().mockResolvedValue({
          _sum: { expectedBytes: 0n },
        }),
        create: jest.fn().mockRejectedValue(new Error('database unavailable')),
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
      salesHistoryImportJob: {
        findUnique: jest.fn().mockResolvedValue(null),
      },
      $transaction: jest.fn(async (operation: (client: any) => unknown) =>
        operation(tx),
      ),
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);

    try {
      await expect(
        service.createUpload({ id: 'admin-1' }, 'history.csv', 3),
      ).rejects.toThrow('database unavailable');
      expect(artifactPath).toEqual(expect.any(String));
      expect(mockUnlink).toHaveBeenCalledWith(artifactPath);
      await expect(access(artifactPath!)).rejects.toMatchObject({
        code: 'ENOENT',
      });
    } finally {
      if (artifactPath) await rm(artifactPath, { force: true });
      mockOpen.mockImplementation(actualFs.open);
      mockUnlink.mockImplementation(actualFs.unlink);
    }
  });

  it('does not create a job when its artifact parent cannot be opened', async () => {
    const mockOpen = jest.mocked(open);
    const mockUnlink = jest.mocked(unlink);
    const missingParent = Object.assign(new Error('ENOENT'), {
      code: 'ENOENT',
    });
    mockOpen.mockClear();
    mockUnlink.mockClear();
    mockOpen.mockRejectedValueOnce(missingParent);
    const tx = {
      $executeRaw: jest.fn().mockResolvedValue(1),
      salesHistoryImportJob: {
        aggregate: jest.fn().mockResolvedValue({
          _sum: { expectedBytes: 0n },
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
      salesHistoryImportJob: {
        findUnique: jest.fn().mockResolvedValue(null),
      },
      $transaction: jest.fn(async (operation: (client: any) => unknown) =>
        operation(tx),
      ),
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);
    const warn = jest.spyOn((service as any).logger, 'warn');

    await expect(
      service.createUpload({ id: 'admin-1' }, 'history.csv', 3),
    ).rejects.toThrow('ENOENT');
    expect(tx.salesHistoryImportJob.create).not.toHaveBeenCalled();
    expect(mockUnlink).not.toHaveBeenCalled();
    expect(warn).toHaveBeenCalledWith(
      expect.stringContaining('admission failed'),
    );
  });

  it('cleans up and logs when closing a newly created artifact fails', async () => {
    const mockOpen = jest.mocked(open);
    const mockUnlink = jest.mocked(unlink);
    mockOpen.mockClear();
    mockUnlink.mockClear();
    mockOpen.mockImplementationOnce(
      async () =>
        ({
          close: jest.fn().mockRejectedValue(new Error('close unavailable')),
        }) as any,
    );
    mockUnlink.mockResolvedValueOnce(undefined);
    const tx = {
      $executeRaw: jest.fn().mockResolvedValue(1),
      salesHistoryImportJob: {
        aggregate: jest.fn().mockResolvedValue({
          _sum: { expectedBytes: 0n },
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
      salesHistoryImportJob: {
        findUnique: jest.fn().mockResolvedValue(null),
      },
      $transaction: jest.fn(async (operation: (client: any) => unknown) =>
        operation(tx),
      ),
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);
    const warn = jest.spyOn((service as any).logger, 'warn');

    await expect(
      service.createUpload({ id: 'admin-1' }, 'history.csv', 3),
    ).rejects.toThrow('close unavailable');
    expect(tx.salesHistoryImportJob.create).not.toHaveBeenCalled();
    expect(mockUnlink).toHaveBeenCalledWith(expect.any(String));
    expect(warn).toHaveBeenCalledWith(
      expect.stringContaining('admission failed'),
    );
  });

  it('logs cleanup failure without masking the database admission failure', async () => {
    const mockOpen = jest.mocked(open);
    const mockUnlink = jest.mocked(unlink);
    const close = jest.fn().mockResolvedValue(undefined);
    mockOpen.mockClear();
    mockUnlink.mockClear();
    mockOpen.mockImplementationOnce(async () => ({ close }) as any);
    mockUnlink.mockRejectedValueOnce(new Error('unlink unavailable'));
    const tx = {
      $executeRaw: jest.fn().mockResolvedValue(1),
      salesHistoryImportJob: {
        aggregate: jest.fn().mockResolvedValue({
          _sum: { expectedBytes: 0n },
        }),
        create: jest.fn().mockRejectedValue(new Error('database unavailable')),
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
      salesHistoryImportJob: {
        findUnique: jest.fn().mockResolvedValue(null),
      },
      $transaction: jest.fn(async (operation: (client: any) => unknown) =>
        operation(tx),
      ),
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);
    const error = jest.spyOn((service as any).logger, 'error');

    await expect(
      service.createUpload({ id: 'admin-1' }, 'history.csv', 3),
    ).rejects.toThrow('database unavailable');
    expect(error).toHaveBeenCalledWith(
      expect.stringContaining('admission cleanup failed'),
    );
  });

  it('persists a chunk across short writes before advancing the upload offset', async () => {
    const bytes = Buffer.from('hello');
    const job = {
      id: 'job-1',
      status: 'UPLOADING',
      requestedByUserId: 'admin-1',
      uploadedBytes: 0n,
      expectedBytes: 5n,
      artifactPath: 'C:/tmp/history.csv',
      version: null,
      stagedGrains: [],
    };
    const write = jest
      .fn()
      .mockResolvedValueOnce({ bytesWritten: 2 })
      .mockResolvedValueOnce({ bytesWritten: 1 })
      .mockResolvedValueOnce({ bytesWritten: 2 });
    const handle = {
      stat: jest.fn().mockResolvedValue({ size: 0 }),
      write,
      truncate: jest.fn().mockResolvedValue(undefined),
      close: jest.fn().mockResolvedValue(undefined),
    };
    const tx = {
      $executeRaw: jest.fn().mockResolvedValue(1),
      salesHistoryImportJob: {
        findUnique: jest
          .fn()
          .mockResolvedValueOnce(job)
          .mockResolvedValueOnce({ ...job, uploadedBytes: 5n }),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
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
      salesHistoryImportJob: { findUnique: jest.fn().mockResolvedValue(job) },
      $transaction: jest.fn(async (operation: (client: any) => unknown) =>
        operation(tx),
      ),
    };
    const mockOpen = jest.mocked(open);
    mockOpen.mockClear();
    mockOpen.mockImplementationOnce(async () => handle as any);
    const service = new SalesHistoryImportService(prisma as any, {} as any);

    await expect(
      service.appendUploadChunk({ id: 'admin-1' }, 'job-1', 0, {
        buffer: bytes,
      } as any),
    ).resolves.toMatchObject({ uploadedBytes: 5 });
    expect(write).toHaveBeenCalledTimes(3);
    expect(
      write.mock.calls.map(([buffer, sourceOffset, length, position]) => ({
        data: Buffer.from(buffer)
          .subarray(sourceOffset, sourceOffset + length)
          .toString(),
        sourceOffset,
        length,
        position,
      })),
    ).toEqual([
      { data: 'hello', sourceOffset: 0, length: 5, position: 0 },
      { data: 'llo', sourceOffset: 2, length: 3, position: 2 },
      { data: 'lo', sourceOffset: 3, length: 2, position: 3 },
    ]);
    expect(tx.salesHistoryImportJob.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({ data: { uploadedBytes: 5n } }),
    );
  });

  it('rejects a zero-progress write without advancing the upload record or scheduling work', async () => {
    const job = {
      id: 'job-1',
      status: 'UPLOADING',
      requestedByUserId: 'admin-1',
      uploadedBytes: 0n,
      expectedBytes: 3n,
      artifactPath: 'C:/tmp/history.csv',
      version: null,
      stagedGrains: [],
    };
    const handle = {
      stat: jest.fn().mockResolvedValue({ size: 0 }),
      write: jest.fn().mockResolvedValue({ bytesWritten: 0 }),
      truncate: jest.fn().mockResolvedValue(undefined),
      close: jest.fn().mockResolvedValue(undefined),
    };
    const tx = {
      $executeRaw: jest.fn().mockResolvedValue(1),
      salesHistoryImportJob: {
        findUnique: jest.fn().mockResolvedValue(job),
        updateMany: jest.fn(),
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
      salesHistoryImportJob: { findUnique: jest.fn().mockResolvedValue(job) },
      $transaction: jest.fn(async (operation: (client: any) => unknown) =>
        operation(tx),
      ),
    };
    const mockOpen = jest.mocked(open);
    mockOpen.mockClear();
    mockOpen.mockImplementationOnce(async () => handle as any);
    const service = new SalesHistoryImportService(prisma as any, {} as any);
    const schedulePump = jest.spyOn(service as any, 'schedulePump');

    await expect(
      service.appendUploadChunk({ id: 'admin-1' }, 'job-1', 0, {
        buffer: Buffer.from('abc'),
      } as any),
    ).rejects.toThrow();
    expect(tx.salesHistoryImportJob.updateMany).not.toHaveBeenCalled();
    expect(schedulePump).not.toHaveBeenCalled();
    expect(handle.truncate).toHaveBeenCalledWith(0);
    expect(handle.close).toHaveBeenCalledTimes(1);
  });

  it('does not make a short final chunk eligible for completion until every byte persists', async () => {
    const job = {
      id: 'job-1',
      status: 'UPLOADING',
      requestedByUserId: 'admin-1',
      uploadedBytes: 0n,
      expectedBytes: 5n,
      artifactPath: 'C:/tmp/history.csv',
      version: null,
      stagedGrains: [],
    };
    const handle = {
      stat: jest.fn().mockResolvedValue({ size: 0 }),
      write: jest
        .fn()
        .mockResolvedValueOnce({ bytesWritten: 4 })
        .mockResolvedValueOnce({ bytesWritten: 0 }),
      truncate: jest.fn().mockResolvedValue(undefined),
      close: jest.fn().mockResolvedValue(undefined),
    };
    const tx = {
      $executeRaw: jest.fn().mockResolvedValue(1),
      salesHistoryImportJob: {
        findUnique: jest.fn().mockResolvedValue(job),
        updateMany: jest.fn(),
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
      salesHistoryImportJob: { findUnique: jest.fn().mockResolvedValue(job) },
      $transaction: jest.fn(async (operation: (client: any) => unknown) =>
        operation(tx),
      ),
    };
    const mockOpen = jest.mocked(open);
    mockOpen.mockClear();
    mockOpen.mockImplementationOnce(async () => handle as any);
    const service = new SalesHistoryImportService(prisma as any, {} as any);

    await expect(
      service.appendUploadChunk({ id: 'admin-1' }, 'job-1', 0, {
        buffer: Buffer.from('final'),
      } as any),
    ).rejects.toThrow();
    expect(handle.write).toHaveBeenCalledTimes(2);
    expect(tx.salesHistoryImportJob.updateMany).not.toHaveBeenCalled();
  });

  it('accepts only a fully acknowledged chunk replay and rejects a partial overlap', async () => {
    const job = {
      id: 'job-1',
      status: 'UPLOADING',
      requestedByUserId: 'admin-1',
      uploadedBytes: 3n,
      expectedBytes: 8n,
      artifactPath: 'C:/tmp/history.csv',
      version: null,
      stagedGrains: [],
    };
    const tx = {
      $executeRaw: jest.fn().mockResolvedValue(1),
      salesHistoryImportJob: {
        findUnique: jest.fn().mockResolvedValue(job),
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
      salesHistoryImportJob: {
        findUnique: jest.fn().mockResolvedValue(job),
      },
      $transaction: jest.fn(async (operation: (client: any) => unknown) =>
        operation(tx),
      ),
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);
    const mockOpen = jest.mocked(open);
    mockOpen.mockClear();

    await expect(
      service.appendUploadChunk({ id: 'admin-1' }, 'job-1', 1, {
        buffer: Buffer.from('bc'),
      } as any),
    ).resolves.toMatchObject({ id: 'job-1', uploadedBytes: 3 });
    await expect(
      service.appendUploadChunk({ id: 'admin-1' }, 'job-1', 2, {
        buffer: Buffer.from('cd'),
      } as any),
    ).rejects.toThrow('Tiến trình tải lên đã thay đổi');
    expect(mockOpen).not.toHaveBeenCalled();
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
      $executeRaw: jest.fn().mockResolvedValue(0),
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

  it('uses normalized email as the stable historical identity before HRM or current showroom', () => {
    const service = new SalesHistoryImportService({} as any, {} as any);
    const row = {
      date: '2025-08-10',
      storeCode: 'CP01',
      orderCode: 'ORDER-1',
      salespersonEmail: ' Sale@PhongVu.vn ',
      salespersonCode: 'NV001',
      signedRevenue: 1000,
      quantities: {},
      errorCodes: [],
    };
    const emailWins = (service as any).resolveRowIdentity(row, {
      byEmail: new Map([['sale@phongvu.vn', 'user-1']]),
      byPersonnelCode: new Map([['NV001', 'user-2']]),
      userStoreCodes: new Map([
        ['user-1', new Set(['CP02'])],
        ['user-2', new Set(['CP01'])],
      ]),
    });
    expect(emailWins.userId).toBe('user-1');
    expect(emailWins.reasons).not.toContain('SALESPERSON_IDENTITY_MISMATCH');
    expect(emailWins.reasons).not.toContain('SALESPERSON_STORE_MISMATCH');

    const unknownHrmDoesNotOverrideEmail = (service as any).resolveRowIdentity(
      {
        ...row,
        salespersonEmail: 'sale@phongvu.vn',
        salespersonCode: 'OLD-001',
      },
      {
        byEmail: new Map([['sale@phongvu.vn', 'user-1']]),
        byPersonnelCode: new Map(),
        userStoreCodes: new Map([['user-1', new Set(['CP02'])]]),
      },
    );
    expect(unknownHrmDoesNotOverrideEmail.userId).toBe('user-1');
    expect(unknownHrmDoesNotOverrideEmail.reasons).not.toContain(
      'SALESPERSON_IDENTITY_MISMATCH',
    );

    const personnelFallback = (service as any).resolveRowIdentity(
      { ...row, salespersonEmail: 'departed@phongvu.vn' },
      {
        byEmail: new Map(),
        byPersonnelCode: new Map([['NV001', 'user-2']]),
        userStoreCodes: new Map([['user-2', new Set(['CP02'])]]),
      },
    );
    expect(personnelFallback.userId).toBe('user-2');
    expect(personnelFallback.reasons).not.toContain('UNKNOWN_SALESPERSON');
    expect(personnelFallback.reasons).not.toContain(
      'SALESPERSON_STORE_MISMATCH',
    );

    const ambiguousEmailFallsBackToPersonnel = (
      service as any
    ).resolveRowIdentity(
      { ...row, salespersonEmail: 'shared@phongvu.vn' },
      {
        byEmail: new Map([['shared@phongvu.vn', null]]),
        byPersonnelCode: new Map([['NV001', 'user-2']]),
        userStoreCodes: new Map(),
      },
    );
    expect(ambiguousEmailFallsBackToPersonnel.userId).toBe('user-2');
    expect(ambiguousEmailFallsBackToPersonnel.reasons).not.toContain(
      'AMBIGUOUS_SALESPERSON',
    );
  });

  it('normalizes current-user email and historical personnel indexes without loading current showroom assignments', async () => {
    const prisma = {
      store: {
        findMany: jest.fn().mockResolvedValue([{ storeId: ' cp01 ' }]),
      },
      user: {
        findMany: jest
          .fn()
          .mockResolvedValue([{ id: 'user-1', email: ' Sale@PhongVu.vn ' }]),
      },
      salesReport: {
        findMany: jest
          .fn()
          .mockResolvedValue([
            { createdByUserId: 'user-1', createdByPersonnelCode: ' nv001 ' },
          ]),
      },
      homeSummaryOrderFact: {
        findMany: jest.fn().mockResolvedValue([]),
      },
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);

    const index = await (service as any).loadIdentityIndex();

    expect(index.storeCodes).toEqual(new Set(['CP01']));
    expect(index.byEmail.get('sale@phongvu.vn')).toBe('user-1');
    expect(index.byPersonnelCode.get('NV001')).toBe('user-1');
    expect(prisma.user.findMany).toHaveBeenCalledWith({
      select: { id: true, email: true },
    });
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

describe('SalesHistoryImportService historical export staging SQL', () => {
  const sqlText = (statement: any) =>
    Array.isArray(statement?.strings)
      ? statement.strings.join('?')
      : String(statement?.sql ?? '');

  const quantities = (overrides: Record<string, number> = {}) => ({
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
    ...overrides,
  });

  const row = (overrides: Record<string, unknown> = {}) => ({
    rowNumber: 2,
    date: '2025-07-01',
    storeCode: 'CP01',
    orderCode: '25070134938050',
    salespersonEmail: 'sale@phongvu.vn',
    salespersonCode: 'NV001',
    signedRevenue: 1_000,
    quantities: quantities(),
    errorCodes: [],
    ...overrides,
  });

  const identities = {
    storeCodes: new Set(['CP01']),
    byEmail: new Map([['sale@phongvu.vn', 'user-1']]),
    byPersonnelCode: new Map([['NV001', 'user-1']]),
    userStoreCodes: new Map([['user-1', new Set(['CP01'])]]),
  };

  it('collapses canonical suffix lines in one chunk and accumulates components across chunk upserts', async () => {
    const tx = {
      $queryRaw: jest.fn().mockResolvedValue([{ id: 'job-1' }]),
      $executeRaw: jest.fn().mockResolvedValue(1),
    };
    const prisma = {
      $transaction: jest.fn(async (operation: (client: any) => unknown) =>
        operation(tx),
      ),
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);

    await (service as any).stageChunk(
      'job-1',
      7n,
      [
        row({
          signedRevenue: 100,
          quantities: quantities({ cpuQuantity: 2 }),
        }),
        row({
          rowNumber: 3,
          signedRevenue: 200,
          quantities: quantities({ mainboardQuantity: 3 }),
        }),
        row({
          rowNumber: 4,
          signedRevenue: 300,
          quantities: quantities({ memoryQuantity: 4 }),
        }),
      ],
      identities,
    );
    await (service as any).stageChunk(
      'job-1',
      7n,
      [
        row({
          rowNumber: 5,
          signedRevenue: 400,
          quantities: quantities({ storageQuantity: 5 }),
        }),
        row({
          rowNumber: 6,
          signedRevenue: 500,
          quantities: quantities({ caseQuantity: 6 }),
        }),
        row({
          rowNumber: 7,
          signedRevenue: 600,
          quantities: quantities({ psuQuantity: 7 }),
        }),
      ],
      identities,
    );

    const orderStatements = tx.$executeRaw.mock.calls
      .map(([statement]) => statement)
      .filter((statement) =>
        sqlText(statement).includes(
          'INSERT INTO "SalesHistoryImportOrderStage"',
        ),
      );
    expect(orderStatements).toHaveLength(2);
    expect(orderStatements[0].values).toEqual(
      expect.arrayContaining([600n, 2, 3, 4]),
    );
    expect(orderStatements[1].values).toEqual(
      expect.arrayContaining([1_500n, 5, 6, 7]),
    );
    for (const statement of orderStatements) {
      expect(sqlText(statement)).toContain(
        'ON CONFLICT ("jobId", "summaryDate", "storeCode", "userId", "orderHash")',
      );
      expect(sqlText(statement)).toContain(
        '"cpuQuantity" = "SalesHistoryImportOrderStage"."cpuQuantity" + EXCLUDED."cpuQuantity"',
      );
      expect(sqlText(statement)).toContain(
        '"psuQuantity" = "SalesHistoryImportOrderStage"."psuQuantity" + EXCLUDED."psuQuantity"',
      );
    }
    const orderHashes = orderStatements.map((statement) =>
      statement.values.find((value: unknown) =>
        /^[a-f0-9]{64}$/.test(String(value)),
      ),
    );
    expect(orderHashes[0]).toBeTruthy();
    expect(orderHashes[0]).toBe(orderHashes[1]);
  });

  it('keeps a canonical order in STORE when a later chunk resolves another valid user and marks personal coverage incomplete', async () => {
    const orderHash = createHash('sha256')
      .update('2025-07-01|CP01|25070134938050')
      .digest('hex');
    const tx = {
      $queryRaw: jest
        .fn()
        .mockResolvedValueOnce([{ id: 'job-1' }])
        .mockResolvedValueOnce([])
        .mockResolvedValueOnce([{ id: 'job-1' }])
        .mockResolvedValueOnce([
          {
            orderHash,
            userId: 'user-1',
            totalRevenue: 100n,
            ...quantities({ cpuQuantity: 1 }),
          },
        ]),
      $executeRaw: jest.fn().mockResolvedValue(1),
    };
    const prisma = {
      $transaction: jest.fn(async (operation: (client: any) => unknown) =>
        operation(tx),
      ),
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);
    const conflictingIdentities = {
      storeCodes: new Set(['CP01']),
      byEmail: new Map([
        ['sale@phongvu.vn', 'user-1'],
        ['sale-2@phongvu.vn', 'user-2'],
      ]),
      byPersonnelCode: new Map([
        ['NV001', 'user-1'],
        ['NV002', 'user-2'],
      ]),
      userStoreCodes: new Map([
        ['user-1', new Set(['CP01'])],
        ['user-2', new Set(['CP01'])],
      ]),
    };

    await (service as any).stageChunk(
      'job-1',
      7n,
      [row({ signedRevenue: 100, quantities: quantities({ cpuQuantity: 1 }) })],
      conflictingIdentities,
    );
    await (service as any).stageChunk(
      'job-1',
      7n,
      [
        row({
          rowNumber: 3,
          salespersonEmail: 'sale-2@phongvu.vn',
          salespersonCode: 'NV002',
          signedRevenue: 200,
          quantities: quantities({ mainboardQuantity: 1 }),
        }),
      ],
      conflictingIdentities,
    );

    const stagedSql = tx.$executeRaw.mock.calls
      .map(([statement]: [any]) => sqlText(statement))
      .join('\n');
    const stagedValues = tx.$executeRaw.mock.calls
      .flatMap(([statement]: [any]) => statement.values ?? [])
      .flat(Infinity);
    expect(stagedValues).not.toContain('DATE_SHOWROOM_ORDER_IDENTITY_CONFLICT');
    expect(stagedValues).toContain('PERSONAL_COVERAGE_INCOMPLETE');
    expect(stagedSql).toContain('SalesHistoryImportGrainStage');
    expect(stagedSql).toContain('SalesHistoryImportOrderStage');
  });

  it('keeps unresolved or ambiguous historical identity in STORE and marks personal coverage without quarantining the grain', async () => {
    const tx = {
      $queryRaw: jest.fn().mockResolvedValue([{ id: 'job-1' }]),
      $executeRaw: jest.fn().mockResolvedValue(1),
    };
    const prisma = {
      $transaction: jest.fn(async (operation: (client: any) => unknown) =>
        operation(tx),
      ),
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);

    await (service as any).stageChunk(
      'job-1',
      7n,
      [
        row({
          salespersonEmail: 'departed@phongvu.vn',
          salespersonCode: 'OLD-001',
        }),
        row({
          rowNumber: 3,
          orderCode: '25070134938051',
          salespersonEmail: 'ambiguous@phongvu.vn',
          salespersonCode: null,
        }),
      ],
      {
        storeCodes: new Set(['CP01']),
        byEmail: new Map([['ambiguous@phongvu.vn', null]]),
        byPersonnelCode: new Map(),
        userStoreCodes: new Map(),
      },
    );

    const grainStatement = tx.$executeRaw.mock.calls
      .map(([statement]) => statement)
      .find((statement) =>
        sqlText(statement).includes('SalesHistoryImportGrainStage'),
      );
    expect(grainStatement).toBeTruthy();
    expect(grainStatement.values).toEqual(
      expect.arrayContaining([
        2,
        0,
        expect.arrayContaining(['PERSONAL_COVERAGE_INCOMPLETE']),
      ]),
    );
    expect(
      tx.$executeRaw.mock.calls
        .map(([statement]) => sqlText(statement))
        .join('\n'),
    ).toContain('SalesHistoryImportOrderStage');
  });

  it('quarantines within- and cross-chunk numeric overflows before a corrupt grain can activate', async () => {
    const orderHash = createHash('sha256')
      .update('2025-07-01|CP01|25070134938050')
      .digest('hex');
    const tx = {
      $queryRaw: jest
        .fn()
        .mockResolvedValueOnce([{ id: 'job-1' }])
        .mockResolvedValueOnce([])
        .mockResolvedValueOnce([{ id: 'job-1' }])
        .mockResolvedValueOnce([
          {
            orderHash,
            userId: 'user-1',
            totalRevenue: BigInt(Number.MAX_SAFE_INTEGER),
            ...quantities({ laptopQuantity: 2_147_483_647 }),
          },
        ]),
      $executeRaw: jest.fn().mockResolvedValue(1),
    };
    const prisma = {
      $transaction: jest.fn(async (operation: (client: any) => unknown) =>
        operation(tx),
      ),
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);

    await (service as any).stageChunk(
      'job-1',
      7n,
      [
        row({
          signedRevenue: Number.MAX_SAFE_INTEGER,
          quantities: quantities({ laptopQuantity: 2_147_483_647 }),
        }),
        row({
          rowNumber: 3,
          signedRevenue: 1,
          quantities: quantities({ laptopQuantity: 1 }),
        }),
      ],
      identities,
    );
    await (service as any).stageChunk(
      'job-1',
      7n,
      [
        row({
          rowNumber: 4,
          signedRevenue: 1,
          quantities: quantities({ laptopQuantity: 1 }),
        }),
      ],
      identities,
    );

    const stagedSql = tx.$executeRaw.mock.calls
      .map(([statement]: [any]) => sqlText(statement))
      .join('\n');
    const stagedValues = tx.$executeRaw.mock.calls
      .flatMap(([statement]: [any]) => statement.values ?? [])
      .flat(Infinity);
    expect(stagedValues).toContain('DATE_SHOWROOM_NUMERIC_OVERFLOW');
    expect(stagedSql).toContain('invalidRows');
  });

  it('quarantines a derived assembled-PC total above PostgreSQL integer range', async () => {
    const tx = {
      $queryRaw: jest.fn().mockResolvedValue([{ id: 'job-1' }]),
      $executeRaw: jest.fn().mockResolvedValue(1),
    };
    const prisma = {
      $transaction: jest.fn(async (operation: (client: any) => unknown) =>
        operation(tx),
      ),
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);

    await (service as any).stageChunk(
      'job-1',
      7n,
      [
        row({
          signedRevenue: 1_000,
          quantities: quantities({
            assembledPcQuantity: 2_147_483_647,
            cpuQuantity: 1,
            mainboardQuantity: 1,
            memoryQuantity: 1,
            storageQuantity: 1,
            caseQuantity: 1,
            psuQuantity: 1,
          }),
        }),
      ],
      identities,
    );

    expect(tx.$executeRaw).toHaveBeenCalledTimes(1);
    const grainStatement = tx.$executeRaw.mock.calls[0][0];
    expect(sqlText(grainStatement)).toContain(
      'INSERT INTO "SalesHistoryImportGrainStage"',
    );
    expect(grainStatement.values).toEqual(
      expect.arrayContaining([1, ['DATE_SHOWROOM_NUMERIC_OVERFLOW']]),
    );
  });

  it('quarantines an unmatched taxonomy grain while keeping the invalid row out of order stage', async () => {
    const tx = {
      $queryRaw: jest.fn().mockResolvedValue([{ id: 'job-1' }]),
      $executeRaw: jest.fn().mockResolvedValue(1),
    };
    const prisma = {
      $transaction: jest.fn(async (operation: (client: any) => unknown) =>
        operation(tx),
      ),
    };
    const service = new SalesHistoryImportService(prisma as any, {} as any);

    await (service as any).stageChunk(
      'job-1',
      7n,
      [row({ errorCodes: ['INVALID_CATEGORY'] })],
      identities,
    );

    expect(tx.$executeRaw).toHaveBeenCalledTimes(1);
    const grainStatement = tx.$executeRaw.mock.calls[0][0];
    expect(sqlText(grainStatement)).toContain(
      'INSERT INTO "SalesHistoryImportGrainStage"',
    );
    expect(grainStatement.values).toEqual(
      expect.arrayContaining([1, ['INVALID_CATEGORY']]),
    );
  });

  it('finalizes assembled PC as direct quantity plus the non-negative six-component minimum per order', async () => {
    const summaryDate = new Date('2025-07-01T00:00:00.000Z');
    const tx = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'admin-1',
          role: 'SUPER_ADMIN',
          store: null,
          organizationAssignments: [],
        }),
      },
      salesHistoryImportGrainStage: {
        findMany: jest.fn().mockResolvedValue([
          {
            summaryDate,
            storeCode: 'CP01',
            rowCount: 6,
            invalidRows: 0,
            reasonCodes: [],
          },
        ]),
        deleteMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      salesHistoryImportOrderStage: {
        deleteMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      salesHistoryImportJob: {
        findUnique: jest.fn().mockResolvedValue({
          requestedByUserId: 'admin-1',
        }),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      salesHistoryVersion: {
        create: jest.fn().mockResolvedValue({ id: 'version-1' }),
      },
      salesHistoryCoverage: {
        createMany: jest.fn().mockResolvedValue({ count: 1 }),
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
      (service as any).finalizeVersion(
        { id: 'admin-1' },
        'job-1',
        'source-hash',
      ),
    ).resolves.toMatchObject({ versionId: 'version-1', cleanGrains: 1 });

    const statements = tx.$executeRaw.mock.calls.map(([statement]) => ({
      sql: sqlText(statement).replace(/\s+/g, ' '),
      statement,
    }));
    expect(statements[0].sql).toContain('WITH overflow_grains AS');
    expect(statements[0].sql).toContain('DATE_SHOWROOM_NUMERIC_OVERFLOW');
    const aggregateSql = statements.find(({ sql }) =>
      sql.includes('INSERT INTO "SalesHistoryAggregate"'),
    )!.sql;
    expect(aggregateSql).toContain(
      'GREATEST(stage."assembledPcQuantity", 0)::bigint + GREATEST( LEAST( stage."cpuQuantity", stage."mainboardQuantity", stage."memoryQuantity", stage."storageQuantity", stage."caseQuantity", stage."psuQuantity" ), 0 )::bigint',
    );
    expect(aggregateSql).toContain(
      'SUM(item."finalAssembledPcQuantity")::integer',
    );
    expect(aggregateSql).toContain('WHERE item."userId" <>');
    expect(
      statements.find(({ sql }) =>
        sql.includes('INSERT INTO "SalesHistoryAggregate"'),
      )!.statement.values,
    ).toContain('');
  });
});
