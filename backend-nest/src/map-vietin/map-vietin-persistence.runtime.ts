import { Logger, type LoggerService } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { createHash } from 'crypto';
import { withPostgresDeadlockRetry } from '../common/postgres-deadlock-retry';
import { PaymentNotificationsService } from '../payment-notifications/payment-notifications.service';
import { PrismaService } from '../prisma/prisma.service';
import {
  classifyMapVietinIncomeType,
  MAP_VIETIN_INCOME_TYPE,
} from './income-type';
import {
  conflictingStatementProviderIdentifiers,
  mergeStatementProviderIdentifiers,
  resolveStoredStatementNumber,
} from './statement-identifiers';

const DEFAULT_MAP_SYNC_FINGERPRINT_CACHE_TTL_MS = 5 * 60 * 1000;
const DEFAULT_MAP_SYNC_FINGERPRINT_CACHE_MAX_ENTRIES = 20_000;
const MAX_MAP_SYNC_FINGERPRINT_CACHE_ENTRIES = 100_000;
const ORDER_SOURCE_AUTO = 'AUTO';
const ORDER_SOURCE_MANUAL = 'MANUAL';
const ORDER_SOURCE_OFFSET = 'OFFSET';
const ORDER_SOURCE_ERP_REPLACEMENT = 'ERP_REPLACEMENT';
const INCOME_TYPE_SOURCE_AUTO = 'AUTO';
const INCOME_TYPE_SOURCE_MANUAL = 'MANUAL';

export type MapTransactionRow = Record<string, unknown>;

export type MapPersistStats = {
  updated: number;
  unchanged: number;
  cacheHits: number;
};

type MapSyncFingerprintCacheEntry = {
  fingerprint: string;
  expiresAt: number;
};

type PersistenceLogger = Pick<LoggerService, 'log' | 'warn' | 'error'>;

type NormalizedMapTransaction = {
  storeCode: string | null;
  transactionKey: string;
  transactionNumber: string | null;
  amount: number;
  content: string;
  orders: string[];
  orderSource: string;
  status: string | null;
  paidAt: Date | null;
  payerName: string | null;
  payerAccount: string | null;
  incomeType: string;
  incomeTypeSource: string;
  rawData: Prisma.InputJsonObject;
};

export type MapVietinPersistenceRuntimeConfig = {
  prisma: PrismaService;
  paymentNotifications?: Pick<
    PaymentNotificationsService,
    'createForTransaction'
  >;
  logger?: PersistenceLogger;
  amountKeys: string[];
  contentKeys: string[];
  statusKeys: string[];
  transactionNumberKeys: string[];
  transactionReferenceKeys: string[];
  payerNameKeys: string[];
  payerAccountKeys: string[];
  readAmount: (row: MapTransactionRow) => number | null;
  isSuccessfulTransaction: (row: MapTransactionRow) => boolean;
  readFirstText: (row: MapTransactionRow, keys: string[]) => string;
  readTransactionTime: (row: MapTransactionRow) => Date | null;
  extractOrderCodesFromContent: (content: string) => string[];
  isEfastMapTransactionRow: (row: MapTransactionRow) => boolean;
  rawDataAsMapRow: (
    value?: Prisma.JsonValue | null,
  ) => MapTransactionRow | null;
  readPositiveInt: (name: string, fallback: number) => number;
  safeError: (error: unknown) => string;
};

/**
 * Owns transaction canonicalization, deduplication and persistence. The
 * MapVietinService remains the stable product facade and keeps provider,
 * account-routing and quarantine orchestration outside this runtime.
 */
export class MapVietinPersistenceRuntime {
  private readonly defaultLogger = new Logger(MapVietinPersistenceRuntime.name);
  private readonly mapSyncFingerprintCache = new Map<
    string,
    MapSyncFingerprintCacheEntry
  >();
  private persistenceQueue: Promise<void> = Promise.resolve();

  constructor(private readonly config: MapVietinPersistenceRuntimeConfig) {}

  clearFingerprintCache() {
    this.mapSyncFingerprintCache.clear();
  }

