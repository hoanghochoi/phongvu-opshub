import { BidvH2hProjectionWorker } from './bidv-h2h-projection.worker';

describe('BidvH2hProjectionWorker', () => {
  const originalEnv = {
    environment: process.env.BIDV_H2H_ENVIRONMENT,
    publicBaseUrl: process.env.BIDV_H2H_PUBLIC_BASE_URL,
    ingest: process.env.BIDV_H2H_INGEST_ENABLED,
    projection: process.env.BIDV_H2H_PROJECTION_ENABLED,
    kek: process.env.BIDV_H2H_KEK_BASE64,
  };

  beforeEach(() => {
    process.env.BIDV_H2H_ENVIRONMENT = 'local';
    process.env.BIDV_H2H_PUBLIC_BASE_URL = 'http://localhost:3000';
    process.env.BIDV_H2H_INGEST_ENABLED = 'true';
    process.env.BIDV_H2H_PROJECTION_ENABLED = 'true';
    process.env.BIDV_H2H_KEK_BASE64 = Buffer.alloc(32, 9).toString('base64');
  });

  afterAll(() => {
    restore('BIDV_H2H_ENVIRONMENT', originalEnv.environment);
    restore('BIDV_H2H_PUBLIC_BASE_URL', originalEnv.publicBaseUrl);
    restore('BIDV_H2H_INGEST_ENABLED', originalEnv.ingest);
    restore('BIDV_H2H_PROJECTION_ENABLED', originalEnv.projection);
    restore('BIDV_H2H_KEK_BASE64', originalEnv.kek);
  });

  it('allows a crashed processing lease to be reclaimed', async () => {
    const queryRaw = jest.fn().mockResolvedValue([]);
    const worker = new BidvH2hProjectionWorker(
      {
        bankConnectionControl: {
          findUnique: jest.fn().mockResolvedValue({ projectionEnabled: true }),
        },
        $queryRaw: queryRaw,
      } as any,
      {} as any,
      policy() as any,
    );

    await worker.tick();

    const sql = (queryRaw.mock.calls[0][0] as TemplateStringsArray).join('?');
    expect(sql).toContain('"projectionStatus" = \'PROCESSING\'');
    expect(sql).toContain('"projectionLeaseExpiresAt" < NOW()');
  });

  it.each([
    ['D', 'VND', '1000', 'not_credit'],
    ['C', 'USD', '1000', 'not_vnd'],
    ['C', 'VND', '1000.5', 'amount_not_supported'],
  ])(
    'skips non-eligible direction/currency/amount %#',
    async (direction, currency, exactAmount, reason) => {
      const worker = new BidvH2hProjectionWorker(
        { store: { findMany: jest.fn() } } as any,
        {} as any,
        policy() as any,
      );

      await expect(
        (worker as any).eligibility({
          conflictStatus: 'NONE',
          direction,
          currency,
          exactAmount,
        }),
      ).resolves.toEqual({ eligible: false, reason });
    },
  );

  it('projects only when showroom resolution is unique', async () => {
    const worker = new BidvH2hProjectionWorker(
      {
        store: {
          findMany: jest
            .fn()
            .mockResolvedValue([{ storeId: 'CP01' }, { storeId: 'CP02' }]),
        },
      } as any,
      {} as any,
      policy() as any,
    );

    await expect(
      (worker as any).eligibility({
        conflictStatus: 'NONE',
        direction: 'C',
        currency: 'VND',
        exactAmount: '1000',
        showroomCodeHint: 'CP01',
      }),
    ).resolves.toEqual({ eligible: true, storeCode: 'CP01', amount: 1000 });
  });

  it('does not infer showroom from account or virtual-account hashes', async () => {
    const worker = new BidvH2hProjectionWorker(
      {
        store: {
          findMany: jest.fn().mockResolvedValue([{ storeId: 'CP01' }]),
        },
      } as any,
      {} as any,
      policy() as any,
    );

    await expect(
      (worker as any).eligibility({
        conflictStatus: 'NONE',
        direction: 'C',
        currency: 'VND',
        exactAmount: '1000',
        showroomCodeHint: null,
        accountNoHash: 'matching-account-hash',
        virtualAccountHash: 'matching-account-hash',
      }),
    ).resolves.toEqual({ eligible: false, reason: 'showroom_not_unique' });
  });

  it('rechecks conflict state under the shared identity lock before projection', async () => {
    const executeRaw = jest.fn().mockResolvedValue(1);
    const mapUpsert = jest.fn();
    const updateMany = jest.fn().mockResolvedValue({ count: 1 });
    const transaction = {
      id: 'bank-transaction-1',
      identityHash: 'identity-hash',
      payloadHash: 'payload-hash',
      projectionClaimToken: 'claim-1',
      projectionAttempts: 1,
    };
    const prisma = {
      bankConnectionControl: {
        findUnique: jest.fn().mockResolvedValue({ operatingMode: 'LIVE' }),
      },
      $transaction: jest.fn(async (callback: (tx: any) => unknown) =>
        callback({
          $executeRaw: executeRaw,
          bankTransaction: {
            findUnique: jest.fn().mockResolvedValue({
              ...transaction,
              conflictStatus: 'CONFLICT',
            }),
          },
          mapVietinTransaction: { upsert: mapUpsert },
        }),
      ),
      bankTransaction: { updateMany },
    };
    const notify = jest.fn();
    const worker = new BidvH2hProjectionWorker(
      prisma as any,
      { createForTransaction: notify } as any,
      policy(true) as any,
    );

    await (worker as any).process(transaction);

    expect(executeRaw).toHaveBeenCalledTimes(2);
    expect(mapUpsert).not.toHaveBeenCalled();
    expect(notify).not.toHaveBeenCalled();
    expect(updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          projectionStatus: 'CONFLICT',
          projectionReason: 'identity_conflict',
        }),
      }),
    );
  });
});

function policy(lock = false) {
  return {
    evaluate: jest.fn().mockResolvedValue({ effectiveMode: 'LIVE' }),
    assertLive: jest.fn().mockResolvedValue({ effectiveMode: 'LIVE' }),
    lock: jest.fn((tx: any) =>
      lock ? tx.$executeRaw(['control-lock'] as any) : undefined,
    ),
  };
}

function restore(key: string, value: string | undefined) {
  if (value === undefined) delete process.env[key];
  else process.env[key] = value;
}
