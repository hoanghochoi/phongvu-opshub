import { Logger } from '@nestjs/common';
import { logFingerprint, safeLogError } from '../common/log-sanitizer';
import type { GetHomeSummaryQueryDto } from './home-summary.dto';
import type {
  HomeSummaryComputationContext,
  HomeSummaryInFlightEntry,
  HomeSummaryProjectionInvalidation,
  HomeSummaryProjectionSnapshot,
  HomeSummaryResponse,
  HomeSummaryResponseCacheEntry,
  HomeSummaryScopeOptionResponse,
  HomeSummarySupportCacheEntry,
  SummaryDateRange,
} from './home-summary.service';

const HOME_SUMMARY_RESPONSE_CACHE_TTL_MS = 60_000;
const HOME_SUMMARY_SUPPORT_CACHE_TTL_MS = 5_000;
const HOME_SUMMARY_CACHE_DIAGNOSTIC_LOG_INTERVAL_MS = 15_000;
const HOME_SUMMARY_RESPONSE_REFRESH_AHEAD_MIN_MS = 30_000;
const HOME_SUMMARY_RESPONSE_REFRESH_AHEAD_SPREAD_MS = 20_000;
const MAX_HOME_SUMMARY_RESPONSE_CACHE_ENTRIES = 1000;
const HOME_SUMMARY_SCOPE_OPTIONS_L1_TTL_MS = 5_000;
const MAX_HOME_SUMMARY_SCOPE_OPTIONS_CACHE_ENTRIES = 1000;

type HomeSummaryScopeOptionsCacheEntry = {
  expiresAt: number;
  response: HomeSummaryScopeOptionResponse[];
};

type CacheRuntimeComputeSummary = (
  user: any,
  query: GetHomeSummaryQueryDto,
  options?: { skipComparisons?: boolean },
) => Promise<HomeSummaryResponse>;

type CacheRuntimeExtendDailySeries = (
  user: any,
  query: GetHomeSummaryQueryDto,
  range: SummaryDateRange,
  legacyResponse: HomeSummaryResponse,
  context: HomeSummaryComputationContext,
) => Promise<HomeSummaryResponse>;

type CacheRuntimeCallbacks = {
  isCacheEnabled: () => boolean;
  responseCacheKey: (
    user: any,
    query: GetHomeSummaryQueryDto,
  ) => string;
  parseSummaryRange: (query: GetHomeSummaryQueryDto) => SummaryDateRange;
  summaryCacheCoverageRange: (
    range: Pick<SummaryDateRange, 'startDate' | 'endDate'>,
    query: GetHomeSummaryQueryDto,
  ) => Pick<SummaryDateRange, 'startDate' | 'endDate'>;
  rangeDateKeys: (startDate: string, endDate: string) => string[];
  computeSummary: CacheRuntimeComputeSummary;
  extendLegacySummaryWithDailySeries: CacheRuntimeExtendDailySeries;
  scopeOptionsCacheKey: (user: any) => string;
  loadScopeOptions: (
    contextUser: any,
    user: any,
    cacheKey: string,
    cacheLabel: string,
  ) => Promise<HomeSummaryScopeOptionResponse[]>;
};

/**
 * Owns Home Summary response/support cache state while the service remains the
 * stable API facade. All product computation and authorization stay in the
 * service and are supplied through constructor callbacks.
 */