  normalizeTransaction(
    storeCode: string | null,
    row: MapTransactionRow,
  ): NormalizedMapTransaction | null {
    const amount = this.config.readAmount(row);
    if (!amount || amount <= 0) return null;
    if (!this.config.isSuccessfulTransaction(row)) return null;
    const content = this.config.readFirstText(row, this.config.contentKeys);
    const transactionNumber = this.config.readFirstText(
      row,
      this.config.transactionNumberKeys,
    );
    const paidAt = this.config.readTransactionTime(row);
    const status = this.config.readFirstText(row, this.config.statusKeys);
    const payerName = this.config.readFirstText(row, this.config.payerNameKeys);
    const payerAccount = this.config.readFirstText(
      row,
      this.config.payerAccountKeys,
    );
    const orders = this.config.extractOrderCodesFromContent(content);
    const canonicalStatementIdentifier =
      this.canonicalStatementIdentifierForRow(row);
    const fallback = [
      transactionNumber,
      amount,
      paidAt?.toISOString() ?? '',
      content,
    ].join('|');
    const identity = canonicalStatementIdentifier
      ? `STATEMENT|${canonicalStatementIdentifier}`
      : `FALLBACK|${fallback}`;

    return {
      storeCode,
      transactionKey: this.transactionKeyForIdentity(storeCode, identity),
      transactionNumber: transactionNumber || null,
      amount,
      content,
      orders,
      orderSource: ORDER_SOURCE_AUTO,
      status: status || null,
      paidAt,
      payerName: payerName || null,
      payerAccount: payerAccount || null,
      incomeType: classifyMapVietinIncomeType(content, payerAccount),
      incomeTypeSource: INCOME_TYPE_SOURCE_AUTO,
      rawData: mergeStatementProviderIdentifiers(row, {
        transactionNumber: transactionNumber || null,
        rawData: row,
      }) as Prisma.InputJsonObject,
    };
  }

  async persistTransactions(
    storeCode: string | null,
    rows: unknown[],
    stats: MapPersistStats = { updated: 0, unchanged: 0, cacheHits: 0 },
  ) {
    let releaseQueue!: () => void;
    const previous = this.persistenceQueue;
    this.persistenceQueue = new Promise<void>((resolve) => {
      releaseQueue = resolve;
    });
    await previous;
    try {
      return await this.persistTransactionsUnlocked(storeCode, rows, stats);
    } finally {
      releaseQueue();
    }
  }

