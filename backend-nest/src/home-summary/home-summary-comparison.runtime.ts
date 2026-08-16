import type { Logger } from '@nestjs/common';
import { safeLogError } from '../common/log-sanitizer';
import type { GetHomeSummaryQueryDto } from './home-summary.dto';
import { HOME_SALES_COMPARISON_METRIC_KEYS } from './home-summary-csv-comparison.runtime';
import type {
  HomeSalesComparisonMetricKey,
  HomeSummaryCsvComparison,
} from './home-summary-csv-comparison.runtime';
import type {
  HomeSummaryResponse,
  SummaryDateRange,
} from './home-summary.service';
import type { SalesReportSummaryScopeDescriptor } from '../sales-reports/sales-reports.service';

export type HomeSummaryComparisonMetricResponse = {
  value: number | null;
  deltaPercent: number | null;
  status: 'AVAILABLE' | 'NEW' | 'UNAVAILABLE';
};

export type HomeSummaryComparisonPeriodResponse = {
  startDate: string;
  endDate: string;
  source: 'OPSHUB' | 'HYBRID_CSV' | 'UNAVAILABLE';
  complete: boolean;
  metrics: Record<
    HomeSalesComparisonMetricKey,
    HomeSummaryComparisonMetricResponse
  >;
};

export type HomeSummaryComparisonsResponse = {
  previousMonth: HomeSummaryComparisonPeriodResponse;
  previousYear: HomeSummaryComparisonPeriodResponse;
};

export type HomeSummaryComparisonComputeOptions = {
  skipComparisons?: boolean;
};

export type HomeSummaryComparisonCallbacks = {
  overlayActiveCsvHistory: (
    range: SummaryDateRange,
    scope: SalesReportSummaryScopeDescriptor,
  ) => Promise<HomeSummaryCsvComparison | null>;
  computeSummary: (
    user: any,
    query: GetHomeSummaryQueryDto,
    options?: HomeSummaryComparisonComputeOptions,
  ) => Promise<HomeSummaryResponse>;
  dateOnlyUtc: (value: string) => Date;
  logger: Pick<Logger, 'log' | 'warn'>;
};

/**
 * Owns comparison-period composition while HomeSummaryService remains the
 * stable public facade. CSV coverage stays in HomeSummaryCsvComparisonRuntime;
 * this collaborator only coordinates fallback, metric semantics and ranges.
 */
export class HomeSummaryComparisonRuntime {
  constructor(private readonly callbacks: HomeSummaryComparisonCallbacks) {}

  async buildComparisons(
    user: any,
    query: GetHomeSummaryQueryDto,
    currentRange: SummaryDateRange,
    current: HomeSummaryResponse,
    scope: SalesReportSummaryScopeDescriptor,
  ): Promise<HomeSummaryComparisonsResponse> {
    const previousMonthRange = this.shiftSummaryRange(currentRange, -1, 0);
    const previousYearRange = this.shiftSummaryRange(currentRange, 0, -1);
    const [previousMonth, previousYear] = await Promise.all([
      this.buildComparisonPeriod(
        user,
        query,
        current,
        previousMonthRange,
        scope,
      ),
      this.buildComparisonPeriod(
        user,
        query,
        current,
        previousYearRange,
        scope,
      ),
    ]);
    return { previousMonth, previousYear };
  }

