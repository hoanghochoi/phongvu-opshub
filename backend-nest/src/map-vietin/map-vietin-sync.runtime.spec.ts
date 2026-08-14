import { MapVietinSyncCoordinator } from './map-vietin-sync.runtime';

describe('MapVietinSyncCoordinator', () => {
  let coordinator: MapVietinSyncCoordinator;
  let syncConfiguredStores: jest.Mock;
  let syncEfastTransactions: jest.Mock;
  let resetProviderBackoff: jest.Mock;
  let clearFingerprintCache: jest.Mock;
  let setTimeoutSpy: jest.SpyInstance;
  let logger: {
    debug: jest.Mock;
    log: jest.Mock;
    warn: jest.Mock;
  };

  beforeEach(() => {
    jest.useFakeTimers();
    setTimeoutSpy = jest.spyOn(global, 'setTimeout');
    syncConfiguredStores = jest.fn().mockResolvedValue(undefined);
    syncEfastTransactions = jest.fn().mockResolvedValue(undefined);
    resetProviderBackoff = jest.fn();
    clearFingerprintCache = jest.fn();
    logger = {
      debug: jest.fn(),
      log: jest.fn(),
      warn: jest.fn(),
    };
    coordinator = new MapVietinSyncCoordinator();
    coordinator.configure({
      logger,
      isMapHistorySyncDisabled: () => false,
      isEfastSyncEnabled: () => false,
      mapProviderBackoffUntil: () => 0,
      globalSyncMaxPages: () => 2,
      readPositiveInt: (name, fallback) => {
        const value = Number(process.env[name]);
        return Number.isSafeInteger(value) && value > 0 ? value : fallback;
      },
      resetProviderBackoff,
      clearFingerprintCache,
      safeError: (error) => String(error),
      syncConfiguredStores,
      syncEfastTransactions,
    });
  });

  afterEach(() => {
    coordinator.onModuleDestroy();
    setTimeoutSpy.mockRestore();
    jest.useRealTimers();
  });

  it('preserves MAP and eFAST window cadence calculations', () => {
    jest.spyOn(Math, 'random').mockReturnValue(0);

    expect(
      coordinator.nextMapHistorySyncDelayMs(
        new Date('2026-05-21T00:00:00.000Z'),
      ),
    ).toBe(1000);
    expect(
      coordinator.nextMapHistorySyncDelayMs(
        new Date('2026-05-21T15:01:00.000Z'),
      ),
    ).toBe(30 * 60 * 1000);
    expect(
      coordinator.nextEfastSyncDelayMs(new Date('2026-05-21T01:00:00.000Z')),
    ).toBe(50 * 1000);
    expect(
      coordinator.nextEfastSyncDelayMs(new Date('2026-05-21T15:01:00.000Z')),
    ).toBe(30 * 60 * 1000);
  });

  it('keeps the MAP scheduler behind provider backoff', () => {
    const retryAt = Date.now() + 30_000;
    coordinator.configure({
      logger,
      isMapHistorySyncDisabled: () => false,
      isEfastSyncEnabled: () => false,
      mapProviderBackoffUntil: () => retryAt,
      globalSyncMaxPages: () => 2,
      readPositiveInt: () => 1000,
      resetProviderBackoff,
      clearFingerprintCache,
      safeError: (error) => String(error),
      syncConfiguredStores,
      syncEfastTransactions,
    });

    coordinator.scheduleNextMapHistorySync(0);

    expect(setTimeoutSpy).toHaveBeenCalledWith(expect.any(Function), 30_000);
  });

  it('enforces a single-flight lease for configured-store sync', async () => {
    let resolveFirst!: () => void;
    const execute = jest.fn(
      () =>
        new Promise<void>((resolve) => {
          resolveFirst = resolve;
        }),
    );

    const first = coordinator.runConfiguredStores({}, execute);
    await Promise.resolve();
    await expect(
      coordinator.runConfiguredStores({}, execute),
    ).resolves.toBeUndefined();
    expect(execute).toHaveBeenCalledTimes(1);

    resolveFirst();
    await first;
  });

  it('enforces a single-flight lease for eFAST sync', async () => {
    let resolveFirst!: () => void;
    const execute = jest.fn(
      () =>
        new Promise<void>((resolve) => {
          resolveFirst = resolve;
        }),
    );

    const first = coordinator.runEfastTransactions(execute);
    await Promise.resolve();
    await expect(
      coordinator.runEfastTransactions(execute),
    ).resolves.toBeUndefined();
    expect(execute).toHaveBeenCalledTimes(1);

    resolveFirst();
    await first;
  });

  it('calls the public sync callback and reschedules after a MAP run', async () => {
    coordinator.mapHistoryDeepSweepDueAt = 0;

    await coordinator.runScheduledMapHistorySync();

    expect(syncConfiguredStores).toHaveBeenCalledWith({
      mode: 'deep_sweep',
      maxPages: 2,
    });
    expect(setTimeoutSpy).toHaveBeenCalled();
  });

  it('clears timers, stops callbacks and clears fingerprint state on destroy', async () => {
    coordinator.scheduleNextMapHistorySync(1000);
    coordinator.onModuleDestroy();

    jest.advanceTimersByTime(1000);
    expect(syncConfiguredStores).not.toHaveBeenCalled();
    expect(clearFingerprintCache).toHaveBeenCalledTimes(1);
    await expect(
      coordinator.runConfiguredStores({}, syncConfiguredStores),
    ).resolves.toBeUndefined();
  });
});
