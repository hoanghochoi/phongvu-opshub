import { Injectable, Logger, LoggerService } from '@nestjs/common';

const EFAST_SYNC_START_HOUR_VN = 8;
const EFAST_SYNC_END_HOUR_VN = 22;
const EFAST_FAST_SYNC_DELAY_MIN_MS = 50 * 1000;
const EFAST_FAST_SYNC_DELAY_MAX_MS = 60 * 1000;
const EFAST_NIGHT_SYNC_DELAY_MS = 30 * 60 * 1000;
const MAP_SYNC_START_HOUR_VN = 7;
const MAP_SYNC_END_HOUR_VN = 22;
const DEFAULT_MAP_HISTORY_SYNC_DELAY_MIN_MS = 1000;
const DEFAULT_MAP_HISTORY_SYNC_DELAY_MAX_MS = 2000;
const MIN_MAP_HISTORY_SYNC_DELAY_MS = 500;
const DEFAULT_MAP_DEEP_SWEEP_DELAY_MIN_MS = 30 * 1000;
const DEFAULT_MAP_DEEP_SWEEP_DELAY_MAX_MS = 60 * 1000;
const MIN_MAP_DEEP_SWEEP_DELAY_MS = 30 * 1000;
const MAP_HISTORY_SYNC_NIGHT_DELAY_MS = 30 * 60 * 1000;
const ONE_DAY_MS = 24 * 60 * 60 * 1000;
const VIETNAM_UTC_OFFSET_HOURS = 7;

export type MapVietinSyncMode =
  | 'fast_page'
  | 'deep_sweep'
  | 'session_recovery'
  | 'manual';

export type MapVietinSyncOptions = {
  mode?: MapVietinSyncMode;
  maxPages?: number;
};

type SyncLogger = {
  debug: LoggerService['debug'] extends (...args: infer Args) => infer Result
    ? (...args: Args) => Result
    : (message: unknown, ...optionalParams: unknown[]) => unknown;
  log: LoggerService['log'] extends (...args: infer Args) => infer Result
    ? (...args: Args) => Result
    : (message: unknown, ...optionalParams: unknown[]) => unknown;
  warn: LoggerService['warn'] extends (...args: infer Args) => infer Result
    ? (...args: Args) => Result
    : (message: unknown, ...optionalParams: unknown[]) => unknown;
};

export type MapVietinSyncCoordinatorConfig = {
  logger?: SyncLogger;
  isMapHistorySyncDisabled: () => boolean;
  isEfastSyncEnabled: () => boolean;
  mapProviderBackoffUntil: () => number;
  globalSyncMaxPages: () => number;
  readPositiveInt: (name: string, fallback: number) => number;
  resetProviderBackoff: () => void;
  clearFingerprintCache?: () => void;
  safeError: (error: unknown) => string;
  syncConfiguredStores: (options: MapVietinSyncOptions) => Promise<unknown>;
  syncEfastTransactions: () => Promise<unknown>;
};

/**
 * Owns MAP/eFAST scheduling and single-flight leases while the service keeps
 * the stable product facade and the actual sync execution logic.
 */
@Injectable()
export class MapVietinSyncCoordinator {
  private readonly defaultLogger = new Logger(MapVietinSyncCoordinator.name);
  private config?: MapVietinSyncCoordinatorConfig;
  private mapHistorySyncTimer?: NodeJS.Timeout;
  private efastSyncTimer?: NodeJS.Timeout;
  private mapHistorySyncStopped = false;
  private efastSyncStopped = false;
  private mapSyncInProgress = false;
  private efastSyncInProgress = false;
  private lastSyncWindowOpenValue?: boolean;
  private lastEfastSyncWindowOpen?: boolean;
  private mapHistoryDeepSweepDueAtValue = 0;

  configure(config: MapVietinSyncCoordinatorConfig) {
    this.config = config;
  }

  get mapHistoryDeepSweepDueAt() {
    return this.mapHistoryDeepSweepDueAtValue;
  }

  set mapHistoryDeepSweepDueAt(value: number) {
    this.mapHistoryDeepSweepDueAtValue = value;
  }

  get lastSyncWindowOpen() {
    return this.lastSyncWindowOpenValue;
  }

  set lastSyncWindowOpen(value: boolean | undefined) {
    this.lastSyncWindowOpenValue = value;
  }

  onModuleInit() {
    const config = this.requireConfig();
    this.mapHistorySyncStopped = false;
    this.efastSyncStopped = false;
    this.mapSyncInProgress = false;
    this.efastSyncInProgress = false;
    this.lastSyncWindowOpenValue = undefined;
    this.lastEfastSyncWindowOpen = undefined;
    this.mapHistoryDeepSweepDueAtValue = 0;
    config.resetProviderBackoff();

    if (config.isMapHistorySyncDisabled()) {
      this.logger().log(
        'MAP history sync scheduler disabled by MAP_VIETIN_SYNC_ENABLED=false',
      );
    } else {
      this.scheduleNextMapHistorySync(0);
    }
    this.scheduleNextEfastSync();
  }