  private async persistTransactionsUnlocked(
    storeCode: string | null,
    rows: unknown[],
    stats: MapPersistStats,
  ) {
    let created = 0;
    let withOrders = 0;
    let withoutOrders = 0;
    let manualProtected = 0;
    let offsetProtected = 0;
    let manualIncomeTypeProtected = 0;
    let duplicateStatementSkipped = 0;
    let duplicateFingerprintSkipped = 0;
    let identifierEnriched = 0;
    let identifierConflicts = 0;
    let ambiguousFingerprintSkipped = 0;
    let salesIncome = 0;
    let partnerInternalIncome = 0;
    for (const raw of rows) {
      if (!raw || typeof raw !== 'object') continue;
      const row = raw as MapTransactionRow;
      const normalized = this.normalizeTransaction(storeCode, row);
      if (!normalized) continue;
      if (normalized.incomeType === MAP_VIETIN_INCOME_TYPE.PARTNER_INTERNAL) {
        partnerInternalIncome += 1;
      } else {
        salesIncome += 1;
      }
      const syncFingerprint = this.mapSyncFingerprint(normalized);
      if (
        this.mapSyncFingerprintCacheHit(
          normalized.transactionKey,
          syncFingerprint,
        )
      ) {
        stats.unchanged += 1;
        stats.cacheHits += 1;
        continue;
      }
      let existing = await this.config.prisma.mapVietinTransaction.findUnique({
        where: { transactionKey: normalized.transactionKey },
      });
      if (!existing) {
        const legacyTransactionKey = this.legacyTransactionKeyForRow(
          storeCode,
          row,
        );
        if (legacyTransactionKey !== normalized.transactionKey) {
          existing = await this.config.prisma.mapVietinTransaction.findUnique({
            where: { transactionKey: legacyTransactionKey },
          });
        }
      }
      if (!existing) {
        const existingStatement = await this.findExistingTransactionByStatement(
          normalized.transactionKey,
          row,
        );
        if (existingStatement) {
          duplicateStatementSkipped += 1;
          const enrichment = await this.enrichStoredProviderIdentifiers(
            existingStatement,
            normalized,
            'statement_identifier',
          );
          identifierEnriched += enrichment.updated ? 1 : 0;
          stats.updated += enrichment.updated ? 1 : 0;
          identifierConflicts += enrichment.conflict ? 1 : 0;
          this.rememberMapSyncFingerprint(
            normalized.transactionKey,
            syncFingerprint,
          );
          continue;
        }
        const fingerprintResult =
          await this.findExistingTransactionByBankFingerprint(
            normalized.transactionKey,
            normalized,
            row,
          );
        if (fingerprintResult.ambiguousCount > 0) {
          ambiguousFingerprintSkipped += 1;
          this.logger().warn(
            `MAP sync identifier enrichment stopped for ambiguous bank fingerprint: incoming=${normalized.transactionKey} store=${normalized.storeCode || 'null'} candidates=${fingerprintResult.ambiguousCount} source=${this.config.isEfastMapTransactionRow(row) ? 'VIETIN_EFAST' : 'MAP'}`,
          );
          this.rememberMapSyncFingerprint(
            normalized.transactionKey,
            syncFingerprint,
          );
          continue;
        }
        if (fingerprintResult.match) {
          duplicateFingerprintSkipped += 1;
          const enrichment = await this.enrichStoredProviderIdentifiers(
            fingerprintResult.match,
            normalized,
            'bank_fingerprint',
          );
          identifierEnriched += enrichment.updated ? 1 : 0;
          stats.updated += enrichment.updated ? 1 : 0;
          identifierConflicts += enrichment.conflict ? 1 : 0;
          this.logger().warn(
            `MAP sync duplicate enriched by bank fingerprint: incoming=${normalized.transactionKey} existing=${fingerprintResult.match.transactionKey} store=${normalized.storeCode || 'null'} source=${this.config.isEfastMapTransactionRow(row) ? 'VIETIN_EFAST' : 'MAP'} enriched=${enrichment.updated} conflict=${enrichment.conflict}`,
          );
          this.rememberMapSyncFingerprint(
            normalized.transactionKey,
            syncFingerprint,
          );
          continue;
        }
      }
      if (normalized.orders.length > 0) withOrders += 1;
      else withoutOrders += 1;
      if (!existing) created += 1;
      const preservesProtectedOrders =
        existing?.orderSource === ORDER_SOURCE_MANUAL ||
        existing?.orderSource === ORDER_SOURCE_OFFSET ||
        existing?.orderSource === ORDER_SOURCE_ERP_REPLACEMENT;
      const preservesManualIncomeType =
        existing?.incomeTypeSource === INCOME_TYPE_SOURCE_MANUAL;
      if (preservesManualIncomeType) manualIncomeTypeProtected += 1;
      if (existing?.orderSource === ORDER_SOURCE_MANUAL) manualProtected += 1;
      if (existing?.orderSource === ORDER_SOURCE_OFFSET) offsetProtected += 1;
      const updateData = {
        transactionNumber: normalized.transactionNumber,
        amount: normalized.amount,
        content: normalized.content,
        ...(preservesManualIncomeType
          ? {}
          : {
              incomeType: normalized.incomeType,
              incomeTypeSource: INCOME_TYPE_SOURCE_AUTO,
            }),
        ...(preservesProtectedOrders
          ? {}
          : { orders: normalized.orders, orderSource: ORDER_SOURCE_AUTO }),
        status: normalized.status,
        paidAt: normalized.paidAt,
        payerName: normalized.payerName,
        payerAccount: normalized.payerAccount,
        rawData: mergeStatementProviderIdentifiers(
          normalized.rawData,
          {
            transactionNumber: existing?.transactionNumber,
            rawData: existing?.rawData,
          },
          {
            transactionNumber: normalized.transactionNumber,
            rawData: normalized.rawData,
          },
        ) as Prisma.InputJsonObject,
      };
      const isNoOp =
        existing && this.mapTransactionSyncIsNoOp(existing, updateData);
      const stored = isNoOp
        ? existing
        : await withPostgresDeadlockRetry(
            () =>
              this.config.prisma.mapVietinTransaction.upsert({
                where: {
                  transactionKey:
                    existing?.transactionKey ?? normalized.transactionKey,
                },
                create: normalized,
                update: updateData,
              }),
            { operation: 'map_vietin_ingest_upsert', logger: this.logger() },
          );
      if (isNoOp) stats.unchanged += 1;
      else if (existing) stats.updated += 1;
      this.rememberMapSyncFingerprint(
        normalized.transactionKey,
        syncFingerprint,
      );
      if (
        !existing &&
        stored?.id &&
        stored.storeCode &&
        this.config.paymentNotifications
      ) {
        const storedWithStore = stored as typeof stored & { storeCode: string };
        void this.config.paymentNotifications
          .createForTransaction(storedWithStore)
          .catch((error) => {
            this.logger().warn(
              `Payment notification failed for ${stored.id}: ${this.config.safeError(error)}`,
            );
          });
      }
    }
    if (
      created > 0 ||
      stats.updated > 0 ||
      duplicateStatementSkipped > 0 ||
      duplicateFingerprintSkipped > 0 ||
      ambiguousFingerprintSkipped > 0
    ) {
      const storeLabel = storeCode || 'null';
      this.logger().log(
        `MAP sync order extraction: store=${storeLabel} created=${created} updated=${stats.updated} unchanged=${stats.unchanged} withOrders=${withOrders} withoutOrders=${withoutOrders} salesIncome=${salesIncome} partnerInternalIncome=${partnerInternalIncome} manualProtected=${manualProtected} offsetProtected=${offsetProtected} manualIncomeTypeProtected=${manualIncomeTypeProtected} duplicateStatementSkipped=${duplicateStatementSkipped} duplicateFingerprintSkipped=${duplicateFingerprintSkipped} identifierEnriched=${identifierEnriched} identifierConflicts=${identifierConflicts} ambiguousFingerprintSkipped=${ambiguousFingerprintSkipped}`,
      );
    }
    return created;
  }