export class HomeSummaryCacheRuntime {
  private readonly summaryResponseCache = new Map<
    string,
    HomeSummaryResponseCacheEntry
  >();
  private readonly summaryInFlight = new Map<
    string,
    HomeSummaryInFlightEntry
  >();
  private readonly projectionVersionsByResponse = new WeakMap<
    HomeSummaryResponse,
    Map<string, number>
  >();
  private readonly computationContextByResponse = new WeakMap<
    HomeSummaryResponse,
    HomeSummaryComputationContext
  >();
  private readonly projectionFreshnessCache = new Map<
    string,
    HomeSummarySupportCacheEntry<HomeSummaryProjectionSnapshot>
  >();
  private readonly projectionFreshnessInFlight = new Map<
    string,
    Promise<HomeSummaryProjectionSnapshot>
  >();
  private readonly salesProgressBundleCache = new Map<
    string,
    HomeSummarySupportCacheEntry<any>
  >();
  private readonly salesProgressBundleInFlight = new Map<
    string,
    Promise<any>
  >();
  private readonly scopedSalesProgressCache = new Map<
    string,
    HomeSummarySupportCacheEntry<any>
  >();
  private readonly scopedSalesProgressInFlight = new Map<
    string,
    Promise<any>
  >();
  private readonly cacheDiagnosticLogAtByBranch = new Map<string, number>();
  private supportCacheGeneration = 0;
  private readonly latestProjectionVersionByDate = new Map<string, number>();
  private readonly scopeOptionsCache = new Map<
    string,
    HomeSummaryScopeOptionsCacheEntry
  >();
  private readonly scopeOptionsInFlight = new Map<
    string,
    Promise<HomeSummaryScopeOptionResponse[]>
  >();

  constructor(
    private readonly logger: Logger,
    private readonly callbacks: CacheRuntimeCallbacks,
  ) {}

  /**
   * Internal characterization views for the stable service facade.
   *
   * These expose the same state objects that the pre-extraction tests used to
   * inspect. They are intentionally not part of the product API; production
   * cache behavior continues to be owned by this runtime.
   */
  get responseCacheState() {
    return this.summaryResponseCache;
  }

  get inFlightState() {
    return this.summaryInFlight;
  }

  get projectionVersionsState() {
    return this.projectionVersionsByResponse;
  }

  get computationContextState() {
    return this.computationContextByResponse;
  }

  get scopeOptionsCacheState() {
    return this.scopeOptionsCache;
  }

  async getSummary(
    user: any,
    query: GetHomeSummaryQueryDto,
  ): Promise<HomeSummaryResponse> {
    if (!this.callbacks.isCacheEnabled()) {
      return this.callbacks.computeSummary(user, query);
    }
    const cacheKey = this.callbacks.responseCacheKey(user, query);
    const cacheLabel = logFingerprint(cacheKey);
    const range = this.callbacks.parseSummaryRange(query);
    const cached = this.summaryResponseCache.get(cacheKey);
    const now = Date.now();
    if (cached && cached.expiresAt > now) {
      this.maybeStartSummaryRefreshAhead(
        cacheKey,
        cacheLabel,
        cached,
        user,
        query,
        range,
        now,
      );
      this.logCacheDiagnostic(
        'response_hit',
        `Home summary cache hit: key=${cacheLabel} ttlMs=${cached.expiresAt - now}`,
      );
      return cached.response;
    }
    if (cached) {
      this.summaryResponseCache.delete(cacheKey);
      this.logCacheDiagnostic(
        'response_expired',
        `Home summary cache expired: key=${cacheLabel}`,
      );
    }
    const pending = this.summaryInFlight.get(cacheKey);
    if (pending && !pending.invalidated) {
      this.logCacheDiagnostic(
        'response_join',
        `Home summary cache joined in-flight: key=${cacheLabel}`,
      );
      return pending.promise;
    }
    if (pending?.invalidated) {
      this.logger.log(
        `Home summary cache follow-up started: key=${cacheLabel} source=${pending.source}`,
      );
    }

    const dailyExtension = this.maybeStartDailySeriesExtension(
      cacheKey,
      cacheLabel,
      user,
      query,
      range,
      now,
    );
    if (dailyExtension) return dailyExtension;

    this.logger.log(`Home summary cache miss: key=${cacheLabel}`);
    return this.startSummaryLoad(
      cacheKey,
      cacheLabel,
      user,
      query,
      range,
      'miss',
    );
  }