  onModuleDestroy() {
    this.mapHistorySyncStopped = true;
    this.efastSyncStopped = true;
    this.clearMapTimer();
    this.clearEfastTimer();
    this.config?.clearFingerprintCache?.();
  }

  async runConfiguredStores(
    options: MapVietinSyncOptions,
    execute: (options: MapVietinSyncOptions) => Promise<unknown>,
  ) {
    const config = this.requireConfig();
    if (
      this.mapHistorySyncStopped ||
      config.isMapHistorySyncDisabled() ||
      this.mapSyncInProgress
    ) {
      return undefined;
    }
    this.mapSyncInProgress = true;
    try {
      return await execute(options);
    } finally {
      this.mapSyncInProgress = false;
    }
  }

  async runEfastTransactions(execute: () => Promise<unknown>) {
    if (this.efastSyncStopped || this.efastSyncInProgress) {
      return undefined;
    }
    this.efastSyncInProgress = true;
    try {
      return await execute();
    } finally {
      this.efastSyncInProgress = false;
    }
  }

  scheduleNextMapHistorySync(delayOverrideMs?: number) {
    const config = this.requireConfig();
    if (this.mapHistorySyncStopped || config.isMapHistorySyncDisabled()) {
      return;
    }
    const now = Date.now();
    const normalDelayMs =
      delayOverrideMs ?? this.nextMapHistorySyncDelayMs(new Date(now));
    const backoffDelayMs = Math.max(0, config.mapProviderBackoffUntil() - now);
    const delayMs = Math.max(normalDelayMs, backoffDelayMs);
    this.clearMapTimer();
    this.mapHistorySyncTimer = setTimeout(() => {
      void this.runScheduledMapHistorySync();
    }, delayMs);
    this.mapHistorySyncTimer.unref?.();
    this.logger().debug(
      `Next MAP history sync scheduled in ${delayMs}ms mode=${this.mapHistoryDeepSweepDueAtValue <= now ? 'deep_sweep' : 'fast_page'} backoffMs=${backoffDelayMs}`,
    );
  }

  async runScheduledMapHistorySync() {
    const config = this.requireConfig();
    try {
      const deepSweep = this.mapHistoryDeepSweepDueAtValue <= Date.now();
      await config.syncConfiguredStores({
        mode: deepSweep ? 'deep_sweep' : 'fast_page',
        maxPages: deepSweep ? config.globalSyncMaxPages() : 1,
      });
    } catch (error) {
      this.logger().warn(
        `Scheduled MAP history sync failed: ${config.safeError(error).slice(0, 500)}`,
      );
    } finally {
      this.scheduleNextMapHistorySync();
    }
  }

  scheduleNextEfastSync() {
    const config = this.requireConfig();
    if (this.efastSyncStopped || !config.isEfastSyncEnabled()) return;
    const delayMs = this.nextEfastSyncDelayMs();
    this.clearEfastTimer();
    this.efastSyncTimer = setTimeout(() => {
      void this.runScheduledEfastSync();
    }, delayMs);
    this.efastSyncTimer.unref?.();
    this.logger().debug(`Next VietinBank eFAST sync scheduled in ${delayMs}ms`);
  }

  async runScheduledEfastSync() {
    const config = this.requireConfig();
    try {
      const inFastWindow = this.isWithinEfastFastSyncWindow();
      if (this.lastEfastSyncWindowOpen !== inFastWindow) {
        this.logger().log(
          inFastWindow
            ? 'VietinBank eFAST sync fast cadence active'
            : 'VietinBank eFAST sync night cadence active',
        );
      }
      this.lastEfastSyncWindowOpen = inFastWindow;
      await config.syncEfastTransactions();
    } catch (error) {
      this.logger().warn(
        `Scheduled VietinBank eFAST sync failed: ${config.safeError(error).slice(0, 500)}`,
      );
    } finally {
      this.scheduleNextEfastSync();
    }
  }

  randomMapHistorySyncDelayMs() {
    const config = this.requireConfig();
    const configuredMin = config.readPositiveInt(
      'MAP_VIETIN_SYNC_DELAY_MIN_MS',
      DEFAULT_MAP_HISTORY_SYNC_DELAY_MIN_MS,
    );
    const configuredMax = config.readPositiveInt(
      'MAP_VIETIN_SYNC_DELAY_MAX_MS',
      DEFAULT_MAP_HISTORY_SYNC_DELAY_MAX_MS,
    );
    const min = Math.max(MIN_MAP_HISTORY_SYNC_DELAY_MS, configuredMin);
    const max = Math.max(min, configuredMax);
    const span = max - min;
    return min + Math.floor(Math.random() * (span + 1));
  }

  randomMapDeepSweepDelayMs() {
    const config = this.requireConfig();
    const configuredMin = config.readPositiveInt(
      'MAP_VIETIN_DEEP_SWEEP_DELAY_MIN_MS',
      DEFAULT_MAP_DEEP_SWEEP_DELAY_MIN_MS,
    );
    const configuredMax = config.readPositiveInt(
      'MAP_VIETIN_DEEP_SWEEP_DELAY_MAX_MS',
      DEFAULT_MAP_DEEP_SWEEP_DELAY_MAX_MS,
    );
    const min = Math.max(MIN_MAP_DEEP_SWEEP_DELAY_MS, configuredMin);
    const max = Math.max(min, configuredMax);
    return min + Math.floor(Math.random() * (max - min + 1));
  }