  private async enrichStoredProviderIdentifiers(
    existing: {
      id: string;
      transactionKey: string;
      transactionNumber?: string | null;
      rawData?: Prisma.JsonValue | null;
    },
    incoming: {
      transactionNumber?: string | null;
      rawData: Prisma.InputJsonObject;
    },
    reason: 'statement_identifier' | 'bank_fingerprint',
  ) {
    const conflicts = conflictingStatementProviderIdentifiers(
      existing,
      incoming,
    );
    if (conflicts.length > 0) {
      this.logger().warn(
        `MAP sync identifier enrichment conflict: transaction=${existing.id} reason=${reason} fields=${conflicts.join(',')}`,
      );
      return { updated: false, conflict: true };
    }
    const rawData = mergeStatementProviderIdentifiers(
      existing.rawData,
      existing,
      incoming,
    ) as Prisma.InputJsonObject;
    if (this.mapSyncValueEquals(existing.rawData, rawData)) {
      return { updated: false, conflict: false };
    }
    const statementNumber = resolveStoredStatementNumber({
      transactionNumber: existing.transactionNumber,
      rawData,
    });
    await this.config.prisma.$transaction(async (tx) => {
      await tx.mapVietinTransaction.update({
        where: { id: existing.id },
        data: { rawData },
      });
      if (statementNumber) {
        await tx.vietQrPaymentIntent.updateMany({
          where: { matchedTransactionId: existing.id },
          data: { matchedTransactionNumber: statementNumber },
        });
      }
    });
    this.logger().log(
      `MAP sync identifier enrichment succeeded: transaction=${existing.id} reason=${reason} vietQrCanonicalUpdated=${Boolean(statementNumber)}`,
    );
    return { updated: true, conflict: false };
  }

