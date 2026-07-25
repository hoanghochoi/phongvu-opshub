import {
  findPostgresSqlState,
  isPostgresDeadlock,
  withPostgresDeadlockRetry,
} from './postgres-deadlock-retry';

describe('postgres deadlock retry', () => {
  const logger = {
    log: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
  };

  beforeEach(() => jest.clearAllMocks());

  it('finds 40P01 through Prisma driver-adapter causes', () => {
    const error = {
      code: 'P2010',
      meta: {
        driverAdapterError: {
          name: 'DriverAdapterError',
          cause: {
            kind: 'postgres',
            code: '40P01',
            originalCode: '40P01',
          },
        },
      },
    };

    expect(findPostgresSqlState(error)).toBe('40P01');
    expect(isPostgresDeadlock(error)).toBe(true);
  });

  it('does not infer SQLSTATE from an error message', () => {
    expect(isPostgresDeadlock(new Error('40P01: deadlock detected'))).toBe(
      false,
    );
  });

  it('retries a deadlock at most three total attempts with deterministic jitter', async () => {
    const execute = jest
      .fn<Promise<string>, []>()
      .mockRejectedValueOnce({ cause: { originalCode: '40P01' } })
      .mockRejectedValueOnce({ code: '40P01' })
      .mockResolvedValue('ok');
    const delays: number[] = [];

    await expect(
      withPostgresDeadlockRetry(execute, {
        operation: 'test_operation',
        logger,
        baseDelayMs: 20,
        maxDelayMs: 100,
        random: () => 0.5,
        sleep: async (delayMs) => {
          delays.push(delayMs);
        },
      }),
    ).resolves.toBe('ok');

    expect(execute).toHaveBeenCalledTimes(3);
    expect(delays).toEqual([30, 50]);
    expect(logger.warn).toHaveBeenCalledTimes(2);
    expect(logger.log).toHaveBeenCalledWith(
      expect.stringContaining(
        'operation=test_operation attempt=3 maxAttempts=3 sqlState=40P01',
      ),
    );
  });

  it('rethrows the final deadlock after the third total attempt', async () => {
    const error = { originalCode: '40P01' };
    const execute = jest.fn().mockRejectedValue(error);

    await expect(
      withPostgresDeadlockRetry(execute, {
        operation: 'exhausted_operation',
        logger,
        random: () => 0,
        sleep: async () => undefined,
      }),
    ).rejects.toBe(error);

    expect(execute).toHaveBeenCalledTimes(3);
    expect(logger.warn).toHaveBeenCalledTimes(2);
    expect(logger.error).toHaveBeenCalledWith(
      expect.stringContaining(
        'operation=exhausted_operation attempt=3 maxAttempts=3 sqlState=40P01',
      ),
    );
  });

  it('never allows configuration to exceed three attempts', async () => {
    const execute = jest.fn().mockRejectedValue({ code: '40P01' });

    await expect(
      withPostgresDeadlockRetry(execute, {
        operation: 'bounded_operation',
        logger,
        maxAttempts: 20,
        sleep: async () => undefined,
      }),
    ).rejects.toEqual({ code: '40P01' });

    expect(execute).toHaveBeenCalledTimes(3);
  });

  it.each([
    { code: '23505' },
    { code: 'P2002', meta: { target: ['transactionKey'] } },
    { cause: { originalCode: '40001' } },
  ])('does not retry non-deadlock errors: %p', async (error) => {
    const execute = jest.fn().mockRejectedValue(error);

    await expect(
      withPostgresDeadlockRetry(execute, {
        operation: 'non_deadlock_operation',
        logger,
        sleep: async () => undefined,
      }),
    ).rejects.toBe(error);

    expect(execute).toHaveBeenCalledTimes(1);
    expect(logger.warn).not.toHaveBeenCalled();
    expect(logger.error).not.toHaveBeenCalled();
  });
});