  randomEfastFastSyncDelayMs() {
    const span = EFAST_FAST_SYNC_DELAY_MAX_MS - EFAST_FAST_SYNC_DELAY_MIN_MS;
    return (
      EFAST_FAST_SYNC_DELAY_MIN_MS + Math.floor(Math.random() * (span + 1))
    );
  }

  nextMapHistorySyncDelayMs(value = new Date(Date.now())) {
    if (this.isWithinMapSyncWindow(value)) {
      return this.randomMapHistorySyncDelayMs();
    }
    return Math.min(
      MAP_HISTORY_SYNC_NIGHT_DELAY_MS,
      this.msUntilNextMapFastWindowStart(value),
    );
  }

  nextEfastSyncDelayMs(value = new Date(Date.now())) {
    if (this.isWithinEfastFastSyncWindow(value)) {
      const fastDelay = this.randomEfastFastSyncDelayMs();
      const msUntilNight = this.msUntilEfastNightWindowStart(value);
      return msUntilNight <= fastDelay
        ? msUntilNight + EFAST_NIGHT_SYNC_DELAY_MS
        : fastDelay;
    }
    return Math.min(
      EFAST_NIGHT_SYNC_DELAY_MS,
      this.msUntilNextEfastFastWindowStart(value),
    );
  }

  isWithinMapSyncWindow(value = new Date(Date.now())) {
    const vietnamHour = (value.getUTCHours() + VIETNAM_UTC_OFFSET_HOURS) % 24;
    return (
      vietnamHour >= MAP_SYNC_START_HOUR_VN &&
      vietnamHour < MAP_SYNC_END_HOUR_VN
    );
  }

  isWithinEfastFastSyncWindow(value = new Date(Date.now())) {
    const vietnamDate = new Date(this.vietnamTimeMs(value));
    const minutes =
      vietnamDate.getUTCHours() * 60 + vietnamDate.getUTCMinutes();
    return (
      minutes >= EFAST_SYNC_START_HOUR_VN * 60 &&
      minutes <= EFAST_SYNC_END_HOUR_VN * 60
    );
  }

  private msUntilNextMapFastWindowStart(value: Date) {
    const vietnamTimeMs = this.vietnamTimeMs(value);
    const vietnamDate = new Date(vietnamTimeMs);
    const startTodayVietnamMs = Date.UTC(
      vietnamDate.getUTCFullYear(),
      vietnamDate.getUTCMonth(),
      vietnamDate.getUTCDate(),
      MAP_SYNC_START_HOUR_VN,
      0,
      0,
      0,
    );
    const nextStartVietnamMs =
      vietnamTimeMs < startTodayVietnamMs
        ? startTodayVietnamMs
        : startTodayVietnamMs + ONE_DAY_MS;
    return Math.max(1, nextStartVietnamMs - vietnamTimeMs);
  }

  private msUntilNextEfastFastWindowStart(value: Date) {
    const vietnamTimeMs = this.vietnamTimeMs(value);
    const vietnamDate = new Date(vietnamTimeMs);
    const startTodayVietnamMs = Date.UTC(
      vietnamDate.getUTCFullYear(),
      vietnamDate.getUTCMonth(),
      vietnamDate.getUTCDate(),
      EFAST_SYNC_START_HOUR_VN,
      0,
      0,
      0,
    );
    const nextStartVietnamMs =
      vietnamTimeMs < startTodayVietnamMs
        ? startTodayVietnamMs
        : startTodayVietnamMs + ONE_DAY_MS;
    return Math.max(1, nextStartVietnamMs - vietnamTimeMs);
  }

  private msUntilEfastNightWindowStart(value: Date) {
    const vietnamTimeMs = this.vietnamTimeMs(value);
    const vietnamDate = new Date(vietnamTimeMs);
    const nightStartVietnamMs = Date.UTC(
      vietnamDate.getUTCFullYear(),
      vietnamDate.getUTCMonth(),
      vietnamDate.getUTCDate(),
      EFAST_SYNC_END_HOUR_VN,
      1,
      0,
      0,
    );
    return Math.max(1, nightStartVietnamMs - vietnamTimeMs);
  }

  private vietnamTimeMs(value: Date) {
    return value.getTime() + VIETNAM_UTC_OFFSET_HOURS * 60 * 60 * 1000;
  }

  private clearMapTimer() {
    if (!this.mapHistorySyncTimer) return;
    clearTimeout(this.mapHistorySyncTimer);
    this.mapHistorySyncTimer = undefined;
  }

  private clearEfastTimer() {
    if (!this.efastSyncTimer) return;
    clearTimeout(this.efastSyncTimer);
    this.efastSyncTimer = undefined;
  }

  private logger() {
    return this.config?.logger ?? this.defaultLogger;
  }

  private requireConfig() {
    if (!this.config) {
      throw new Error('MapVietinSyncCoordinator chưa được cấu hình');
    }
    return this.config;
  }
}