  private async findExistingTransactionByStatement(
    transactionKey: string,
    row: MapTransactionRow,
  ) {
    const identifiers = this.statementIdentifiersForRow(row);
    if (identifiers.length === 0) return null;
    const referenceWhere = identifiers.flatMap((identifier) => [
      { transactionNumber: identifier },
      { rawData: { path: ['txnReference'], equals: identifier } },
      { rawData: { path: ['trxId'], equals: identifier } },
      { rawData: { path: ['trxRefNo'], equals: identifier } },
      {
        rawData: {
          path: ['providerIdentifiers', 'mapTransactionNumber'],
          equals: identifier,
        },
      },
      {
        rawData: {
          path: ['providerIdentifiers', 'efastTrxId'],
          equals: identifier,
        },
      },
      {
        rawData: {
          path: ['providerIdentifiers', 'efastTrxRefNo'],
          equals: identifier,
        },
      },
    ]);
    return this.config.prisma.mapVietinTransaction.findFirst({
      where: { transactionKey: { not: transactionKey }, OR: referenceWhere },
      select: {
        id: true,
        transactionKey: true,
        transactionNumber: true,
        storeCode: true,
        rawData: true,
      },
    });
  }

  private async findExistingTransactionByBankFingerprint(
    transactionKey: string,
    normalized: Pick<
      NormalizedMapTransaction,
      'storeCode' | 'amount' | 'content' | 'paidAt'
    >,
    row: MapTransactionRow,
  ) {
    if (
      !normalized.storeCode ||
      !normalized.paidAt ||
      !normalized.content.trim()
    ) {
      return { match: null, ambiguousCount: 0 };
    }
    const incomingIsEfast = this.config.isEfastMapTransactionRow(row);
    const candidates = await this.config.prisma.mapVietinTransaction.findMany({
      where: {
        transactionKey: { not: transactionKey },
        storeCode: normalized.storeCode,
        amount: normalized.amount,
        paidAt: normalized.paidAt,
        content: normalized.content,
      },
      select: {
        id: true,
        transactionKey: true,
        transactionNumber: true,
        storeCode: true,
        rawData: true,
      },
      take: 5,
    });
    const oppositeSourceCandidates = candidates.filter((candidate) => {
      const candidateRaw = this.config.rawDataAsMapRow(candidate.rawData);
      const candidateIsEfast = candidateRaw
        ? this.config.isEfastMapTransactionRow(candidateRaw)
        : false;
      return candidateIsEfast !== incomingIsEfast;
    });
    if (oppositeSourceCandidates.length !== 1) {
      return {
        match: null,
        ambiguousCount:
          oppositeSourceCandidates.length > 1
            ? oppositeSourceCandidates.length
            : 0,
      };
    }
    return { match: oppositeSourceCandidates[0], ambiguousCount: 0 };
  }

  private statementIdentifiersForRow(row: MapTransactionRow) {
    const seen = new Set<string>();
    const output: string[] = [];
    const candidates = [
      this.config.readFirstText(row, this.config.transactionNumberKeys),
      this.config.readFirstText(row, this.config.transactionReferenceKeys),
      this.readText(row, 'trxId'),
      this.readText(row, 'trxRefNo'),
      this.readText(row, 'numberOrder'),
    ];
    for (const candidate of candidates) {
      const value = this.cleanText(candidate);
      if (!value || seen.has(value)) continue;
      seen.add(value);
      output.push(value);
    }
    return output;
  }

  private canonicalStatementIdentifierForRow(row: MapTransactionRow) {
    const candidates = this.config.isEfastMapTransactionRow(row)
      ? [
          this.readText(row, 'trxId'),
          this.config.readFirstText(row, this.config.transactionNumberKeys),
          this.readText(row, 'trxRefNo'),
          this.config.readFirstText(row, this.config.transactionReferenceKeys),
        ]
      : [
          this.readText(row, 'txnReference'),
          this.readText(row, 'trxId'),
          this.readText(row, 'trxRefNo'),
          this.config.readFirstText(row, this.config.transactionNumberKeys),
        ];
    for (const candidate of candidates) {
      const value = this.cleanText(candidate).toUpperCase();
      if (value) return value;
    }
    return '';
  }