  async buildComparisonPeriod(
    user: any,
    query: GetHomeSummaryQueryDto,
    current: HomeSummaryResponse,
    range: SummaryDateRange,
    scope: SalesReportSummaryScopeDescriptor,
  ): Promise<HomeSummaryComparisonPeriodResponse> {
    const startedAt = Date.now();
    try {
      const csvComposition = await this.callbacks.overlayActiveCsvHistory(
        range,
        scope,
      );
      let values: Record<HomeSalesComparisonMetricKey, number>;
      let source: HomeSummaryComparisonPeriodResponse['source'];
      let unavailable: Set<HomeSalesComparisonMetricKey>;
      if (csvComposition) {
        values = csvComposition.values;
        source = csvComposition.source;
        unavailable = csvComposition.unavailable;
      } else {
        const previous = await this.callbacks.computeSummary(
          user,
          {
            ...query,
            date: undefined,
            startDate: range.startDate,
            endDate: range.endDate,
            includeDailySeries: 'false',
            includeComparisons: 'false',
          },
          { skipComparisons: true },
        );
        if (!previous.available || !previous.salesAvailable) {
          return this.unavailableComparisonPeriod(range);
        }
        values = this.comparisonValues(previous);
        source = 'OPSHUB';
        unavailable = new Set<HomeSalesComparisonMetricKey>();
      }
      const currentValues = this.comparisonValues(current);
      const metrics = {} as Record<
        HomeSalesComparisonMetricKey,
        HomeSummaryComparisonMetricResponse
      >;
      for (const key of HOME_SALES_COMPARISON_METRIC_KEYS) {
        metrics[key] = unavailable.has(key)
          ? { value: null, deltaPercent: null, status: 'UNAVAILABLE' }
          : this.comparisonMetric(currentValues[key], values[key]);
      }
      this.callbacks.logger.log(
        `Home comparison period loaded: startDate=${range.startDate} endDate=${range.endDate} source=${source} unavailableMetrics=${unavailable.size} durationMs=${Date.now() - startedAt}`,
      );
      return {
        startDate: range.startDate,
        endDate: range.endDate,
        source,
        complete: unavailable.size === 0,
        metrics,
      };
    } catch (error) {
      this.callbacks.logger.warn(
        `Home comparison period unavailable: startDate=${range.startDate} endDate=${range.endDate} error=${safeLogError(error)} durationMs=${Date.now() - startedAt}`,
      );
      return this.unavailableComparisonPeriod(range);
    }
  }

  comparisonValues(response: HomeSummaryResponse) {
    return Object.fromEntries(
      HOME_SALES_COMPARISON_METRIC_KEYS.map((key) => [
        key,
        Number(response[key] ?? 0),
      ]),
    ) as Record<HomeSalesComparisonMetricKey, number>;
  }

  comparisonMetric(
    current: number,
    previous: number,
  ): HomeSummaryComparisonMetricResponse {
    if (previous === 0 && current > 0) {
      return { value: previous, deltaPercent: null, status: 'NEW' };
    }
    const deltaPercent =
      previous === 0
        ? 0
        : Number(
            (((current - previous) / Math.abs(previous)) * 100).toFixed(2),
          );
    return { value: previous, deltaPercent, status: 'AVAILABLE' };
  }

  unavailableComparisonPeriod(
    range: Pick<SummaryDateRange, 'startDate' | 'endDate'>,
  ): HomeSummaryComparisonPeriodResponse {
    return {
      startDate: range.startDate,
      endDate: range.endDate,
      source: 'UNAVAILABLE',
      complete: false,
      metrics: Object.fromEntries(
        HOME_SALES_COMPARISON_METRIC_KEYS.map((key) => [
          key,
          { value: null, deltaPercent: null, status: 'UNAVAILABLE' },
        ]),
      ) as Record<
        HomeSalesComparisonMetricKey,
        HomeSummaryComparisonMetricResponse
      >,
    };
  }

  shiftSummaryRange(
    range: Pick<SummaryDateRange, 'startDate' | 'endDate'>,
    monthDelta: number,
    yearDelta: number,
  ): SummaryDateRange {
    const startDate = this.shiftDateOnly(
      range.startDate,
      monthDelta,
      yearDelta,
    );
    const endDate = this.shiftDateOnly(range.endDate, monthDelta, yearDelta);
    return {
      startDate,
      endDate,
      legacyDate: null,
      start: this.callbacks.dateOnlyUtc(startDate),
      end: new Date(`${endDate}T23:59:59.999Z`),
    };
  }

  shiftDateOnly(value: string, monthDelta: number, yearDelta: number) {
    const source = this.callbacks.dateOnlyUtc(value);
    const targetMonthIndex =
      source.getUTCFullYear() * 12 +
      source.getUTCMonth() +
      monthDelta +
      yearDelta * 12;
    const year = Math.floor(targetMonthIndex / 12);
    const month = ((targetMonthIndex % 12) + 12) % 12;
    const day = Math.min(
      source.getUTCDate(),
      new Date(Date.UTC(year, month + 1, 0)).getUTCDate(),
    );
    return `${year}-${String(month + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
  }
}