  invalidateSummaryResponseCache(
    updates: HomeSummaryProjectionInvalidation[],
    source = 'projection_event',
  ) {
    const changedVersionsByDate = new Map<string, number | null>();
    let ignoredUpdates = 0;
    for (const update of updates) {
      const version = Number(update.projectionVersion);
      const validVersion = Number.isSafeInteger(version) && version > 0;
      for (const rawDate of update.affectedDates ?? []) {
        const date = String(rawDate).trim();
        if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
          ignoredUpdates += 1;
          continue;
        }
        if (!validVersion) {
          changedVersionsByDate.set(date, null);
          continue;
        }
        const previous = changedVersionsByDate.get(date);
        if (
          previous === null ||
          (previous !== undefined && version <= previous)
        ) {
          ignoredUpdates += 1;
          continue;
        }
        changedVersionsByDate.set(date, version);
      }
    }
    for (const [date, version] of changedVersionsByDate) {
      if (version === null) continue;
      const previous = this.latestProjectionVersionByDate.get(date) ?? 0;
      if (version <= previous) {
        changedVersionsByDate.delete(date);
        ignoredUpdates += 1;
        continue;
      }
      this.latestProjectionVersionByDate.set(date, version);
    }
    const invalidatedSupportEntries =
      changedVersionsByDate.size > 0 ? this.clearSummarySupportCaches() : 0;

    let invalidatedCacheEntries = 0;
    let coveredCacheEntries = 0;
    for (const [cacheKey, entry] of this.summaryResponseCache.entries()) {
      if (!this.cacheEntryNeedsInvalidation(entry, changedVersionsByDate)) {
        if (this.rangeOverlapsDates(entry, changedVersionsByDate.keys())) {
          coveredCacheEntries += 1;
        }
        continue;
      }
      this.summaryResponseCache.delete(cacheKey);
      invalidatedCacheEntries += 1;
    }

    let invalidatedInFlight = 0;
    for (const [cacheKey, entry] of this.summaryInFlight) {
      const cached = this.summaryResponseCache.get(cacheKey);
      if (
        entry.invalidated ||
        (cached &&
          !this.cacheEntryNeedsInvalidation(cached, changedVersionsByDate)) ||
        !this.rangeOverlapsDates(entry, changedVersionsByDate.keys())
      ) {
        continue;
      }
      entry.invalidated = true;
      invalidatedInFlight += 1;
    }