  private legacyTransactionKeyForRow(
    storeCode: string | null,
    row: MapTransactionRow,
  ) {
    const transactionNumber = this.config.readFirstText(
      row,
      this.config.transactionNumberKeys,
    );
    const amount = this.config.readAmount(row) ?? 0;
    const paidAt = this.config.readTransactionTime(row);
    const content = this.config.readFirstText(row, this.config.contentKeys);
    const fallback = [
      transactionNumber,
      amount,
      paidAt?.toISOString() ?? '',
      content,
    ].join('|');
    return this.transactionKeyForIdentity(storeCode, fallback);
  }

  private transactionKeyForIdentity(
    storeCode: string | null,
    identity: string,
  ) {
    const storeKey = storeCode || '__NO_STORE__';
    const hash = createHash('sha256')
      .update(`${storeKey}|${identity}`)
      .digest('hex');
    return `${storeKey}:${hash}`;
  }

  private mapTransactionSyncIsNoOp(
    existing: Record<string, unknown>,
    updateData: Record<string, unknown>,
  ) {
    return Object.entries(updateData).every(([key, value]) =>
      this.mapSyncValueEquals(existing[key], value),
    );
  }

  private mapSyncValueEquals(left: unknown, right: unknown): boolean {
    if (left instanceof Date || right instanceof Date) {
      if (!(left instanceof Date) || !(right instanceof Date)) return false;
      return left.getTime() === right.getTime();
    }
    if (Array.isArray(left) || Array.isArray(right)) {
      if (!Array.isArray(left) || !Array.isArray(right)) return false;
      if (left.length !== right.length) return false;
      return left.every((value, index) =>
        this.mapSyncValueEquals(value, right[index]),
      );
    }
    if (
      left !== null &&
      right !== null &&
      typeof left === 'object' &&
      typeof right === 'object'
    ) {
      return this.stableJson(left) === this.stableJson(right);
    }
    return left === right;
  }

  private mapSyncFingerprint(normalized: Record<string, unknown>) {
    return createHash('sha256')
      .update(this.stableJson(normalized))
      .digest('hex');
  }

  private mapSyncFingerprintCacheHit(key: string, fingerprint: string) {
    const cached = this.mapSyncFingerprintCache.get(key);
    if (!cached) return false;
    if (cached.expiresAt <= Date.now() || cached.fingerprint !== fingerprint) {
      this.mapSyncFingerprintCache.delete(key);
      return false;
    }
    this.mapSyncFingerprintCache.delete(key);
    this.mapSyncFingerprintCache.set(key, cached);
    return true;
  }

  private rememberMapSyncFingerprint(key: string, fingerprint: string) {
    const maxEntries = Math.min(
      MAX_MAP_SYNC_FINGERPRINT_CACHE_ENTRIES,
      this.config.readPositiveInt(
        'MAP_VIETIN_SYNC_FINGERPRINT_CACHE_MAX_ENTRIES',
        DEFAULT_MAP_SYNC_FINGERPRINT_CACHE_MAX_ENTRIES,
      ),
    );
    while (this.mapSyncFingerprintCache.size >= maxEntries) {
      const oldestKey = this.mapSyncFingerprintCache.keys().next().value as
        | string
        | undefined;
      if (!oldestKey) break;
      this.mapSyncFingerprintCache.delete(oldestKey);
    }
    this.mapSyncFingerprintCache.set(key, {
      fingerprint,
      expiresAt:
        Date.now() +
        this.config.readPositiveInt(
          'MAP_VIETIN_SYNC_FINGERPRINT_CACHE_TTL_MS',
          DEFAULT_MAP_SYNC_FINGERPRINT_CACHE_TTL_MS,
        ),
    });
  }

  private stableJson(value: unknown): string {
    const normalize = (input: unknown): unknown => {
      if (Array.isArray(input)) return input.map(normalize);
      if (input && typeof input === 'object') {
        return Object.fromEntries(
          Object.entries(input as Record<string, unknown>)
            .sort(([left], [right]) => left.localeCompare(right))
            .map(([key, nested]) => [key, normalize(nested)]),
        );
      }
      return input;
    };
    return JSON.stringify(normalize(value));
  }

  private cleanText(value: unknown) {
    if (value === null || value === undefined) return '';
    return String(value as string).trim();
  }

  private readText(row: MapTransactionRow, key: string) {
    return this.cleanText(row[key]);
  }

  private logger() {
    return this.config.logger ?? this.defaultLogger;
  }
}