    this.logger.log(
      `Home summary cache invalidated: source=${source} affectedDates=${changedVersionsByDate.size} cacheEntries=${invalidatedCacheEntries} coveredCacheEntries=${coveredCacheEntries} supportEntries=${invalidatedSupportEntries} inFlightMarked=${invalidatedInFlight} ignoredUpdates=${ignoredUpdates}`,
    );
    return {
      affectedDates: changedVersionsByDate.size,
      invalidatedCacheEntries,
      coveredCacheEntries,
      invalidatedSupportEntries,
      invalidatedInFlight,
      ignoredUpdates,
    };
  }

  getProjectionVersions(response: HomeSummaryResponse) {
    return this.projectionVersionsByResponse.get(response);
  }

  setProjectionVersions(
    response: HomeSummaryResponse,
    versions: Map<string, number>,
  ) {
    this.projectionVersionsByResponse.set(response, versions);
  }

  getComputationContext(response: HomeSummaryResponse) {
    return this.computationContextByResponse.get(response);
  }

  setComputationContext(
    response: HomeSummaryResponse,
    context: HomeSummaryComputationContext,
  ) {
    this.computationContextByResponse.set(response, context);
  }

  async getScopeOptions(
    contextUser: any,
    user: any,
  ): Promise<HomeSummaryScopeOptionResponse[]> {
    const cacheKey = this.callbacks.scopeOptionsCacheKey(contextUser);
    const cacheLabel = logFingerprint(cacheKey);
    const now = Date.now();
    const cached = this.scopeOptionsCache.get(cacheKey);
    if (cached && cached.expiresAt > now) {
      this.logger.log(
        `Home summary scope options cache hit: key=${cacheLabel} ttlMs=${cached.expiresAt - now}`,
      );
      return cached.response;
    }
    if (cached) {
      this.scopeOptionsCache.delete(cacheKey);
      this.logger.log(
        `Home summary scope options cache expired: key=${cacheLabel}`,
      );
    }
    const pending = this.scopeOptionsInFlight.get(cacheKey);
    if (pending) {
      this.logger.log(
        `Home summary scope options cache joined in-flight: key=${cacheLabel}`,
      );
      return pending;
    }

    const pendingLoad = this.callbacks.loadScopeOptions(
      contextUser,
      user,
      cacheKey,
      cacheLabel,
    ).then((response) => {
      this.storeScopeOptionsCache(cacheKey, response);
      return response;
    });
    this.scopeOptionsInFlight.set(cacheKey, pendingLoad);
    try {
      return await pendingLoad;
    } finally {
      if (this.scopeOptionsInFlight.get(cacheKey) === pendingLoad) {
        this.scopeOptionsInFlight.delete(cacheKey);
      }
    }
  }

  async getOrLoadSummarySupportValue<T>(
    cacheName: 'projection_freshness' | 'principal_progress' | 'shared_scope_progress',
    key: string,
    label: string,
    loader: () => Promise<T>,
  ): Promise<T> {
    const cache =
      cacheName === 'projection_freshness'
        ? this.projectionFreshnessCache
        : cacheName === 'principal_progress'
          ? this.salesProgressBundleCache
          : this.scopedSalesProgressCache;
    const inFlight =
      cacheName === 'projection_freshness'
        ? this.projectionFreshnessInFlight
        : cacheName === 'principal_progress'
          ? this.salesProgressBundleInFlight
          : this.scopedSalesProgressInFlight;
    if (!this.callbacks.isCacheEnabled()) return loader();
    const now = Date.now();
    const cached = cache.get(key);
    if (cached && cached.expiresAt > now) {
      this.logCacheDiagnostic(
        `support_hit:${label}`,
        `Home summary support cache hit: type=${label}`,
      );
      return cached.value;
    }
    if (cached) cache.delete(key);
    const pending = inFlight.get(key);
    if (pending) {
      this.logCacheDiagnostic(
        `support_join:${label}`,
        `Home summary support cache joined in-flight: type=${label}`,
      );
      return pending;
    }

    const generation = this.supportCacheGeneration;
    let promise: Promise<T>;
    promise = loader()
      .then((value) => {
        if (generation !== this.supportCacheGeneration) return value;
        while (cache.size >= MAX_HOME_SUMMARY_RESPONSE_CACHE_ENTRIES) {
          const oldestKey = cache.keys().next().value;
          if (!oldestKey) break;
          cache.delete(oldestKey);
        }
        cache.set(key, {
          expiresAt: Date.now() + HOME_SUMMARY_SUPPORT_CACHE_TTL_MS,
          value,
        });
        return value;
      })
      .finally(() => {
        if (inFlight.get(key) === promise) inFlight.delete(key);
      });
    inFlight.set(key, promise);
    return promise;
  }

  private maybeStartSummaryRefreshAhead(
    cacheKey: string,
    cacheLabel: string,
    cached: HomeSummaryResponseCacheEntry,
    user: any,
    query: GetHomeSummaryQueryDto,
    range: SummaryDateRange,
    now: number,
  ) {
    if (cached.refreshAttempted || now < cached.refreshAfter) return;
    cached.refreshAttempted = true;
    const pending = this.summaryInFlight.get(cacheKey);
    if (pending && !pending.invalidated) return;
    this.logger.log(
      `Home summary cache refresh-ahead started: key=${cacheLabel} ttlMs=${cached.expiresAt - now}`,
    );
    void this.startSummaryLoad(
      cacheKey,
      cacheLabel,
      user,
      query,
      range,
      'refresh_ahead',
    ).catch((error) => {
      this.logger.warn(
        `Home summary cache refresh-ahead failed: key=${cacheLabel} error=${safeLogError(error)}`,
      );
    });
  }

  private startSummaryLoad(
    cacheKey: string,
    cacheLabel: string,
    user: any,
    query: GetHomeSummaryQueryDto,
    range: SummaryDateRange,
    source: HomeSummaryInFlightEntry['source'],
  ) {
    const cacheRange = this.callbacks.summaryCacheCoverageRange(range, query);
    let inFlight: HomeSummaryInFlightEntry;
    const promise = this.callbacks
      .computeSummary(user, query)
      .then((response) => {
        if (inFlight.invalidated) {
          this.logger.log(
            `Home summary cache stale store skipped: key=${cacheLabel} source=${source}`,
          );
          return response;
        }
        this.storeSummaryResponseCache(cacheKey, response, cacheRange);
        this.logger.log(
          `Home summary cache stored: key=${cacheLabel} source=${source} ttlMs=${HOME_SUMMARY_RESPONSE_CACHE_TTL_MS}`,
        );
        return response;
      })
      .finally(() => {
        if (this.summaryInFlight.get(cacheKey) === inFlight) {
          this.summaryInFlight.delete(cacheKey);
        }
      });
    inFlight = {
      promise,
      startDate: cacheRange.startDate,
      endDate: cacheRange.endDate,
      invalidated: false,
      source,
    };
    this.summaryInFlight.set(cacheKey, inFlight);
    return promise;
  }

  private maybeStartDailySeriesExtension(
    cacheKey: string,
    cacheLabel: string,
    user: any,
    query: GetHomeSummaryQueryDto,
    range: SummaryDateRange,
    now: number,
  ) {
    if (query.includeDailySeries !== 'true') return null;
    const days = this.callbacks.rangeDateKeys(
      range.startDate,
      range.endDate,
    ).length;
    if (days > 90) return null;
    const legacyQuery: GetHomeSummaryQueryDto = {
      ...query,
      includeDailySeries: 'false',
    };
    const legacyKey = this.callbacks.responseCacheKey(user, legacyQuery);
    const legacy = this.summaryResponseCache.get(legacyKey);
    if (!legacy || legacy.expiresAt <= now) return null;
    const context = this.computationContextByResponse.get(legacy.response);
    if (!context?.useProjection || !context.salesAvailable) return null;

    this.logger.log(
      `Home summary daily cache extension started: key=${cacheLabel} days=${days} scope=${context.salesMetricsScope.scope}`,
    );
    return this.startDailySeriesExtension(
      cacheKey,
      cacheLabel,
      user,
      query,
      range,
      legacy.response,
      context,
    );
  }

  private startDailySeriesExtension(
    cacheKey: string,
    cacheLabel: string,
    user: any,
    query: GetHomeSummaryQueryDto,
    range: SummaryDateRange,
    legacyResponse: HomeSummaryResponse,
    context: HomeSummaryComputationContext,
  ) {
    const cacheRange = this.callbacks.summaryCacheCoverageRange(range, query);
    let inFlight: HomeSummaryInFlightEntry;
    const startedAt = Date.now();
    const promise = this.callbacks
      .extendLegacySummaryWithDailySeries(
        user,
        query,
        range,
        legacyResponse,
        context,
      )
      .then((response) => {
        if (inFlight.invalidated) {
          this.logger.log(
            `Home summary cache stale store skipped: key=${cacheLabel} source=daily_extension`,
          );
          return response;
        }
        this.storeSummaryResponseCache(cacheKey, response, cacheRange);
        this.logger.log(
          `Home summary daily cache extension stored: key=${cacheLabel} scope=${context.salesMetricsScope.scope} points=${response.dailySeries?.length ?? 0} durationMs=${Date.now() - startedAt}`,
        );
        return response;
      })
      .finally(() => {
        if (this.summaryInFlight.get(cacheKey) === inFlight) {
          this.summaryInFlight.delete(cacheKey);
        }
      });
    inFlight = {
      promise,
      startDate: cacheRange.startDate,
      endDate: cacheRange.endDate,
      invalidated: false,
      source: 'daily_extension',
    };
    this.summaryInFlight.set(cacheKey, inFlight);
    return promise;
  }

  private cacheEntryNeedsInvalidation(
    entry: HomeSummaryResponseCacheEntry,
    changes: Map<string, number | null>,
  ) {
    for (const [date, version] of changes) {
      if (date < entry.startDate || date > entry.endDate) continue;
      if (version === null) return true;
      const cachedVersion = entry.projectionVersionsByDate.get(date) ?? 0;
      if (cachedVersion < version) return true;
    }
    return false;
  }

  private rangeOverlapsDates(
    range: Pick<SummaryDateRange, 'startDate' | 'endDate'>,
    dates: Iterable<string>,
  ) {
    for (const date of dates) {
      if (date >= range.startDate && date <= range.endDate) return true;
    }
    return false;
  }

  private clearSummarySupportCaches() {
    const entries =
      this.projectionFreshnessCache.size +
      this.salesProgressBundleCache.size +
      this.scopedSalesProgressCache.size;
    this.supportCacheGeneration += 1;
    this.projectionFreshnessCache.clear();
    this.salesProgressBundleCache.clear();
    this.scopedSalesProgressCache.clear();
    this.projectionFreshnessInFlight.clear();
    this.salesProgressBundleInFlight.clear();
    this.scopedSalesProgressInFlight.clear();
    return entries;
  }

  private storeSummaryResponseCache(
    cacheKey: string,
    response: HomeSummaryResponse,
    range: Pick<SummaryDateRange, 'startDate' | 'endDate'>,
  ) {
    while (
      this.summaryResponseCache.size >= MAX_HOME_SUMMARY_RESPONSE_CACHE_ENTRIES
    ) {
      const oldestKey = this.summaryResponseCache.keys().next().value;
      if (!oldestKey) break;
      this.summaryResponseCache.delete(oldestKey);
    }
    const storedAt = Date.now();
    const refreshSpread =
      Number.parseInt(logFingerprint(cacheKey).slice(0, 8), 16) %
      HOME_SUMMARY_RESPONSE_REFRESH_AHEAD_SPREAD_MS;
    const responseVersions = this.projectionVersionsByResponse.get(response);
    const fallbackVersion = response.freshness?.projectionVersion ?? 0;
    const projectionVersionsByDate = new Map<string, number>();
    for (const date of this.callbacks.rangeDateKeys(
      range.startDate,
      range.endDate,
    )) {
      projectionVersionsByDate.set(
        date,
        responseVersions?.get(date) ?? fallbackVersion,
      );
    }
    this.summaryResponseCache.set(cacheKey, {
      expiresAt: storedAt + HOME_SUMMARY_RESPONSE_CACHE_TTL_MS,
      refreshAfter:
        storedAt + HOME_SUMMARY_RESPONSE_REFRESH_AHEAD_MIN_MS + refreshSpread,
      refreshAttempted: false,
      startDate: range.startDate,
      endDate: range.endDate,
      projectionVersionsByDate,
      response,
    });
  }

  private storeScopeOptionsCache(
    cacheKey: string,
    response: HomeSummaryScopeOptionResponse[],
  ) {
    while (
      this.scopeOptionsCache.size >= MAX_HOME_SUMMARY_SCOPE_OPTIONS_CACHE_ENTRIES
    ) {
      const oldestKey = this.scopeOptionsCache.keys().next().value;
      if (!oldestKey) break;
      this.scopeOptionsCache.delete(oldestKey);
    }
    this.scopeOptionsCache.set(cacheKey, {
      expiresAt: Date.now() + HOME_SUMMARY_SCOPE_OPTIONS_L1_TTL_MS,
      response,
    });
  }

  private logCacheDiagnostic(branch: string, message: string) {
    const now = Date.now();
    const lastLoggedAt = this.cacheDiagnosticLogAtByBranch.get(branch) ?? 0;
    if (now - lastLoggedAt < HOME_SUMMARY_CACHE_DIAGNOSTIC_LOG_INTERVAL_MS) {
      return;
    }
    this.cacheDiagnosticLogAtByBranch.set(branch, now);
    this.logger.debug(message);
  }
}
